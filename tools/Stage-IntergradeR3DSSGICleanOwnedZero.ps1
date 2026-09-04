[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ContactInstallReportPath,
    [string]$GameRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64',
    [string]$PackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-zero-pack'),
    [string]$BackupRoot = 'F:\Shader3Dmigoto\FF7Remake\IndirectLighting',
    [switch]$AcknowledgeDiagnosticOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $AcknowledgeDiagnosticOnly) { throw 'Pass -AcknowledgeDiagnosticOnly to stage the literal-zero F2 diagnostic.' }

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$game = [IO.Path]::GetFullPath($GameRoot).TrimEnd('\')
$pack = [IO.Path]::GetFullPath($PackRoot).TrimEnd('\')
$backupBase = [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')
$contactReportPath = [IO.Path]::GetFullPath($ContactInstallReportPath)
if (-not $game.EndsWith('\End\Binaries\Win64',[StringComparison]::OrdinalIgnoreCase)) { throw 'GameRoot must be an exact FF7 Remake Win64 directory.' }
if (-not $backupBase.StartsWith('F:\Shader3Dmigoto\',[StringComparison]::OrdinalIgnoreCase)) { throw 'BackupRoot must remain beneath F:\Shader3Dmigoto.' }

$mods = Join-Path $game 'Mods'
$shaderFixes = Join-Path $game 'ShaderFixes'
$sourceMods = Join-Path $pack 'Mods'
$manifestPath = Join-Path $pack 'manifest.json'
$contactIni = Join-Path $mods 'ContactShadows.ini'
$nativeReplacement = Join-Path $shaderFixes 'e2aa1c8cb39e0a55-ps.txt'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$backup = Join-Path $backupBase ($timestamp + '-pre-clean-owned-zero')
$backupMods = Join-Path $backup 'Mods'
$backupShaderFixes = Join-Path $backup 'ShaderFixes'
$disabled = Join-Path $game ('DISABLED-IndirectLightingHybrid-' + $timestamp)
$reportRoot = Join-Path $workspace ('artifacts\indirect-clean-owned-zero-stage-' + $timestamp)
$reportPath = Join-Path $reportRoot 'stage-report.json'
$utf8 = [Text.UTF8Encoding]::new($false)

$names = @(
    'Agent2R3DSSGITest.ini','Agent2R3DSSGIFullscreen_vs.hlsl','Agent2R3DSSGITraceE2AA_ps.hlsl',
    'Agent2R3DSSGIDenoise2_ps.hlsl','Agent2R3DSSGIDenoise4_ps.hlsl','Agent2R3DSSGIDenoise8_ps.hlsl',
    'Agent2R3DSSGIDenoise16_ps.hlsl','Agent2R3DSSGICompositeE2AA_ps.hlsl'
)
$knownHybrid = [ordered]@{
    'Agent2R3DSSGITest.ini'='2C19B86DC52BA30FD405E47CEA6D8D464E579AA5181F7547CFADDD79551419CD'
    'Agent2R3DSSGIFullscreen_vs.hlsl'='10B9B823B723F2B1CFE21A4427C0D477F15F16EBFBF448B5101042D438206090'
    'Agent2R3DSSGITraceE2AA_ps.hlsl'='CB37EEFE5EF398F0EC1BBB91B67FBB55C02054BE3E3EFBF552A30CEECC921BAF'
    'Agent2R3DSSGIDenoise2_ps.hlsl'='74C2561478CCCCAA1D497065CBCB77010E70813BF591036989776896F3CF86D3'
    'Agent2R3DSSGIDenoise4_ps.hlsl'='F35CBF0773C53E7AA60DB9E9D61D144921A608622F4275CAF68A01FDA82C3F2C'
    'Agent2R3DSSGIDenoise8_ps.hlsl'='86C68D9EDF1F26A84B9ECB5A72846298DBC3896228C4429BFFD665D3099172FB'
    'Agent2R3DSSGIDenoise16_ps.hlsl'='46507B681EE65FA0C4BDA463BF06981B081EFEA86AFF5CA103F75194E093AC44'
    'Agent2R3DSSGICompositeE2AA_ps.hlsl'='DD3902609B46C8E76E303D46E12F06371A5AE3C9A4AE1CA350A8AF2A92D18F08'
}
$knownNativeReplacementSha = '4775E2F6FF4F3E45C4C3DF7E0B832DBB61D58ECE3A46ACAB51079C5A42E0F6FF'

foreach ($path in @($mods,$shaderFixes,$manifestPath,$contactReportPath,$contactIni,$nativeReplacement)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required path is missing: $path" }
}
if (Test-Path -LiteralPath $backup) { throw "Backup already exists: $backup" }
if (Test-Path -LiteralPath $disabled) { throw "Disabled destination already exists: $disabled" }

$contactReport = Get-Content -Raw -LiteralPath $contactReportPath | ConvertFrom-Json
if (-not $contactReport.installed -or $contactReport.liveIniSha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $contactIni).Hash) {
    throw 'Contact-family install report does not match the current live ContactShadows.ini.'
}
foreach ($hash in @('08bb8764f1840179','0e97888f9a8767da','5a9fbefe0ab6f815','62b33a2d1e505241','c30cdc8365df9840')) {
    if (Test-Path -LiteralPath (Join-Path $shaderFixes ($hash+'-cs.txt'))) { throw "Explicit contact shader unexpectedly returned live: $hash" }
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.result -ne 'pass' -or $manifest.runtimeEligible -ne $false -or
    $manifest.hook -ne 'e2aa1c8cb39e0a55-ps' -or $manifest.ownedPass.draw -ne '3, 0' -or @($manifest.files).Count -ne 8) {
    throw 'Owned zero-pack manifest contract is invalid.'
}
$packHashes = [ordered]@{}
foreach ($file in @($manifest.files)) {
    $name = [string]$file.name
    if ($name -notin $names) { throw "Unexpected zero-pack file: $name" }
    $source = Join-Path $sourceMods $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Zero-pack file is missing: $source" }
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
    if ($sha -ne [string]$file.sha256) { throw "Zero-pack file drifted: $name" }
    $packHashes[$name] = $sha
}
if ((@($packHashes.Keys|Sort-Object)-join '|') -ne (@($names|Sort-Object)-join '|')) { throw 'Zero-pack file set is incomplete.' }

$zeroIni = [IO.File]::ReadAllText((Join-Path $sourceMods 'Agent2R3DSSGITest.ini'))
$zeroComposite = [IO.File]::ReadAllText((Join-Path $sourceMods 'Agent2R3DSSGICompositeE2AA_ps.hlsl'))
foreach ($needle in @('vs = Agent2R3DSSGIFullscreen_vs.hlsl','draw = 3, 0','key = no_modifiers F2')) {
    if (-not $zeroIni.Contains($needle)) { throw "Zero pack lacks required contract: $needle" }
}
if ($zeroIni -match '(?im)^\s*key\s*=.*(?:F10|VK_PRIOR|VK_NEXT).*$') { throw 'Zero pack attempts to capture F10, Page Up, or Page Down.' }
if ($zeroComposite -notmatch '(?m)^\s*return\s+0\.0\s*;') { throw 'Diagnostic composite is not literal zero.' }

foreach ($name in $names) {
    $live = Join-Path $mods $name
    if (-not (Test-Path -LiteralPath $live -PathType Leaf)) { throw "Live hybrid file is missing: $name" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $live).Hash -ne [string]$knownHybrid[$name]) { throw "Live hybrid file is unknown or drifted: $name" }
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $nativeReplacement).Hash -ne $knownNativeReplacementSha) { throw 'Native e2aa replacement is unknown or drifted.' }

[IO.Directory]::CreateDirectory($backupMods)|Out-Null
[IO.Directory]::CreateDirectory($backupShaderFixes)|Out-Null
[IO.Directory]::CreateDirectory($reportRoot)|Out-Null
[IO.Directory]::CreateDirectory($disabled)|Out-Null
$before = [Collections.Generic.List[object]]::new()
foreach ($name in $names) {
    $live = Join-Path $mods $name
    Copy-Item -LiteralPath $live -Destination $backupMods
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $live).Hash
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $backupMods $name)).Hash -ne $sha) { throw "Backup verification failed: $name" }
    $before.Add([ordered]@{relativePath=('Mods\'+$name);sha256=$sha})
}
Copy-Item -LiteralPath $nativeReplacement -Destination $backupShaderFixes
if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $backupShaderFixes 'e2aa1c8cb39e0a55-ps.txt')).Hash -ne $knownNativeReplacementSha) { throw 'Native replacement backup verification failed.' }
$before.Add([ordered]@{relativePath='ShaderFixes\e2aa1c8cb39e0a55-ps.txt';sha256=$knownNativeReplacementSha})
Copy-Item -LiteralPath $manifestPath -Destination $backup
Copy-Item -LiteralPath $contactReportPath -Destination (Join-Path $backup 'contact-family-install-report.json')

