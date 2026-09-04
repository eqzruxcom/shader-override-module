[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$OutputDirectory=(Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts/generated-runtime/FF7RemakeIntergradeContactShadows-live-v1'),
    [string]$GameRoot='C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes',
    [switch]$Install
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if(-not $output.StartsWith((Join-Path $repo 'artifacts/generated-runtime')+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Output must be under generated-runtime.'}
if(Test-Path -LiteralPath $output) {throw 'Output exists; preserve earlier staging evidence.'}
$live=[IO.Path]::GetFullPath((Join-Path $GameRoot 'End/Binaries/Win64')).TrimEnd('\')
$exe=Join-Path $live 'ff7remake_.exe'
$exeSha='25B54C345C94EE9F6C6876B9C7537A69E6B0EEF25F322207C32A8DDCEE816635'
if((Get-FileHash -LiteralPath $exe).Hash -ne $exeSha) {throw 'Wrong executable.'}
$candidateRoot=Join-Path $repo 'artifacts/contact-shadow-candidate-20260830-v3'
$candidatePath=Join-Path $candidateRoot 'candidate.json'
$candidate=Get-Content -LiteralPath $candidatePath -Raw | ConvertFrom-Json
$validationPath=Join-Path $repo 'artifacts/contact-candidate-validation-20260830/manifest.json'
$validation=Get-Content -LiteralPath $validationPath -Raw | ConvertFrom-Json
$portablePath=Join-Path $repo 'artifacts/contact-shadows-port-20260830-v10/manifest.json'
$portable=Get-Content -LiteralPath $portablePath -Raw | ConvertFrom-Json
$analysisPath=Join-Path $repo 'artifacts/contact-capture-analysis-20260830-v2/analysis.json'
$analysis=Get-Content -LiteralPath $analysisPath -Raw | ConvertFrom-Json
$expectedHashes=@('c30cdc8365df9840','62b33a2d1e505241','5a9fbefe0ab6f815','0e97888f9a8767da','08bb8764f1840179')
if(($candidate.variants.shaderHash -join ',') -cne ($expectedHashes -join ',') -or $candidate.sampleCount -ne 16) {throw 'Unexpected candidate set.'}
if((Get-FileHash -LiteralPath $candidatePath).Hash -ne $validation.candidateManifestSha256 -or $validation.result -ne 'passed' -or $validation.creationChecks -ne 15 -or $validation.injectedBlockResourceCases -ne 120) {throw 'Candidate execution evidence mismatch.'}
if($portable.result -ne 'passed' -or $portable.warpCases -ne 34 -or $portable.adapterResourceCases -ne 48 -or $portable.smokeCompiles -ne 6) {throw 'Portable tests incomplete.'}
foreach($source in $portable.sources) {
    if((Get-FileHash -LiteralPath (Join-Path $repo $source.path)).Hash -ne $source.sha256) {throw "Tested source changed: $($source.path)"}
}
if(-not $analysis.activeLightRowsUnchangedAcrossVariants -or $analysis.reprojection.passFraction -ne 1 -or $analysis.sampleCount -ne 129600) {throw 'Captured camera/light checks incomplete.'}
if((Get-FileHash -LiteralPath (Join-Path $repo 'tools/analyze_intergrade_contact_capture.py')).Hash -ne $analysis.analyzerSha256) {throw 'Capture analyzer changed.'}
$selected=@($analysis.rankedLightCandidates | Where-Object index -eq 50)
if($selected.Count -ne 1 -or $selected[0].contactEligibleSamples -lt 50000) {throw 'Selected light lacks captured geometric coverage.'}
$prior=Get-Content -LiteralPath (Join-Path $repo 'artifacts/installed-author-image-adjustments-overlay.json') -Raw | ConvertFrom-Json
foreach($f in $prior.files) {
    if((Get-FileHash -LiteralPath (Join-Path $live $f.relativePath)).Hash -ne $f.installedSha256) {throw "Existing image adjustment changed: $($f.relativePath)"}
}
$capturePath=Join-Path $live 'Mods/ContactShadowCapture.ini'
if((Get-FileHash -LiteralPath $capturePath).Hash -ne (Get-FileHash -LiteralPath (Join-Path $repo 'src/Adapters/FF7RemakeIntergrade/ContactShadowCapture.ini')).Hash) {throw 'Capture INI changed; do not overwrite.'}
$inis=@(Get-ChildItem -LiteralPath (Join-Path $live 'Mods') -Filter '*.ini' -File -Recurse)
if($inis.Count -ne 2) {throw 'Unexpected active INIs; inspect conflicts.'}
foreach($ini in $inis) {
    if($ini.FullName -notin @($capturePath,(Join-Path $live 'Mods/UE4EffectsGenerated.ini'))) {throw 'Unexpected active INI.'}
    if((Get-Content -LiteralPath $ini.FullName -Raw) -match '(?im)^key\s*=.*\b(?:VK_HOME|HOME)\b') {throw 'Home is already assigned.'}
}
$rootIni=Join-Path $live 'd3dx.ini'
$rootText=Get-Content -LiteralPath $rootIni -Raw
foreach($pattern in @('(?m)^ini_params\s*=\s*120\s*$','(?m)^cache_shaders\s*=\s*0\s*$','(?m)^include_recursive\s*=\s*Mods\s*$')) {
    if($rootText -notmatch $pattern) {throw 'Root config changed.'}
}
foreach($line in ($rootText -split "`r?`n")) {
    if($line -match '(?i)^\s*[^;#=]+\s*=\s*([^;#]*\b(?:VK_HOME|HOME)\b[^;#]*)') {
        $binding=$Matches[1]
        if($binding -notmatch '(?i)(?:^|\s)(?:ctrl|shift|alt)(?:\s|$)') {throw 'Unmodified Home conflict.'}
    }
}
$fixes=@(Get-ChildItem -LiteralPath (Join-Path $live 'ShaderFixes') -File -Recurse)
if($fixes.Count -ne 1 -or $fixes[0].Name -ne '41f1bf8b79d01319-ps.txt') {throw 'Unexpected replacement shaders.'}
$installPath=Join-Path $repo 'artifacts/installed-contact-shadows-overlay-v1.json'
if(Test-Path -LiteralPath $installPath) {throw 'Install receipt exists; preserve it.'}
$protected=@(foreach($relative in @('d3dx.ini','d3d11.dll','Mods/UE4EffectsGenerated.ini','ShaderFixes/41f1bf8b79d01319-ps.txt')) {
    [ordered]@{path=$relative;sha256=(Get-FileHash -LiteralPath (Join-Path $live $relative)).Hash}
})
if(-not $PSCmdlet.ShouldProcess($output,'Stage five validated native compute patches and a Home toggle, default OFF')) {return}
$utf8=[Text.UTF8Encoding]::new($false)
foreach($directory in @($output,(Join-Path $output 'Mods'),(Join-Path $output 'ShaderFixes'),(Join-Path $output 'validation'))) {
    $null=New-Item -ItemType Directory -Path $directory
}
$lines=[Collections.Generic.List[string]]::new()
foreach($line in @('; Experimental author-derived local-light contact shadows. No color probe.',
    '; Home toggles only this effect; default OFF. Page Down remains unchanged.',
    '; Light index 50 is nominated from the captured test scene, not a portable light ID.',
    '[Constants]','global $ue4fx_contact_enabled = 0','',
    '[KeyUE4FXContactHome]','key = no_modifiers VK_HOME','type = cycle','smart = true',
    '$ue4fx_contact_enabled = 0, 1','')) {$lines.Add($line)}
$assembler=Join-Path $repo 'artifacts/shader-assembler-build/bin/cmd_Decompiler.exe'
$files=[Collections.Generic.List[object]]::new()
foreach($v in $candidate.variants) {
    $binary=Join-Path $candidateRoot $v.binary
    if((Get-FileHash -LiteralPath $binary).Hash -ne $v.candidateSha256 -or -not $v.roundTripByteIdentical -or -not $v.maskedContributionIdentityLanes) {throw 'Candidate validation mismatch.'}
    $original=Join-Path $repo ('artifacts/surface-lighting-study-20260830-v3/'+$v.shaderHash+'-cs.bin')
    if((Get-FileHash -LiteralPath $original).Hash -ne $v.originalSha256) {throw 'Original binary changed.'}
    $relative='ShaderFixes/'+$v.shaderHash+'-cs.txt'
    $payload=Join-Path $output $relative
    Copy-Item -LiteralPath (Join-Path $candidateRoot $v.assembly) -Destination $payload
    $check=Join-Path $output ('validation/'+$v.shaderHash+'-payload.asm')
    Copy-Item -LiteralPath $payload -Destination $check
    $messages=& $assembler -a --copy-reflection $original $check 2>&1
    $code=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $output ('validation/'+$v.shaderHash+'-assemble.log')),($messages|Out-String),$utf8)
    if($code -ne 0 -or (Get-FileHash -LiteralPath ([IO.Path]::ChangeExtension($check,'.shdr'))).Hash -ne $v.candidateSha256) {throw 'Staged assembly differs from tested binary.'}
    $files.Add([ordered]@{relativePath=$relative;sha256=(Get-FileHash -LiteralPath $payload).Hash})
    foreach($line in @(('[ShaderOverrideUE4FXContact'+$v.shaderHash+']'),('hash = '+$v.shaderHash),
        'x31 = $ue4fx_contact_enabled','y31 = 50','z31 = 1','w31 = 100','')) {$lines.Add($line)}
}
[IO.File]::WriteAllText((Join-Path $output 'Mods/ContactShadows.ini'),($lines -join "`r`n")+"`r`n",$utf8)
# Replace the temporary capture commands with a comment-only file, backing up
# the original through the normal overlay installer. No overlapping hashes.
[IO.File]::WriteAllText((Join-Path $output 'Mods/ContactShadowCapture.ini'),"; Capture completed. Commands disabled for the live contact-shadow test.`r`n; Original capture INI is preserved in the overlay backup and workspace source.`r`n",$utf8)
foreach($relative in @('Mods/ContactShadowCapture.ini','Mods/ContactShadows.ini')) {
    $files.Add([ordered]@{relativePath=$relative;sha256=(Get-FileHash -LiteralPath (Join-Path $output $relative)).Hash})
}
$manifest=[ordered]@{
    schemaVersion=1;adapterId='FF7RemakeIntergradeContactShadows';status='controlled-live-test-pending'
    generatedAtUtc=[DateTime]::UtcNow.ToString('o');licensedRegexDependency=$false
    diagnosticOnly=$true;releaseEligible=$false;executable=@{sha256=$exeSha};files=@($files.ToArray())
    candidateManifestSha256=(Get-FileHash -LiteralPath $candidatePath).Hash
    executionEvidenceSha256=(Get-FileHash -LiteralPath $validationPath).Hash
    captureAnalysisSha256=(Get-FileHash -LiteralPath $analysisPath).Hash
    selectedLight=$selected[0];selectionProof='Native attenuation plus geometry proxy, not measured visible contribution'
    key='Home';defaultEnabled=$false;rayLength=100;strength=1;samples=16
    baseline='OFF preserves native calculations; adds registers/control checks, not zero-cost original objects'
    protectedLiveFiles=$protected;limitations=@('First live test pending','No performance or motion-quality evidence','Single scene-local light index','No material/hair exclusions yet')
}
[IO.File]::WriteAllText((Join-Path $output 'runtime-manifest.json'),($manifest|ConvertTo-Json -Depth 10)+"`n",$utf8)
Copy-Item -LiteralPath (Join-Path $repo 'licenses/ShaderInjector-MIT.txt') -Destination (Join-Path $output 'ShaderInjector-MIT.txt')
if($Install -and $PSCmdlet.ShouldProcess($live,'Install the backed-up, default-OFF contact-shadow test; preserve existing image adjustment')) {
    $process=@(Get-Process -Name 'ff7remake_*' -ErrorAction SilentlyContinue | Where-Object Path -eq $exe)
    if($process.Count -ne 1 -or -not $process[0].Responding) {throw 'Exact live game process is not available.'}
    $logPath=Join-Path $live 'd3d11_log.txt'
    $offset=(Get-Item -LiteralPath $logPath).Length
    & (Join-Path $PSScriptRoot 'Install-UE4GeneratedRuntimeOverlay.ps1') -GeneratedRuntimeDirectory $output -GameRoot $GameRoot -InstallManifestPath $installPath
    foreach($f in $protected) {if((Get-FileHash -LiteralPath (Join-Path $live $f.path)).Hash -ne $f.sha256) {throw 'Protected file changed during install.'}}
    $baseline=[ordered]@{
        schemaVersion=1;processId=$process[0].Id;capturedAtUtc=[DateTime]::UtcNow.ToString('o')
        logPath=$logPath;byteOffset=$offset;installReceipt=$installPath;expectedShaders=$expectedHashes
        defaultEnabled=$false;key='Home';reloadRequired=$true;protectedLiveFiles=$protected
    }
    [IO.File]::WriteAllText((Join-Path $output 'live-reload-baseline.json'),($baseline|ConvertTo-Json -Depth 7)+"`n",$utf8)
}
[pscustomobject]@{State='contact-shadows-staged';Output=$output;InstallRequested=[bool]$Install;Default='OFF';Key='Home';SelectedLight=50}
