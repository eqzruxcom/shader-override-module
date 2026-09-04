[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$OutputDirectory=(Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts/generated-runtime/FF7RemakeIntergradeContactAllLights-live-v2'),
    [switch]$Install
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if(-not $output.StartsWith((Join-Path $repo 'artifacts/generated-runtime')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)) {throw 'Use a new generated-runtime directory.'}
$priorGenerated=Join-Path $repo 'artifacts/generated-runtime/FF7RemakeIntergradeContactAllLights-live-v1'
$priorBaseline=Get-Content -LiteralPath (Join-Path $priorGenerated 'live-reload-baseline.json') -Raw | ConvertFrom-Json
$priorPath=$priorBaseline.installReceipt
$prior=Get-Content -LiteralPath $priorPath -Raw | ConvertFrom-Json
$live=[IO.Path]::GetFullPath($prior.targetRoot).TrimEnd('\')
$gameRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $live))
$exe=Join-Path $live 'ff7remake_.exe'
if((Get-FileHash -LiteralPath $exe).Hash -ne $prior.executable.sha256) {throw 'Executable changed.'}
$previousStatus=& (Join-Path $PSScriptRoot 'Get-IntergradeContactShadowStatus.ps1') -GeneratedRuntimeDirectory $priorGenerated
if($previousStatus.classification -ne 'passed-parser-and-five-native-asm-reloads' -or -not $previousStatus.processResponding) {throw 'Expected all-light predecessor is not healthy.'}
$expectedHashes=@('c30cdc8365df9840','62b33a2d1e505241','5a9fbefe0ab6f815','0e97888f9a8767da','08bb8764f1840179')
$candidateRoot=Join-Path $repo 'artifacts/contact-shadow-candidate-20260831-v6'
$candidatePath=Join-Path $candidateRoot 'candidate.json'
$candidate=Get-Content -LiteralPath $candidatePath -Raw | ConvertFrom-Json
$validationPath=Join-Path $repo 'artifacts/contact-candidate-validation-20260831-v6/manifest.json'
$validation=Get-Content -LiteralPath $validationPath -Raw | ConvertFrom-Json
$portablePath=Join-Path $repo 'artifacts/contact-shadows-port-20260831-v14/manifest.json'
$portable=Get-Content -LiteralPath $portablePath -Raw | ConvertFrom-Json
$analysisPath=Join-Path $repo 'artifacts/contact-capture-analysis-20260831-replay/analysis.json'
$analysis=Get-Content -LiteralPath $analysisPath -Raw | ConvertFrom-Json
if(($candidate.variants.shaderHash -join ',') -cne ($expectedHashes -join ',') -or $candidate.sampleCount -ne 16) {throw 'Unexpected candidate set.'}
if((Get-FileHash -LiteralPath $candidatePath).Hash -ne $validation.candidateManifestSha256 -or $validation.result -ne 'passed' -or $validation.creationChecks -ne 15 -or $validation.injectedBlockResourceCases -ne 185) {throw 'Candidate execution evidence mismatch.'}
if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'New-IntergradeContactShadowCandidate.ps1')).Hash -ne $candidate.generatorSha256) {throw 'Candidate generator changed.'}
if($portable.result -ne 'passed' -or $portable.warpCases -ne 34 -or $portable.adapterResourceCases -ne 56 -or $portable.smokeCompiles -ne 6 -or $portable.runnerSha256 -ne $validation.runnerSha256) {throw 'Portable tests incomplete or runner mismatch.'}
$softwareGate=& (Join-Path $PSScriptRoot 'Assert-IntergradeContactSoftwareGate.ps1') `
    -PlaneAuditDirectory (Join-Path $repo 'artifacts/contact-plane-audit-20260831-v13') `
    -CaptureReplayDirectory (Join-Path $repo 'artifacts/contact-capture-replay-20260831-v4') `
    -CandidateValidationDirectory (Split-Path -Parent $validationPath)
if($softwareGate.result -ne 'passed') {throw 'Software renderer gate failed.'}
$motionGate=& (Join-Path $PSScriptRoot 'Assert-IntergradeContactMotionGate.ps1') `
    -MotionAuditDirectory (Join-Path $repo 'artifacts/contact-motion-audit-20260831-16-v4')