$installed = $false
try {
    Move-Item -LiteralPath $nativeReplacement -Destination (Join-Path $disabled 'e2aa1c8cb39e0a55-ps.txt')
    foreach ($name in $names) {
        Copy-Item -LiteralPath (Join-Path $sourceMods $name) -Destination (Join-Path $mods $name) -Force
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $mods $name)).Hash -ne [string]$packHashes[$name]) { throw "Post-stage mismatch: $name" }
    }
    $installed = $true
}
catch {
    foreach ($name in $names) { Copy-Item -LiteralPath (Join-Path $backupMods $name) -Destination (Join-Path $mods $name) -Force }
    $disabledNative = Join-Path $disabled 'e2aa1c8cb39e0a55-ps.txt'
    if (-not (Test-Path -LiteralPath $nativeReplacement) -and (Test-Path -LiteralPath $disabledNative)) { Move-Item -LiteralPath $disabledNative -Destination $nativeReplacement }
    throw
}

$failures = [Collections.Generic.List[string]]::new()
foreach ($name in $names) {
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $mods $name)).Hash -ne [string]$packHashes[$name]) { $failures.Add("live zero-pack mismatch: $name") }
}
if (Test-Path -LiteralPath $nativeReplacement) { $failures.Add('native e2aa replacement remains active') }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $contactIni).Hash -ne $contactReport.liveIniSha256) { $failures.Add('contact family changed during SSGI stage') }

