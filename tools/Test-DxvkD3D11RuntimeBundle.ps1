[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$testRoot=Join-Path $workspace ('artifacts\dxvk-runtime-bundle-test-'+[Guid]::NewGuid().ToString('N'))
$patchPath=Join-Path $workspace 'src\Backends\DxvkD3D11\patches\dxvk-adeda663-d3d11-shader-overrides.patch'
$stagePath=Join-Path $PSScriptRoot 'Stage-DxvkD3D11RuntimeBundle.ps1';$assertPath=Join-Path $PSScriptRoot 'Assert-DxvkD3D11RuntimeBundle.ps1'
$utf8=[Text.UTF8Encoding]::new($false)
function Write-Json{param([string]$Path,$Value)[IO.Directory]::CreateDirectory((Split-Path -Parent $Path))|Out-Null;[IO.File]::WriteAllText($Path,(($Value|ConvertTo-Json -Depth 10)+[Environment]::NewLine),$utf8)}
function Get-Hash{param([string]$Path)(Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash}
function Write-TestX64Pe{
 param([string]$Path,[byte]$Marker)
 $bytes=[byte[]]::new(512);$bytes[0]=0x4d;$bytes[1]=0x5a
 [BitConverter]::GetBytes([int]0x80).CopyTo($bytes,0x3c);$bytes[0x80]=0x50;$bytes[0x81]=0x45
 [BitConverter]::GetBytes([uint16]0x8664).CopyTo($bytes,0x84);$bytes[0x100]=$Marker
 [IO.File]::WriteAllBytes($Path,$bytes)
}
try{
 $stageText=[IO.File]::ReadAllText($stagePath)
 foreach($required in @('gameDirectoryTouched=$false','runtimeEligible=$false','Installed-ne$false','Refusing DXVK runtime bundle output outside the workspace artifacts directory','$smokeLogInputs=[ordered]@{}','provenance\smoke')){if($stageText-notmatch[regex]::Escape($required)){throw"DXVK bundle staging is missing safety evidence: $required"}}
 foreach($forbidden in @('Invoke-WebRequest','Start-BitsTransfer','curl.exe','C:\Games','End\Binaries\Win64')){if($stageText-match[regex]::Escape($forbidden)){throw"DXVK bundle staging unexpectedly contains network or live-game behavior: $forbidden"}}
 $buildRoot=Join-Path $testRoot 'build';$runtimeRoot=Join-Path $buildRoot 'runtime';$smokeRoot=Join-Path $testRoot 'smoke';$replacementRoot=Join-Path $testRoot 'replacement'
 @($runtimeRoot,$smokeRoot,$replacementRoot)|ForEach-Object{[IO.Directory]::CreateDirectory($_)|Out-Null}
 $d3d11=Join-Path $runtimeRoot 'd3d11.dll';$dxgi=Join-Path $runtimeRoot 'dxgi.dll';Write-TestX64Pe $d3d11 0x11;Write-TestX64Pe $dxgi 0x22
 $buildManifestPath=Join-Path $buildRoot 'manifest.json'
 Write-Json $buildManifestPath ([ordered]@{Schema=1;Backend='DXVK D3D11 shader replacement';Architecture='x64';SourceRevision='adeda6639a09ad1b6a1b7c4158a781ffaf68947d';PatchPath=$patchPath;PatchSha256=Get-Hash $patchPath;MesonVersion='1.12.0';MesonWheelSha256=('A'*64);GlslangVersion='16.5.0';GlslangArchiveSha256=('B'*64);GlslangExecutableSha256=('C'*64);ToolchainInputManifest='fixture';ToolchainInputManifestSha256=('D'*64);StagedToolchainManifest='fixture';StagedToolchainManifestSha256=('E'*64);VisualStudioDevCmd='fixture';Files=@([ordered]@{Name='d3d11.dll';Source=$d3d11;Path=$d3d11;Sha256=Get-Hash $d3d11},[ordered]@{Name='dxgi.dll';Source=$dxgi;Path=$dxgi;Sha256=Get-Hash $dxgi});Installed=$false;RuntimeEligible=$false;Note='fixture'})
 $smokeResultPath=Join-Path $smokeRoot 'result.json';$smokeIdentity='0123456789abcdef-cs';$smokeLogRoot=Join-Path $smokeRoot 'logs';[IO.Directory]::CreateDirectory($smokeLogRoot)|Out-Null
 $compatibleLog=Join-Path $smokeLogRoot 'compatible.log';$missingLog=Join-Path $smokeLogRoot 'missing.log';$corruptLog=Join-Path $smokeLogRoot 'corrupt.log'
 [IO.File]::WriteAllText($compatibleLog,"info: D3D11: Loaded shader replacement $smokeIdentity from replacement-compatible\fixture.bin"+[Environment]::NewLine)
 [IO.File]::WriteAllText($missingLog,"info: no replacement file was present"+[Environment]::NewLine)
 [IO.File]::WriteAllText($corruptLog,"warn: D3D11: Rejecting shader replacement ${smokeIdentity}: input/output signature mismatch"+[Environment]::NewLine)
 $caseEvidence=@(
  [ordered]@{Name='compatible';Log=$compatibleLog;LogSha256=Get-Hash $compatibleLog;ReplacementLoaded=$true;ReplacementRejected=$false},
  [ordered]@{Name='missing';Log=$missingLog;LogSha256=Get-Hash $missingLog;ReplacementLoaded=$false;ReplacementRejected=$false},
  [ordered]@{Name='corrupt';Log=$corruptLog;LogSha256=Get-Hash $corruptLog;ReplacementLoaded=$false;ReplacementRejected=$true}
 )
 Write-Json $smokeResultPath ([ordered]@{Schema=1;RuntimeDirectory=$runtimeRoot;RuntimeD3D11Sha256=Get-Hash $d3d11;RuntimeDxgiSha256=Get-Hash $dxgi;ShaderIdentity=$smokeIdentity;CompatibleReplacementResult=42;MissingReplacementFallbackResult=7;CorruptReplacementFallbackResult=7;CaseEvidence=$caseEvidence;RunRoot=$smokeRoot;Passed=$true;Installed=$false})
 $identity='eda405f2d455d5c7-ps';$binaryPath=Join-Path $replacementRoot ($identity+'_replace.bin');[IO.File]::WriteAllBytes($binaryPath,[byte[]](0x44,0x58,0x42,0x43,1,2,3,4))
 $replacementManifestPath=Join-Path $replacementRoot 'manifest.json'
 Write-Json $replacementManifestPath ([ordered]@{schemaVersion=1;backend='dxvk-d3d11';identity=$identity;hash='eda405f2d455d5c7';stage='ps';profile='ps_5_0';entryPoint='main';sourcePath='fixture.hlsl';sourceSha256=('1'*64);originalPath='fixture.bin';originalSha256=('2'*64);originalIdentityVerified=$true;compatibilityStatus='passed-declaration-contract-rdef-unavailable';familyCatalogPath='fixture.json';familyCatalogSha256=('3'*64);reviewedFamily=[ordered]@{catalogId='fixture';familyId='ue4-motion-blur-scene-color-resolve-ps-sm5';logicalName='fixture';implementationId='fixture';adapter='FF7RemakeIntergrade';identityModel='3dmigoto-fnv64';variantId=$identity;versionGroup='FF7RemakeIntergrade-contact-area-baseline'};outputPath=$binaryPath;outputSha256=(Get-Hash $binaryPath).ToLowerInvariant();compilerPath='fxc.exe';compilerVersion='fixture';generatedUtc=[DateTime]::UtcNow.ToString('o');runtimeEligible=$false;installed=$false})

 $outputParent=Join-Path $testRoot 'bundles';$result=&$stagePath -BuildManifestPath $buildManifestPath -SmokeResultPath $smokeResultPath -ReplacementManifestPath $replacementManifestPath -PackageId 'positive' -OutputParent $outputParent
 if(-not$result.Valid-or$result.ReplacementCount-ne1-or$result.Installed-ne$false-or$result.RuntimeEligible-ne$false){throw'Positive DXVK runtime bundle was not validated.'}
 $bundle=Join-Path $outputParent 'positive';$null=&$assertPath -BundleDirectory $bundle
 $tamperedDll=Join-Path $bundle 'd3d11.dll';$originalBytes=[IO.File]::ReadAllBytes($tamperedDll);$tampered=[byte[]]$originalBytes.Clone();$tampered[0x100]=0xff;[IO.File]::WriteAllBytes($tamperedDll,$tampered)
 $rejected=$false;try{$null=&$assertPath -BundleDirectory $bundle}catch{$rejected=$_.Exception.Message-match'hash mismatch'}
 if(-not$rejected){throw'Bundle validator accepted a tampered runtime DLL.'};[IO.File]::WriteAllBytes($tamperedDll,$originalBytes)
 $packagedSmokeLog=Join-Path $bundle 'provenance\smoke\compatible-d3d11.log';$originalSmokeLog=[IO.File]::ReadAllText($packagedSmokeLog);[IO.File]::AppendAllText($packagedSmokeLog,'tampered')
 $rejected=$false;try{$null=&$assertPath -BundleDirectory $bundle}catch{$rejected=$_.Exception.Message-match'hash mismatch'}
 if(-not$rejected){throw 'Bundle validator accepted a tampered smoke log.'};[IO.File]::WriteAllText($packagedSmokeLog,$originalSmokeLog)
 [IO.File]::WriteAllText((Join-Path $bundle 'unexpected.txt'),'unexpected');$rejected=$false;try{$null=&$assertPath -BundleDirectory $bundle}catch{$rejected=$_.Exception.Message-match'unlisted file'}
 if(-not$rejected){throw'Bundle validator accepted an unlisted file.'};Remove-Item -LiteralPath(Join-Path $bundle 'unexpected.txt')-Force
 $bad=Get-Content -Raw -LiteralPath $replacementManifestPath|ConvertFrom-Json;$bad.originalIdentityVerified=$false;$badPath=Join-Path $replacementRoot 'bad-manifest.json';Write-Json $badPath $bad
 $rejected=$false;try{$null=&$stagePath -BuildManifestPath $buildManifestPath -SmokeResultPath $smokeResultPath -ReplacementManifestPath $badPath -PackageId 'bad-unverified' -OutputParent $outputParent}catch{$rejected=$_.Exception.Message-match'not reviewed'}
 if(-not$rejected){throw'Bundle staging accepted an unverified replacement.'}
 Write-Host 'PASS: DXVK runtime bundle staging is x64, hash-closed, reviewed-replacement-only, rollback-gated, and non-installing.'
}finally{if(Test-Path -LiteralPath $testRoot -PathType Container){Remove-Item -LiteralPath $testRoot -Recurse -Force}}