if($motionGate.result -ne 'passed') {throw 'Synthetic motion gate failed.'}
foreach($source in $portable.sources) {
    if((Get-FileHash -LiteralPath (Join-Path $repo $source.path)).Hash -ne $source.sha256) {throw "Tested source changed: $($source.path)"}
}
if((Get-FileHash -LiteralPath (Join-Path $repo 'src/Adapters/FF7RemakeIntergrade/ContactShadowKernel_ps.hlsl')).Hash -ne $candidate.sourceKernelSha256 -or
   (Get-FileHash -LiteralPath (Join-Path $repo 'src/Effects/Lighting/ContactShadows.hlsl')).Hash -ne $candidate.effectSourceSha256) {throw 'Candidate HLSL source mismatch.'}
if(-not $analysis.activeLightRowsUnchangedAcrossVariants -or $analysis.reprojection.passFraction -ne 1 -or $analysis.sampleCount -ne 129600) {throw 'Captured mapping evidence incomplete.'}
if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'analyze_intergrade_contact_capture.py')).Hash -ne $analysis.analyzerSha256) {throw 'Capture analyzer changed.'}
$protected=@($priorBaseline.protectedLiveFiles)
if(@(Get-Content -LiteralPath (Join-Path $live 'Mods/ContactShadowCapture.ini') | Where-Object {$_.Trim() -and -not $_.Trim().StartsWith(';')}).Count) {throw 'Capture commands unexpectedly enabled.'}
function Assert-Predecessor {
    foreach($f in $prior.files) {if((Get-FileHash -LiteralPath (Join-Path $live $f.relativePath)).Hash -ne $f.installedSha256) {throw "Predecessor payload changed: $($f.relativePath)"}}
    foreach($f in $protected) {if((Get-FileHash -LiteralPath (Join-Path $live $f.path)).Hash -ne $f.sha256) {throw "Protected file changed: $($f.path)"}}
    $expectedFiles=@($prior.files.relativePath | ForEach-Object {$_.Replace('/','\')})+@('Mods\ContactShadowCapture.ini','Mods\UE4EffectsGenerated.ini','ShaderFixes\41f1bf8b79d01319-ps.txt')
    $active=@(Get-ChildItem -LiteralPath (Join-Path $live 'Mods') -File -Recurse -Filter '*.ini')+@(Get-ChildItem -LiteralPath (Join-Path $live 'ShaderFixes') -File -Recurse)
    $actual=@($active | ForEach-Object {$_.FullName.Substring($live.Length+1)})
    if(@(Compare-Object ($expectedFiles | Sort-Object -Unique) ($actual | Sort-Object -Unique)).Count) {throw 'Unexpected active INI or replacement files.'}
}
Assert-Predecessor
$installPath=Join-Path $repo 'artifacts/installed-contact-all-lights-overlay-v2.json'
if(Test-Path -LiteralPath $installPath) {throw 'Receipt exists; preserve it.'}
if(-not $PSCmdlet.ShouldProcess($output,'Stage actual contact shadows for contributing local lights; Home default OFF')) {return}
$utf8=[Text.UTF8Encoding]::new($false)
foreach($path in @($output,(Join-Path $output 'validation'),(Join-Path $output 'ShaderFixes'),(Join-Path $output 'Mods'))) {$null=New-Item -ItemType Directory -Path $path}
$lines=[Collections.Generic.List[string]]::new()
foreach($line in @('; Experimental author-derived contact shadows, all contributing local lights.',
    '; Corrected receiver intersection; mandatory software-renderer gate passed.',
    '; Home default OFF; Page Down unchanged. Live arm/motion quality unverified.',
    '; Native zero-contribution lights bypass rays. Performance and motion unverified.',
    '[Constants]','global $ue4fx_contact_enabled = 0','',
    '[KeyUE4FXContactHome]','key = no_modifiers VK_HOME','type = cycle','smart = true',
    '$ue4fx_contact_enabled = 0, 1','')) {$lines.Add($line)}
$assembler=Join-Path $repo 'artifacts/shader-assembler-build/bin/cmd_Decompiler.exe'
$files=@()
foreach($v in $candidate.variants) {
    $binary=Join-Path $candidateRoot $v.binary
    $original=Join-Path $candidateRoot ('validation/'+$v.shaderHash+'-original.bin')
    if((Get-FileHash -LiteralPath $binary).Hash -ne $v.candidateSha256 -or (Get-FileHash -LiteralPath $original).Hash -ne $v.originalSha256 -or
       -not $v.zeroNativeContributionGate -or -not $v.roundTripByteIdentical -or -not $v.maskedContributionIdentityLanes) {throw 'Candidate validation mismatch.'}
    $relative='ShaderFixes/'+$v.shaderHash+'-cs.txt'
    $payload=Join-Path $output $relative
    Copy-Item -LiteralPath (Join-Path $candidateRoot $v.assembly) -Destination $payload
    $check=Join-Path $output ('validation/'+$v.shaderHash+'-payload.asm')
    Copy-Item -LiteralPath $payload -Destination $check
    $messages=& $assembler -a --copy-reflection $original $check 2>&1;$code=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $output ('validation/'+$v.shaderHash+'-assemble.log')),($messages|Out-String),$utf8)
    if($code -ne 0 -or (Get-FileHash -LiteralPath ([IO.Path]::ChangeExtension($check,'.shdr'))).Hash -ne $v.candidateSha256) {throw 'Staged payload differs from tested binary.'}
    $files+=@{relativePath=$relative;sha256=(Get-FileHash -LiteralPath $payload).Hash}
    foreach($line in @(('[ShaderOverrideUE4FXContact'+$v.shaderHash+']'),('hash = '+$v.shaderHash),
        'x31 = $ue4fx_contact_enabled','y31 = -1','z31 = 1','w31 = 100','')) {$lines.Add($line)}
}
$relative='Mods/ContactShadows.ini'
[IO.File]::WriteAllText((Join-Path $output $relative),($lines -join "`r`n")+"`r`n",$utf8)
$files+=@{relativePath=$relative;sha256=(Get-FileHash -LiteralPath (Join-Path $output $relative)).Hash}
$manifest=[ordered]@{
    schemaVersion=1;adapterId='FF7RemakeIntergradeContactShadows';mode='author-contact-shadows-all-contributing-local-lights'
    createdAtUtc=[DateTime]::UtcNow.ToString('o');licensedRegexDependency=$false;diagnosticOnly=$true;releaseEligible=$false
    executable=$prior.executable;files=$files;candidateManifestSha256=(Get-FileHash -LiteralPath $candidatePath).Hash
    executionEvidenceSha256=(Get-FileHash -LiteralPath $validationPath).Hash;captureAnalysisSha256=(Get-FileHash -LiteralPath $analysisPath).Hash
    softwareRendererGate=$softwareGate;syntheticMotionGate=$motionGate;stagerSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    selectedLight=-1;key='Home';defaultEnabled=$false;rayTracingEnabled=$true;samples=16;strength=1;rayLength=100
    zeroNativeContributionGate=$candidate.zeroNativeContributionGate;predecessorReceipt=$priorPath;protectedLiveFiles=$protected
    baseline='OFF preserves native math; added registers/index/control checks still have cost'
    limitations=@('Controlled test only, not preferred preset','All-light hardware cost unknown','Screen-space effect can remain view-dependent','No material/hair exclusions or temporal integration','Native AO and shadows may already cover ray hits')
}
[IO.File]::WriteAllText((Join-Path $output 'runtime-manifest.json'),($manifest|ConvertTo-Json -Depth 8)+"`n",$utf8)
Copy-Item -LiteralPath (Join-Path $repo 'licenses/ShaderInjector-MIT.txt') -Destination (Join-Path $output 'ShaderInjector-MIT.txt')
if($Install -and $PSCmdlet.ShouldProcess($live,'Back up and replace the banding candidate with software-tested default-OFF contact rays')) {
    Assert-Predecessor
    $process=Get-Process -Id $priorBaseline.processId -ErrorAction Stop
    if($process.Path -ne $exe -or -not $process.Responding) {throw 'Expected game process unavailable.'}
    $offset=(Get-Item -LiteralPath $priorBaseline.logPath).Length
    & (Join-Path $PSScriptRoot 'Install-UE4GeneratedRuntimeOverlay.ps1') -GeneratedRuntimeDirectory $output -GameRoot $gameRoot -InstallManifestPath $installPath
    foreach($f in $protected) {if((Get-FileHash -LiteralPath (Join-Path $live $f.path)).Hash -ne $f.sha256) {throw 'Protected live file changed.'}}
    $next=[ordered]@{schemaVersion=1;mode=$manifest.mode;processId=$process.Id;capturedAtUtc=[DateTime]::UtcNow.ToString('o');logPath=$priorBaseline.logPath;byteOffset=$offset;installReceipt=$installPath;expectedShaders=$expectedHashes;defaultEnabled=$false;key='Home';reloadRequired=$true;protectedLiveFiles=$protected}
    [IO.File]::WriteAllText((Join-Path $output 'live-reload-baseline.json'),($next|ConvertTo-Json -Depth 7)+"`n",$utf8)
}
[pscustomobject]@{State='all-local-light-contact-staged';InstallRequested=[bool]$Install;Output=$output;Key='Home';Default='OFF';Samples=16;SelectedLight=-1}
