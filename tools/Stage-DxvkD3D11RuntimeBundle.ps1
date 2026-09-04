[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$BuildManifestPath,
 [Parameter(Mandatory)][string]$SmokeResultPath,
 [string[]]$RealShaderResultPath=@(),
 [Parameter(Mandatory)][string[]]$ReplacementManifestPath,
 [string]$AdapterBindingsPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Adapters\FF7RemakeIntergrade\adapter-bindings.json'),
 [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')][string]$PackageId,
 [string]$OutputParent=(Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\dxvk-d3d11-runtime-bundles')
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactsRoot=[IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$outputParentFull=[IO.Path]::GetFullPath($OutputParent).TrimEnd('\')
$finalRoot=Join-Path $outputParentFull $PackageId
$temporaryRoot=Join-Path $outputParentFull ('.staging-'+$PackageId+'-'+[Guid]::NewGuid().ToString('N'))
$patchPath=Join-Path $workspace 'src\Backends\DxvkD3D11\patches\dxvk-adeda663-d3d11-shader-overrides.patch'
$assertPath=Join-Path $PSScriptRoot 'Assert-DxvkD3D11RuntimeBundle.ps1'
$utf8=[Text.UTF8Encoding]::new($false)
$moved=$false

function Resolve-ArtifactFile{
 param([string]$Path,[string]$Context)
 $resolved=(Resolve-Path -LiteralPath $Path).Path
 if(-not$resolved.StartsWith($artifactsRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw"$Context must be a workspace artifact: $resolved"}
 if(-not(Test-Path -LiteralPath $resolved -PathType Leaf)){throw"$Context is not a file: $resolved"}
 $resolved
}
function Get-Sha256Upper{param([string]$Path)(Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()}
function Assert-X64Pe{
 param([string]$Path)
 $bytes=[IO.File]::ReadAllBytes($Path)
 if($bytes.Length-lt0x88-or$bytes[0]-ne0x4d-or$bytes[1]-ne0x5a){throw"DXVK build output is not a PE image: $Path"}
 $pe=[BitConverter]::ToInt32($bytes,0x3c)
 if($pe-lt0-or$pe+6-gt$bytes.Length-or$bytes[$pe]-ne0x50-or$bytes[$pe+1]-ne0x45){throw"DXVK build output has an invalid PE header: $Path"}
 if([BitConverter]::ToUInt16($bytes,$pe+4)-ne0x8664){throw"DXVK build output is not x64: $Path"}
}

if(-not$outputParentFull.StartsWith($artifactsRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw"Refusing DXVK runtime bundle output outside the workspace artifacts directory: $outputParentFull"}
if(Test-Path -LiteralPath $finalRoot){throw"Refusing to overwrite an existing DXVK runtime bundle: $finalRoot"}
if($ReplacementManifestPath.Count-lt1){throw'At least one reviewed DXVK replacement manifest is required.'}
$buildManifestFull=Resolve-ArtifactFile $BuildManifestPath 'DXVK build manifest'
$smokeResultFull=Resolve-ArtifactFile $SmokeResultPath 'DXVK smoke result'
$adapterBindingsFull=(Resolve-Path -LiteralPath $AdapterBindingsPath).Path
$build=Get-Content -Raw -LiteralPath $buildManifestFull|ConvertFrom-Json
$smoke=Get-Content -Raw -LiteralPath $smokeResultFull|ConvertFrom-Json
$adapter=Get-Content -Raw -LiteralPath $adapterBindingsFull|ConvertFrom-Json
$pinnedRevision='adeda6639a09ad1b6a1b7c4158a781ffaf68947d';$patchSha=Get-Sha256Upper $patchPath
if($build.Schema-ne1-or$build.Backend-ne'DXVK D3D11 shader replacement'-or$build.Architecture-ne'x64'-or$build.SourceRevision-ne$pinnedRevision-or$build.PatchSha256.ToUpperInvariant()-ne$patchSha-or$build.Installed-ne$false-or$build.RuntimeEligible-ne$false){throw'DXVK build manifest does not match the pinned, non-installing x64 backend contract.'}
if($adapter.schemaVersion-ne1-or$adapter.adapterId-ne'FF7RemakeIntergrade'-or$adapter.renderer-ne'D3D11'-or$adapter.executable.name-ne'ff7remake_.exe'-or$adapter.executable.sha256-notmatch'^[0-9A-Fa-f]{64}$'){throw'Adapter bindings do not identify the reviewed FF7 Remake Intergrade D3D11 executable.'}

$buildFiles=@($build.Files);if($buildFiles.Count-ne2){throw'DXVK build manifest must publish exactly d3d11.dll and dxgi.dll.'}
$runtimeSources=[ordered]@{}
foreach($requiredName in @('d3d11.dll','dxgi.dll')){
 $matches=@($buildFiles|Where-Object{([string]$_.Name).ToLowerInvariant()-eq$requiredName})
 if($matches.Count-ne1){throw"DXVK build manifest must contain exactly one $requiredName"}
 $source=Resolve-ArtifactFile ([string]$matches[0].Path) "DXVK runtime $requiredName"
 if((Get-Sha256Upper $source)-ne([string]$matches[0].Sha256).ToUpperInvariant()){throw"DXVK build output hash mismatch: $requiredName"}
 Assert-X64Pe $source;$runtimeSources[$requiredName]=$source
}
if($smoke.Schema-ne1-or$smoke.Passed-ne$true-or$smoke.Installed-ne$false-or$smoke.CompatibleReplacementResult-ne42-or$smoke.MissingReplacementFallbackResult-ne7-or$smoke.CorruptReplacementFallbackResult-ne7){throw'DXVK smoke result does not prove compatible load and fail-closed fallback.'}
if($smoke.RuntimeD3D11Sha256.ToUpperInvariant()-ne(Get-Sha256Upper $runtimeSources['d3d11.dll'])-or$smoke.RuntimeDxgiSha256.ToUpperInvariant()-ne(Get-Sha256Upper $runtimeSources['dxgi.dll'])){throw'DXVK smoke result hashes do not identify the build outputs being packaged.'}
$smokeIdentity=[string]$smoke.ShaderIdentity
if($smokeIdentity-notmatch'^[0-9a-f]{16}-cs$'){throw'DXVK smoke result has an invalid shader identity.'}
$smokeLogInputs=[ordered]@{}
$caseExpectations=[ordered]@{
 compatible=@($true,$false)
 missing=@($false,$false)
 corrupt=@($false,$true)
}
$caseEvidence=@($smoke.CaseEvidence)
if($caseEvidence.Count-ne3){throw'DXVK smoke result must contain exactly three per-case log evidence records.'}
foreach($caseName in $caseExpectations.Keys){
 $matches=@($caseEvidence|Where-Object{[string]$_.Name-eq$caseName})
 if($matches.Count-ne1){throw"DXVK smoke result must contain exactly one '$caseName' log record."}
 $entry=$matches[0];$expected=$caseExpectations[$caseName]
 if($entry.LogSha256-notmatch'^[0-9A-Fa-f]{64}$'-or[bool]$entry.ReplacementLoaded-ne[bool]$expected[0]-or[bool]$entry.ReplacementRejected-ne[bool]$expected[1]){throw"DXVK smoke '$caseName' log flags or hash are invalid."}
 $logSource=Resolve-ArtifactFile ([string]$entry.Log) "DXVK smoke '$caseName' log"
 if((Get-Sha256Upper $logSource)-ne([string]$entry.LogSha256).ToUpperInvariant()){throw"DXVK smoke '$caseName' log hash mismatch."}
 $logText=Get-Content -Raw -LiteralPath $logSource
 $loadedMarker="D3D11: Loaded shader replacement $smokeIdentity from";$rejectedMarker="D3D11: Rejecting shader replacement ${smokeIdentity}:"
 if($caseName-eq'compatible'-and(-not$logText.Contains($loadedMarker)-or$logText.Contains($rejectedMarker))){throw'DXVK compatible smoke log does not prove replacement acceptance.'}
 if($caseName-eq'missing'-and($logText.Contains($loadedMarker)-or$logText.Contains($rejectedMarker))){throw'DXVK missing smoke log does not prove silent original fallback.'}
 if($caseName-eq'corrupt'-and(-not$logText.Contains($rejectedMarker)-or$logText.Contains($loadedMarker))){throw'DXVK corrupt smoke log does not prove rejection and original fallback.'}
 $smokeLogInputs[$caseName]=$logSource
}

$realShaderInputs=[Collections.Generic.List[object]]::new();$realShaderIdentities=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($resultInputPath in @($RealShaderResultPath)){
 if([string]::IsNullOrWhiteSpace($resultInputPath)){continue}
 $resultFull=Resolve-ArtifactFile $resultInputPath 'DXVK real-shader result';$result=Get-Content -Raw -LiteralPath $resultFull|ConvertFrom-Json
 if($result.schemaVersion-ne1-or$result.kind-ne'dxvk-d3d11-real-shader-creation-gate'-or$result.passed-ne$true-or$result.stage-ne'cs'-or$result.identity-notmatch'^[0-9a-f]{16}-cs$'-or$result.installed-ne$false-or$result.runtimeEligible-ne$false){throw'DXVK real-shader result does not prove a passing, non-installing compute-shader gate.'}
 if(-not$realShaderIdentities.Add([string]$result.identity)){throw"Duplicate DXVK real-shader identity: $($result.identity)"}
 if($result.runtimeD3D11Sha256.ToUpperInvariant()-ne(Get-Sha256Upper $runtimeSources['d3d11.dll'])-or$result.runtimeDxgiSha256.ToUpperInvariant()-ne(Get-Sha256Upper $runtimeSources['dxgi.dll'])){throw'DXVK real-shader result hashes do not identify the build outputs being packaged.'}
 $logs=[ordered]@{};$realCases=@($result.caseEvidence);if($realCases.Count-ne3){throw'DXVK real-shader result must contain exactly three case records.'}
 foreach($caseName in $caseExpectations.Keys){
  $matches=@($realCases|Where-Object{[string]$_.name-eq$caseName});if($matches.Count-ne1){throw"DXVK real-shader result must contain exactly one '$caseName' record."}
  $entry=$matches[0];$expected=$caseExpectations[$caseName]
  if($entry.shaderCreated-ne$true-or$entry.logSha256-notmatch'^[0-9A-Fa-f]{64}$'-or[bool]$entry.replacementLoaded-ne[bool]$expected[0]-or[bool]$entry.replacementRejected-ne[bool]$expected[1]){throw"DXVK real-shader '$caseName' flags or hash are invalid."}
  $logSource=Resolve-ArtifactFile ([string]$entry.log) "DXVK real-shader '$caseName' log";if((Get-Sha256Upper $logSource)-ne([string]$entry.logSha256).ToUpperInvariant()){throw"DXVK real-shader '$caseName' log hash mismatch."}
  $logText=Get-Content -Raw -LiteralPath $logSource;$loadedMarker="D3D11: Loaded shader replacement $($result.identity) from";$rejectedMarker="D3D11: Rejecting shader replacement $($result.identity):"
  if($caseName-eq'compatible'-and(-not$logText.Contains($loadedMarker)-or$logText.Contains($rejectedMarker))){throw'DXVK real compatible log does not prove replacement acceptance.'}
  if($caseName-eq'missing'-and($logText.Contains($loadedMarker)-or$logText.Contains($rejectedMarker))){throw'DXVK real missing log does not prove silent original fallback.'}
  if($caseName-eq'corrupt'-and(-not$logText.Contains($rejectedMarker)-or$logText.Contains($loadedMarker))){throw'DXVK real corrupt log does not prove rejection and original fallback.'}
  $logs[$caseName]=$logSource
 }
 $realShaderInputs.Add([pscustomobject]@{ResultPath=$resultFull;Result=$result;LogInputs=$logs})
}

$replacementInputs=[Collections.Generic.List[object]]::new();$identities=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($inputPath in $ReplacementManifestPath){
 $sourceManifestPath=Resolve-ArtifactFile $inputPath 'DXVK replacement manifest';$replacement=Get-Content -Raw -LiteralPath $sourceManifestPath|ConvertFrom-Json
 if($replacement.schemaVersion-ne1-or$replacement.backend-ne'dxvk-d3d11'-or$replacement.identity-notmatch'^[0-9a-f]{16}-(vs|hs|ds|gs|ps|cs)$'-or$replacement.originalIdentityVerified-ne$true-or$replacement.compatibilityStatus-notin@('passed-reflection-contract','passed-declaration-contract-rdef-unavailable')-or-not$replacement.reviewedFamily-or[string]::IsNullOrWhiteSpace([string]$replacement.reviewedFamily.familyId)-or$replacement.runtimeEligible-ne$false-or$replacement.installed-ne$false){throw"Replacement manifest is not reviewed, original-identity-verified, and compatibility-checked: $sourceManifestPath"}
 if(-not$identities.Add([string]$replacement.identity)){throw"Duplicate DXVK replacement identity: $($replacement.identity)"}
 $binary=Resolve-ArtifactFile ([string]$replacement.outputPath) "DXVK replacement binary '$($replacement.identity)'"
 if((Split-Path -Leaf $binary).ToLowerInvariant()-ne(([string]$replacement.identity)+'_replace.bin')){throw"Replacement filename does not match identity: $binary"}
 if((Get-Sha256Upper $binary)-ne([string]$replacement.outputSha256).ToUpperInvariant()){throw"Replacement binary hash mismatch: $($replacement.identity)"}
 $bytes=[IO.File]::ReadAllBytes($binary);if($bytes.Length-lt4-or[Text.Encoding]::ASCII.GetString($bytes,0,4)-ne'DXBC'){throw"Replacement payload is not DXBC: $($replacement.identity)"}
 $replacementInputs.Add([pscustomobject]@{ManifestPath=$sourceManifestPath;Manifest=$replacement;BinaryPath=$binary})
}
foreach($realInput in $realShaderInputs){
 $matches=@($replacementInputs|Where-Object{[string]$_.Manifest.identity-eq[string]$realInput.Result.identity});if($matches.Count-ne1){throw 'DXVK real-shader evidence does not identify exactly one packaged replacement.'}
 $match=$matches[0]
 if(([string]$realInput.Result.replacementSha256).ToUpperInvariant()-ne(Get-Sha256Upper $match.BinaryPath)-or([string]$realInput.Result.replacementManifestSha256).ToUpperInvariant()-ne(Get-Sha256Upper $match.ManifestPath)-or([string]$realInput.Result.originalSha256).ToUpperInvariant()-ne([string]$match.Manifest.originalSha256).ToUpperInvariant()){throw 'DXVK real-shader evidence hashes do not match the packaged replacement and its original.'}
}

try{
 [IO.Directory]::CreateDirectory($temporaryRoot)|Out-Null
 [IO.Directory]::CreateDirectory((Join-Path $temporaryRoot 'ShaderFixes'))|Out-Null
 [IO.Directory]::CreateDirectory((Join-Path $temporaryRoot 'provenance\replacements'))|Out-Null
 [IO.Directory]::CreateDirectory((Join-Path $temporaryRoot 'provenance\smoke'))|Out-Null
 if($realShaderInputs.Count){[IO.Directory]::CreateDirectory((Join-Path $temporaryRoot 'provenance\real-shader'))|Out-Null}
 foreach($name in $runtimeSources.Keys){Copy-Item -LiteralPath $runtimeSources[$name] -Destination(Join-Path $temporaryRoot $name)}
 [IO.File]::WriteAllText((Join-Path $temporaryRoot 'dxvk.conf'),"d3d11.shaderOverridePath = ShaderFixes`n",[Text.Encoding]::ASCII)
 Copy-Item -LiteralPath $buildManifestFull -Destination(Join-Path $temporaryRoot 'provenance\build-manifest.json')
 Copy-Item -LiteralPath $smokeResultFull -Destination(Join-Path $temporaryRoot 'provenance\smoke-result.json')
 foreach($caseName in $smokeLogInputs.Keys){Copy-Item -LiteralPath $smokeLogInputs[$caseName] -Destination(Join-Path $temporaryRoot "provenance\smoke\$caseName-d3d11.log")}
 foreach($realInput in $realShaderInputs){
  $realIdentity=[string]$realInput.Result.identity;$realRoot=Join-Path $temporaryRoot "provenance\real-shader\$realIdentity";[IO.Directory]::CreateDirectory($realRoot)|Out-Null
  Copy-Item -LiteralPath $realInput.ResultPath -Destination(Join-Path $realRoot 'result.json')
  foreach($caseName in $realInput.LogInputs.Keys){Copy-Item -LiteralPath $realInput.LogInputs[$caseName] -Destination(Join-Path $realRoot "$caseName-d3d11.log")}
 }
 Copy-Item -LiteralPath $adapterBindingsFull -Destination(Join-Path $temporaryRoot 'provenance\adapter-bindings.json')
 Copy-Item -LiteralPath $patchPath -Destination(Join-Path $temporaryRoot 'provenance\dxvk-shader-overrides.patch')
 $replacementRecords=[Collections.Generic.List[object]]::new()
 foreach($input in $replacementInputs){
  $identity=[string]$input.Manifest.identity;$binaryRelative="ShaderFixes/${identity}_replace.bin";$manifestRelative="provenance/replacements/${identity}.json"
  Copy-Item -LiteralPath $input.BinaryPath -Destination(Join-Path $temporaryRoot $binaryRelative.Replace('/','\'))
  Copy-Item -LiteralPath $input.ManifestPath -Destination(Join-Path $temporaryRoot $manifestRelative.Replace('/','\'))
  $replacementRecords.Add([ordered]@{identity=$identity;stage=[string]$input.Manifest.stage;familyId=[string]$input.Manifest.reviewedFamily.familyId;versionGroup=[string]$input.Manifest.reviewedFamily.versionGroup;binary=$binaryRelative;binarySha256=Get-Sha256Upper(Join-Path $temporaryRoot $binaryRelative.Replace('/','\'));manifest=$manifestRelative;manifestSha256=Get-Sha256Upper(Join-Path $temporaryRoot $manifestRelative.Replace('/','\'));compatibilityStatus=[string]$input.Manifest.compatibilityStatus})
 }
 $targetPaths=@('d3d11.dll','dxgi.dll','dxvk.conf')+@($replacementRecords|ForEach-Object{[string]$_.binary})
 $rollback=[ordered]@{schemaVersion=1;packageId=$PackageId;targetRootKind='game-binary-directory';exactTargetRelativePaths=@($targetPaths);backupBeforeWrite=$true;refuseWithoutVerifiedBackup=$true;restoreBackedUpFiles=$true;removePackageCreatedFiles=$true;verifyRestoredHashes=$true;note='Plan only. This package contains no installer and has not touched the game directory.'}
 $rollbackPath=Join-Path $temporaryRoot 'rollback-plan.json';[IO.File]::WriteAllText($rollbackPath,(($rollback|ConvertTo-Json -Depth 6)+[Environment]::NewLine),$utf8)
 $fileRecords=@(Get-ChildItem -LiteralPath $temporaryRoot -Recurse -File|Sort-Object FullName|ForEach-Object{[ordered]@{relativePath=$_.FullName.Substring($temporaryRoot.Length+1).Replace('\','/');sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToUpperInvariant();sizeBytes=[long]$_.Length;role=if($_.Name-in@('d3d11.dll','dxgi.dll')){'runtime'}elseif($_.Name-eq'dxvk.conf'){'configuration'}elseif($_.Directory.Name-eq'ShaderFixes'){'replacement'}elseif($_.Name-eq'rollback-plan.json'){'rollback'}else{'provenance'}}})
 $manifest=[ordered]@{schemaVersion=1;packageId=$PackageId;backend='dxvk-d3d11';architecture='x64';createdUtc=[DateTime]::UtcNow.ToString('o');sourceRevision=$pinnedRevision;patchSha256=$patchSha;adapter=[ordered]@{id=[string]$adapter.adapterId;game=[string]$adapter.game;engineFamily=[string]$adapter.engineFamily;renderer=[string]$adapter.renderer;bindingManifest='provenance/adapter-bindings.json';bindingManifestSha256=Get-Sha256Upper(Join-Path $temporaryRoot 'provenance\adapter-bindings.json');executable=[ordered]@{name=[string]$adapter.executable.name;sha256=([string]$adapter.executable.sha256).ToUpperInvariant()}};buildEvidence=[ordered]@{manifest='provenance/build-manifest.json';manifestSha256=Get-Sha256Upper(Join-Path $temporaryRoot 'provenance\build-manifest.json')};smokeEvidence=[ordered]@{manifest='provenance/smoke-result.json';manifestSha256=Get-Sha256Upper(Join-Path $temporaryRoot 'provenance\smoke-result.json');passed=$true};config=[ordered]@{relativePath='dxvk.conf';key='d3d11.shaderOverridePath';value='ShaderFixes'};replacements=@($replacementRecords);files=@($fileRecords);rollback=[ordered]@{plan='rollback-plan.json';planSha256=Get-Sha256Upper $rollbackPath};policy=[ordered]@{installed=$false;runtimeEligible=$false;automaticInstall=$false;gameDirectoryTouched=$false;backupRequired=$true}}
 [IO.File]::WriteAllText((Join-Path $temporaryRoot 'runtime-bundle.json'),(($manifest|ConvertTo-Json -Depth 10)+[Environment]::NewLine),$utf8)
 [IO.Directory]::CreateDirectory($outputParentFull)|Out-Null;[IO.Directory]::Move($temporaryRoot,$finalRoot);$moved=$true
 $validated=&$assertPath -BundleDirectory $finalRoot
 Write-Host "PASS: staged non-installing DXVK runtime bundle $PackageId with $($validated.ReplacementCount) reviewed replacement(s).";$validated
}catch{if(Test-Path -LiteralPath $temporaryRoot -PathType Container){Remove-Item -LiteralPath $temporaryRoot -Recurse -Force};if($moved-and(Test-Path -LiteralPath $finalRoot -PathType Container)){Remove-Item -LiteralPath $finalRoot -Recurse -Force};throw}
