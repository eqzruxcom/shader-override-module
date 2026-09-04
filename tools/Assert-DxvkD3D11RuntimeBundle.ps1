[CmdletBinding()]
param([Parameter(Mandatory)][string]$BundleDirectory)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactsRoot=[IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$bundleRoot=[IO.Path]::GetFullPath($BundleDirectory).TrimEnd('\')
$manifestPath=Join-Path $bundleRoot 'runtime-bundle.json'
$workspacePatchPath=Join-Path $workspace 'src\Backends\DxvkD3D11\patches\dxvk-adeda663-d3d11-shader-overrides.patch'
if(-not $bundleRoot.StartsWith($artifactsRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Refusing DXVK runtime bundle outside the workspace artifacts directory: $bundleRoot"}
if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw "DXVK runtime bundle manifest is missing: $manifestPath"}

function Assert-ExactProperties{
 param($Object,[string[]]$Names,[string]$Context)
 $actual=@($Object.PSObject.Properties.Name|Sort-Object);$expected=@($Names|Sort-Object)
 if(@(Compare-Object $actual $expected).Count){throw "$Context has missing or unexpected properties. Expected: $($expected-join', '); actual: $($actual-join', ')"}
}
function Assert-Sha256{param([string]$Value,[string]$Context)if($Value-notmatch'^[0-9A-Fa-f]{64}$'){throw "$Context is not SHA-256: $Value"}}
function Resolve-BundleRelativePath{
 param([string]$RelativePath)
 if([IO.Path]::IsPathRooted($RelativePath)-or$RelativePath-match'(^|[\\/])\.\.([\\/]|$)'){throw "Unsafe DXVK bundle relative path: $RelativePath"}
 $full=[IO.Path]::GetFullPath((Join-Path $bundleRoot $RelativePath.Replace('/','\')))
 if(-not $full.StartsWith($bundleRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw "DXVK bundle path escapes package root: $RelativePath"}
 $full
}
function Assert-X64Pe{
 param([string]$Path)
 $bytes=[IO.File]::ReadAllBytes($Path)
 if($bytes.Length-lt0x88-or$bytes[0]-ne0x4d-or$bytes[1]-ne0x5a){throw "Runtime DLL is not a PE image: $Path"}
 $pe=[BitConverter]::ToInt32($bytes,0x3c)
 if($pe-lt0-or$pe+6-gt$bytes.Length-or$bytes[$pe]-ne0x50-or$bytes[$pe+1]-ne0x45-or$bytes[$pe+2]-ne0-or$bytes[$pe+3]-ne0){throw "Runtime DLL has an invalid PE header: $Path"}
 $machine=[BitConverter]::ToUInt16($bytes,$pe+4)
 if($machine-ne0x8664){throw("Runtime DLL is not x64 (machine 0x{0:X4}): {1}"-f$machine,$Path)}
}

$manifest=Get-Content -Raw -LiteralPath $manifestPath|ConvertFrom-Json
Assert-ExactProperties $manifest @('schemaVersion','packageId','backend','architecture','createdUtc','sourceRevision','patchSha256','adapter','buildEvidence','smokeEvidence','config','replacements','files','rollback','policy') 'DXVK runtime bundle manifest'
if($manifest.schemaVersion-ne1-or$manifest.backend-ne'dxvk-d3d11'-or$manifest.architecture-ne'x64'){throw'Unexpected DXVK runtime bundle schema, backend, or architecture.'}
if($manifest.packageId-notmatch'^[A-Za-z0-9][A-Za-z0-9._-]+$'){throw'Invalid DXVK runtime package ID.'}
if([string]$manifest.sourceRevision-ne'adeda6639a09ad1b6a1b7c4158a781ffaf68947d'){throw'DXVK runtime bundle uses an unreviewed source revision.'}
Assert-Sha256 ([string]$manifest.patchSha256) 'DXVK patch hash'

Assert-ExactProperties $manifest.adapter @('id','game','engineFamily','renderer','bindingManifest','bindingManifestSha256','executable') 'DXVK bundle adapter'
Assert-ExactProperties $manifest.adapter.executable @('name','sha256') 'DXVK bundle executable fingerprint'
if($manifest.adapter.id-ne'FF7RemakeIntergrade'-or$manifest.adapter.engineFamily-ne'UE4-custom'-or$manifest.adapter.renderer-ne'D3D11'-or$manifest.adapter.executable.name-ne'ff7remake_.exe'-or$manifest.adapter.executable.sha256-ne'25B54C345C94EE9F6C6876B9C7537A69E6B0EEF25F322207C32A8DDCEE816635'){throw'DXVK bundle adapter is not the reviewed Remake D3D11 target.'}
Assert-Sha256 ([string]$manifest.adapter.bindingManifestSha256) 'Adapter binding manifest hash'
Assert-Sha256 ([string]$manifest.adapter.executable.sha256) 'Executable fingerprint'
Assert-ExactProperties $manifest.buildEvidence @('manifest','manifestSha256') 'DXVK build evidence'
Assert-ExactProperties $manifest.smokeEvidence @('manifest','manifestSha256','passed') 'DXVK smoke evidence'
Assert-Sha256 ([string]$manifest.buildEvidence.manifestSha256) 'Build evidence hash'
Assert-Sha256 ([string]$manifest.smokeEvidence.manifestSha256) 'Smoke evidence hash'
if($manifest.smokeEvidence.passed-ne$true){throw'DXVK smoke evidence is not passing.'}

Assert-ExactProperties $manifest.config @('relativePath','key','value') 'DXVK bundle config'
if($manifest.config.relativePath-ne'dxvk.conf'-or$manifest.config.key-ne'd3d11.shaderOverridePath'-or$manifest.config.value-ne'ShaderFixes'){throw'DXVK runtime bundle has unexpected shader override configuration.'}
Assert-ExactProperties $manifest.policy @('installed','runtimeEligible','automaticInstall','gameDirectoryTouched','backupRequired') 'DXVK bundle policy'
if($manifest.policy.installed-ne$false-or$manifest.policy.runtimeEligible-ne$false-or$manifest.policy.automaticInstall-ne$false-or$manifest.policy.gameDirectoryTouched-ne$false-or$manifest.policy.backupRequired-ne$true){throw'DXVK runtime bundle policy must remain non-installing, non-eligible, and backup-gated.'}

$records=@($manifest.files)
if($records.Count-lt8){throw'DXVK runtime bundle payload is unexpectedly small.'}
$recordPaths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($record in $records){
 Assert-ExactProperties $record @('relativePath','sha256','sizeBytes','role') "DXVK bundle file record '$($record.relativePath)'"
 if(-not$recordPaths.Add([string]$record.relativePath)){throw"Duplicate DXVK bundle file record: $($record.relativePath)"}
 Assert-Sha256 ([string]$record.sha256) "DXVK bundle file hash '$($record.relativePath)'"
 $file=Resolve-BundleRelativePath ([string]$record.relativePath)
 if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw"DXVK bundle file is missing: $($record.relativePath)"}
 if((Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash-ne([string]$record.sha256).ToUpperInvariant()){throw"DXVK bundle file hash mismatch: $($record.relativePath)"}
 if((Get-Item -LiteralPath $file).Length-ne[long]$record.sizeBytes){throw"DXVK bundle file size mismatch: $($record.relativePath)"}
}
$actualFiles=@(Get-ChildItem -LiteralPath $bundleRoot -Recurse -File|ForEach-Object{$_.FullName.Substring($bundleRoot.Length+1).Replace('\','/')}|Where-Object{$_-ne'runtime-bundle.json'})
if(@(Compare-Object @($recordPaths|Sort-Object) @($actualFiles|Sort-Object)).Count){throw'DXVK runtime bundle contains an unlisted file or lists a missing file.'}
foreach($name in @('d3d11.dll','dxgi.dll')){if(-not$recordPaths.Contains($name)){throw"DXVK runtime bundle is missing $name"};Assert-X64Pe(Join-Path $bundleRoot $name)}
$copiedPatch=Resolve-BundleRelativePath 'provenance/dxvk-shader-overrides.patch'
if((Get-FileHash -Algorithm SHA256 -LiteralPath $copiedPatch).Hash-ne([string]$manifest.patchSha256).ToUpperInvariant()-or(Get-FileHash -Algorithm SHA256 -LiteralPath $workspacePatchPath).Hash-ne([string]$manifest.patchSha256).ToUpperInvariant()){throw'DXVK patch provenance does not match the reviewed workspace patch.'}
$configPath=Resolve-BundleRelativePath ([string]$manifest.config.relativePath)
if((Get-Content -Raw -LiteralPath $configPath).Trim()-ne'd3d11.shaderOverridePath = ShaderFixes'){throw'DXVK configuration payload does not match its manifest.'}

$bindingPath=Resolve-BundleRelativePath ([string]$manifest.adapter.bindingManifest)
if((Get-FileHash -Algorithm SHA256 -LiteralPath $bindingPath).Hash-ne([string]$manifest.adapter.bindingManifestSha256).ToUpperInvariant()){throw'Copied adapter binding manifest hash mismatch.'}
$binding=Get-Content -Raw -LiteralPath $bindingPath|ConvertFrom-Json
if($binding.adapterId-ne$manifest.adapter.id-or$binding.renderer-ne'D3D11'-or$binding.executable.name-ne$manifest.adapter.executable.name-or$binding.executable.sha256-ne$manifest.adapter.executable.sha256){throw'Copied adapter binding manifest does not match the DXVK bundle target.'}
$buildPath=Resolve-BundleRelativePath ([string]$manifest.buildEvidence.manifest);$smokePath=Resolve-BundleRelativePath ([string]$manifest.smokeEvidence.manifest)
if((Get-FileHash -Algorithm SHA256 -LiteralPath $buildPath).Hash-ne([string]$manifest.buildEvidence.manifestSha256).ToUpperInvariant()){throw'Copied build evidence hash mismatch.'}
if((Get-FileHash -Algorithm SHA256 -LiteralPath $smokePath).Hash-ne([string]$manifest.smokeEvidence.manifestSha256).ToUpperInvariant()){throw'Copied smoke evidence hash mismatch.'}
$build=Get-Content -Raw -LiteralPath $buildPath|ConvertFrom-Json;$smoke=Get-Content -Raw -LiteralPath $smokePath|ConvertFrom-Json
if($build.SourceRevision-ne$manifest.sourceRevision-or$build.PatchSha256-ne$manifest.patchSha256-or$build.Installed-ne$false-or$build.RuntimeEligible-ne$false){throw'Copied DXVK build evidence is inconsistent with the bundle.'}
if($smoke.Passed-ne$true-or$smoke.Installed-ne$false-or$smoke.CompatibleReplacementResult-ne42-or$smoke.MissingReplacementFallbackResult-ne7-or$smoke.CorruptReplacementFallbackResult-ne7){throw'Copied DXVK smoke evidence does not prove load and fail-closed behavior.'}
$smokeIdentity=[string]$smoke.ShaderIdentity;if($smokeIdentity-notmatch'^[0-9a-f]{16}-cs$'){throw'Copied DXVK smoke evidence has an invalid shader identity.'}
$caseExpectations=[ordered]@{compatible=@($true,$false);missing=@($false,$false);corrupt=@($false,$true)}
$caseEvidence=@($smoke.CaseEvidence);if($caseEvidence.Count-ne3){throw'Copied DXVK smoke evidence must contain exactly three case logs.'}
foreach($caseName in $caseExpectations.Keys){
 $matches=@($caseEvidence|Where-Object{[string]$_.Name-eq$caseName});if($matches.Count-ne1){throw"Copied DXVK smoke evidence must contain exactly one '$caseName' case."}
 $entry=$matches[0];$expected=$caseExpectations[$caseName]
 Assert-Sha256 ([string]$entry.LogSha256) "DXVK smoke '$caseName' log hash"
 if([bool]$entry.ReplacementLoaded-ne[bool]$expected[0]-or[bool]$entry.ReplacementRejected-ne[bool]$expected[1]){throw"Copied DXVK smoke '$caseName' flags are invalid."}
 $copiedLog=Resolve-BundleRelativePath "provenance/smoke/$caseName-d3d11.log"
 if((Get-FileHash -Algorithm SHA256 -LiteralPath $copiedLog).Hash-ne([string]$entry.LogSha256).ToUpperInvariant()){throw"Copied DXVK smoke '$caseName' log hash mismatch."}
 $logText=Get-Content -Raw -LiteralPath $copiedLog;$loadedMarker="D3D11: Loaded shader replacement $smokeIdentity from";$rejectedMarker="D3D11: Rejecting shader replacement ${smokeIdentity}:"
 if($caseName-eq'compatible'-and(-not$logText.Contains($loadedMarker)-or$logText.Contains($rejectedMarker))){throw'Copied compatible smoke log does not prove replacement acceptance.'}
 if($caseName-eq'missing'-and($logText.Contains($loadedMarker)-or$logText.Contains($rejectedMarker))){throw'Copied missing smoke log does not prove silent original fallback.'}
 if($caseName-eq'corrupt'-and(-not$logText.Contains($rejectedMarker)-or$logText.Contains($loadedMarker))){throw'Copied corrupt smoke log does not prove rejection and original fallback.'}
}
$packagedD3d11=(Get-FileHash -Algorithm SHA256 -LiteralPath(Join-Path $bundleRoot 'd3d11.dll')).Hash;$packagedDxgi=(Get-FileHash -Algorithm SHA256 -LiteralPath(Join-Path $bundleRoot 'dxgi.dll')).Hash
if($smoke.RuntimeD3D11Sha256-ne$packagedD3d11-or$smoke.RuntimeDxgiSha256-ne$packagedDxgi){throw'Copied smoke evidence does not identify the packaged runtime DLLs.'}
$buildFiles=@($build.Files);if($buildFiles.Count-ne2){throw'Copied build evidence does not contain exactly two runtime DLLs.'}
foreach($pair in @(@('d3d11.dll',$packagedD3d11),@('dxgi.dll',$packagedDxgi))){$match=@($buildFiles|Where-Object{$_.Name-eq$pair[0]});if($match.Count-ne1-or$match[0].Sha256-ne$pair[1]){throw"Copied build evidence does not identify packaged $($pair[0])."}}

$replacementIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($replacement in @($manifest.replacements)){
 Assert-ExactProperties $replacement @('identity','stage','familyId','versionGroup','binary','binarySha256','manifest','manifestSha256','compatibilityStatus') "DXVK replacement '$($replacement.identity)'"
 if($replacement.identity-notmatch'^[0-9a-f]{16}-(vs|hs|ds|gs|ps|cs)$'){throw"Invalid DXVK replacement identity: $($replacement.identity)"}
 if(-not$replacementIds.Add([string]$replacement.identity)){throw"Duplicate DXVK replacement identity: $($replacement.identity)"}
 Assert-Sha256 ([string]$replacement.binarySha256) "Replacement binary hash '$($replacement.identity)'";Assert-Sha256 ([string]$replacement.manifestSha256) "Replacement manifest hash '$($replacement.identity)'"
 $binary=Resolve-BundleRelativePath ([string]$replacement.binary);$provenance=Resolve-BundleRelativePath ([string]$replacement.manifest)
 if((Get-FileHash -Algorithm SHA256 -LiteralPath $binary).Hash-ne([string]$replacement.binarySha256).ToUpperInvariant()){throw"Replacement binary hash mismatch: $($replacement.identity)"}
 if((Get-FileHash -Algorithm SHA256 -LiteralPath $provenance).Hash-ne([string]$replacement.manifestSha256).ToUpperInvariant()){throw"Replacement manifest hash mismatch: $($replacement.identity)"}
 $bytes=[IO.File]::ReadAllBytes($binary);if($bytes.Length-lt4-or[Text.Encoding]::ASCII.GetString($bytes,0,4)-ne'DXBC'){throw"Replacement is not DXBC: $($replacement.identity)"}
 $source=Get-Content -Raw -LiteralPath $provenance|ConvertFrom-Json
 if($source.backend-ne'dxvk-d3d11'-or$source.identity-ne$replacement.identity-or$source.originalIdentityVerified-ne$true-or$source.compatibilityStatus-ne$replacement.compatibilityStatus-or$source.installed-ne$false-or$source.runtimeEligible-ne$false-or-not$source.reviewedFamily-or$source.reviewedFamily.familyId-ne$replacement.familyId-or$source.reviewedFamily.versionGroup-ne$replacement.versionGroup-or$source.outputSha256.ToUpperInvariant()-ne$replacement.binarySha256.ToUpperInvariant()){throw"Replacement provenance is not reviewed and identity-verified: $($replacement.identity)"}
}
if($replacementIds.Count-lt1){throw'DXVK runtime bundle must contain at least one reviewed replacement.'}

$realEvidenceRoot=Resolve-BundleRelativePath 'provenance/real-shader';$realResultPaths=@()
if(Test-Path -LiteralPath $realEvidenceRoot -PathType Container){$realResultPaths=@(Get-ChildItem -LiteralPath $realEvidenceRoot -Recurse -File -Filter 'result.json')}
$realEvidenceIdentities=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($realResultFile in $realResultPaths){
 $real=Get-Content -Raw -LiteralPath $realResultFile.FullName|ConvertFrom-Json
 Assert-ExactProperties $real @('schemaVersion','kind','passed','identity','stage','originalPath','originalSha256','replacementPath','replacementSha256','replacementManifestPath','replacementManifestSha256','runtimeDirectory','runtimeD3D11Sha256','runtimeDxgiSha256','caseEvidence','runRoot','installed','runtimeEligible') 'DXVK real-shader evidence'
 if($real.schemaVersion-ne1-or$real.kind-ne'dxvk-d3d11-real-shader-creation-gate'-or$real.passed-ne$true-or$real.stage-ne'cs'-or$real.identity-notmatch'^[0-9a-f]{16}-cs$'-or$real.installed-ne$false-or$real.runtimeEligible-ne$false){throw'Copied real-shader evidence is not a passing, non-installing compute gate.'}
 if(-not$realEvidenceIdentities.Add([string]$real.identity)){throw"Duplicate copied real-shader evidence identity: $($real.identity)"}
 Assert-Sha256 ([string]$real.originalSha256) 'Real-shader original hash';Assert-Sha256 ([string]$real.replacementSha256) 'Real-shader replacement hash';Assert-Sha256 ([string]$real.replacementManifestSha256) 'Real-shader replacement manifest hash';Assert-Sha256 ([string]$real.runtimeD3D11Sha256) 'Real-shader d3d11 hash';Assert-Sha256 ([string]$real.runtimeDxgiSha256) 'Real-shader dxgi hash'
 if($real.runtimeD3D11Sha256-ne$packagedD3d11-or$real.runtimeDxgiSha256-ne$packagedDxgi){throw'Copied real-shader evidence does not identify the packaged runtime DLLs.'}
 $realReplacement=@($manifest.replacements|Where-Object{[string]$_.identity-eq[string]$real.identity})
 if($realReplacement.Count-ne1-or$realReplacement[0].binarySha256-ne$real.replacementSha256-or$realReplacement[0].manifestSha256-ne$real.replacementManifestSha256){throw'Copied real-shader evidence does not identify exactly one packaged replacement and manifest.'}
 $realProvenance=Get-Content -Raw -LiteralPath(Resolve-BundleRelativePath ([string]$realReplacement[0].manifest))|ConvertFrom-Json
 if($realProvenance.originalSha256.ToUpperInvariant()-ne([string]$real.originalSha256).ToUpperInvariant()){throw'Copied real-shader original hash does not match replacement provenance.'}
 $realCases=@($real.caseEvidence);if($realCases.Count-ne3){throw'Copied real-shader evidence must contain exactly three cases.'}
 $realExpectations=[ordered]@{compatible=@($true,$false);missing=@($false,$false);corrupt=@($false,$true)};$realCaseRoot=$realResultFile.Directory.FullName
 foreach($caseName in $realExpectations.Keys){
  $matches=@($realCases|Where-Object{[string]$_.name-eq$caseName});if($matches.Count-ne1){throw"Copied real-shader evidence must contain exactly one '$caseName' case."}
  $entry=$matches[0];Assert-ExactProperties $entry @('name','mode','shaderCreated','log','logSha256','replacementLoaded','replacementRejected') "DXVK real-shader '$caseName' case"
  $expected=$realExpectations[$caseName];Assert-Sha256 ([string]$entry.logSha256) "DXVK real-shader '$caseName' log hash"
  if($entry.shaderCreated-ne$true-or[bool]$entry.replacementLoaded-ne[bool]$expected[0]-or[bool]$entry.replacementRejected-ne[bool]$expected[1]){throw"Copied real-shader '$caseName' flags are invalid."}
  $copiedLog=Join-Path $realCaseRoot "$caseName-d3d11.log";if(-not(Test-Path -LiteralPath $copiedLog -PathType Leaf)){throw"Copied real-shader '$caseName' log is missing."}
  if((Get-FileHash -Algorithm SHA256 -LiteralPath $copiedLog).Hash-ne([string]$entry.logSha256).ToUpperInvariant()){throw"Copied real-shader '$caseName' log hash mismatch."}
  $text=Get-Content -Raw -LiteralPath $copiedLog;$loaded="D3D11: Loaded shader replacement $($real.identity) from";$rejected="D3D11: Rejecting shader replacement $($real.identity):"
  if($caseName-eq'compatible'-and(-not$text.Contains($loaded)-or$text.Contains($rejected))){throw'Copied real compatible log does not prove replacement acceptance.'}
  if($caseName-eq'missing'-and($text.Contains($loaded)-or$text.Contains($rejected))){throw'Copied real missing log does not prove silent original fallback.'}
  if($caseName-eq'corrupt'-and(-not$text.Contains($rejected)-or$text.Contains($loaded))){throw'Copied real corrupt log does not prove rejection and original fallback.'}
 }
}

Assert-ExactProperties $manifest.rollback @('plan','planSha256') 'DXVK rollback reference';Assert-Sha256 ([string]$manifest.rollback.planSha256) 'Rollback plan hash'
$rollbackPath=Resolve-BundleRelativePath ([string]$manifest.rollback.plan)
if((Get-FileHash -Algorithm SHA256 -LiteralPath $rollbackPath).Hash-ne([string]$manifest.rollback.planSha256).ToUpperInvariant()){throw'Rollback plan hash mismatch.'}
$rollback=Get-Content -Raw -LiteralPath $rollbackPath|ConvertFrom-Json
Assert-ExactProperties $rollback @('schemaVersion','packageId','targetRootKind','exactTargetRelativePaths','backupBeforeWrite','refuseWithoutVerifiedBackup','restoreBackedUpFiles','removePackageCreatedFiles','verifyRestoredHashes','note') 'DXVK rollback plan'
if($rollback.schemaVersion-ne1-or$rollback.packageId-ne$manifest.packageId-or$rollback.targetRootKind-ne'game-binary-directory'-or$rollback.backupBeforeWrite-ne$true-or$rollback.refuseWithoutVerifiedBackup-ne$true-or$rollback.restoreBackedUpFiles-ne$true-or$rollback.removePackageCreatedFiles-ne$true-or$rollback.verifyRestoredHashes-ne$true){throw'DXVK rollback plan is not strict enough.'}
$expectedTargets=@('d3d11.dll','dxgi.dll','dxvk.conf')+@($manifest.replacements|ForEach-Object{[string]$_.binary})
if(@(Compare-Object @($expectedTargets|Sort-Object) @($rollback.exactTargetRelativePaths|Sort-Object)).Count){throw'Rollback plan does not cover every intended live target exactly.'}
[pscustomobject]@{PackageId=[string]$manifest.packageId;BundleRoot=$bundleRoot;FileCount=$records.Count;ReplacementCount=$replacementIds.Count;Valid=$true;Installed=$false;RuntimeEligible=$false}