$report = [ordered]@{
    schemaVersion=1;kind='ff7-remake-clean-owned-fullscreen-zero-stage';installed=$installed-and$failures.Count-eq0
    installedAt=(Get-Date).ToString('o');gameRoot=$game;packManifest=$manifestPath;backupDirectory=$backup
    disabledHybridDirectory=$disabled;before=@($before);after=@($names|ForEach-Object{[ordered]@{relativePath=('Mods\'+$_);sha256=[string]$packHashes[$_]}})
    nativeE2aaReplacement='disabled for single-path isolation';controls=[ordered]@{F2='owned zero pass off/on';F10='native reload untouched';PageUp='untouched';PageDown='contact master untouched';Number1='contact BaseT5';Number2='contact BaseT4';Number3='contact FrustumT4'}
    reloadRequired=$true;failures=@($failures)
}
$json=($report|ConvertTo-Json -Depth 8)+[Environment]::NewLine
[IO.File]::WriteAllText($reportPath,$json,$utf8)
[IO.File]::WriteAllText((Join-Path $backup 'stage-report.json'),$json,$utf8)
if ($failures.Count) { throw "Clean zero-stage verification failed: $($failures -join '; ')" }
Write-Host "BACKUP=$backup"
Write-Host "DISABLED_HYBRID=$disabled"
Write-Host "REPORT=$reportPath"
Write-Host 'PASS: single-path injector-owned literal-zero F2 diagnostic staged; native e2aa replacement disabled; contact families unchanged; F10 reload required.'
