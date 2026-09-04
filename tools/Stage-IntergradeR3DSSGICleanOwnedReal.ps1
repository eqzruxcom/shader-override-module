[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ZeroStageReportPath,
    [Parameter(Mandatory)][string]$ContactInstallReportPath,
    [string]$GameRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64',
    [string]$PackRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\agent2-r3d-ssgi-clean-owned-real-pack'),
    [string]$BackupRoot = 'F:\Shader3Dmigoto\FF7Remake\IndirectLighting',
    [switch]$AcknowledgeZeroVisualParity,
    [switch]$PreflightOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $PreflightOnly -and -not $AcknowledgeZeroVisualParity) {
    throw 'Pass -AcknowledgeZeroVisualParity only after F10 reload and repeated F2 toggles produce no visual change.'
}

$workspace = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent)).TrimEnd('\')
$game = [IO.Path]::GetFullPath($GameRoot).TrimEnd('\')
$pack = [IO.Path]::GetFullPath($PackRoot).TrimEnd('\')
$backupBase = [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')
$zeroReportPath = [IO.Path]::GetFullPath($ZeroStageReportPath)
$contactReportPath = [IO.Path]::GetFullPath($ContactInstallReportPath)

if (-not $game.EndsWith('\End\Binaries\Win64', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'GameRoot must be an exact FF7 Remake Win64 directory.'
}
if (-not $pack.StartsWith((Join-Path $workspace 'artifacts') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'PackRoot must remain beneath workspace artifacts.'
}
if (-not $backupBase.StartsWith('F:\Shader3Dmigoto\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'BackupRoot must remain beneath F:\Shader3Dmigoto.'
}

$mods = Join-Path $game 'Mods'
$shaderFixes = Join-Path $game 'ShaderFixes'
$sourceMods = Join-Path $pack 'Mods'
$manifestPath = Join-Path $pack 'manifest.json'
$contactIni = Join-Path $mods 'ContactShadows.ini'
$nativeE2aa = Join-Path $shaderFixes 'e2aa1c8cb39e0a55-ps.txt'
$names = @(
    'Agent2R3DSSGITest.ini',
    'Agent2R3DSSGIFullscreen_vs.hlsl',
    'Agent2R3DSSGITraceE2AA_ps.hlsl',
    'Agent2R3DSSGIDenoise2_ps.hlsl',
    'Agent2R3DSSGIDenoise4_ps.hlsl',
    'Agent2R3DSSGIDenoise8_ps.hlsl',
    'Agent2R3DSSGIDenoise16_ps.hlsl',
    'Agent2R3DSSGICompositeE2AA_ps.hlsl'
)

foreach ($path in @($mods, $shaderFixes, $manifestPath, $zeroReportPath, $contactReportPath, $contactIni)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required path is missing: $path" }
}
if (Test-Path -LiteralPath $nativeE2aa) {
    throw 'The native e2aa replacement is active. Refusing a second indirect-light composition path.'
}

$zeroReport = Get-Content -Raw -LiteralPath $zeroReportPath | ConvertFrom-Json
if ($zeroReport.schemaVersion -ne 1 -or $zeroReport.kind -ne 'ff7-remake-clean-owned-fullscreen-zero-stage' -or
    $zeroReport.installed -ne $true -or $zeroReport.gameRoot -ne $game -or $zeroReport.nativeE2aaReplacement -ne 'disabled for single-path isolation' -or
    $zeroReport.reloadRequired -ne $true -or @($zeroReport.after).Count -ne 8 -or @($zeroReport.failures).Count -ne 0) {
    throw 'Zero-stage report contract is invalid or does not describe this game root.'
}

$contactReport = Get-Content -Raw -LiteralPath $contactReportPath | ConvertFrom-Json
if (-not $contactReport.installed -or $contactReport.liveIniSha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $contactIni).Hash) {
    throw 'Contact-family report does not match the current live ContactShadows.ini.'
}
foreach ($hash in @('08bb8764f1840179','0e97888f9a8767da','5a9fbefe0ab6f815','62b33a2d1e505241','c30cdc8365df9840')) {
    if (Test-Path -LiteralPath (Join-Path $shaderFixes ($hash + '-cs.txt'))) {
        throw "Explicit contact shader unexpectedly returned live: $hash"
    }
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.result -ne 'pass' -or
    $manifest.kind -ne 'ff7-remake-clean-owned-fullscreen-real-ssgi' -or
    $manifest.nativeE2aaReplacementIncluded -ne $false -or $manifest.runtimeEligible -ne $false -or
    $manifest.ownedPass.draw -ne '3, 0' -or @($manifest.files).Count -ne 8 -or @($manifest.compile).Count -ne 7) {
    throw 'Clean real-pack manifest contract is invalid.'
}

$realHashes = [ordered]@{}
foreach ($file in @($manifest.files)) {
    $name = [string]$file.name
    if ($name -notin $names) { throw "Unexpected real-pack file: $name" }
    $path = Join-Path $sourceMods $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Real-pack file is missing: $path" }
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    if ($sha -ne [string]$file.sha256) { throw "Real-pack file drifted: $name" }
    $realHashes[$name] = $sha
}
if ((@($realHashes.Keys | Sort-Object) -join '|') -ne (@($names | Sort-Object) -join '|')) {
    throw 'Clean real-pack file set is incomplete.'
}

$zeroHashes = [ordered]@{}
foreach ($file in @($zeroReport.after)) {
    $name = Split-Path -Leaf ([string]$file.relativePath)
    if ($name -notin $names) { throw "Unexpected zero-stage live file: $name" }
    $zeroHashes[$name] = [string]$file.sha256
}
if ((@($zeroHashes.Keys | Sort-Object) -join '|') -ne (@($names | Sort-Object) -join '|')) {
    throw 'Zero-stage report file set is incomplete.'
}
foreach ($name in $names) {
    $live = Join-Path $mods $name
    if (-not (Test-Path -LiteralPath $live -PathType Leaf)) { throw "Live zero-stage file is missing: $name" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $live).Hash -ne [string]$zeroHashes[$name]) {
        throw "Live zero-stage file drifted before parity promotion: $name"
    }
}

$liveZeroComposite = [IO.File]::ReadAllText((Join-Path $mods 'Agent2R3DSSGICompositeE2AA_ps.hlsl'))
$realComposite = [IO.File]::ReadAllText((Join-Path $sourceMods 'Agent2R3DSSGICompositeE2AA_ps.hlsl'))
$realIni = [IO.File]::ReadAllText((Join-Path $sourceMods 'Agent2R3DSSGITest.ini'))
if ($liveZeroComposite -notmatch '(?m)^\s*return\s+0\.0\s*;') { throw 'Live prerequisite is not the literal-zero composite.' }
if ($realComposite -notmatch '(?m)^\s*return float4\(indirectRadiance, 0\.0\);\s*$') { throw 'Real composite output is missing.' }
foreach ($needle in @('key = no_modifiers F2','vs = Agent2R3DSSGIFullscreen_vs.hlsl','draw = 3, 0','blend = ADD ONE ONE')) {
    if (-not $realIni.Contains($needle)) { throw "Real pack lacks required contract: $needle" }
}
if ($realIni -match '(?im)^\s*key\s*=.*(?:F10|VK_PRIOR|VK_NEXT).*$') {
    throw 'Real pack attempts to capture a reserved key.'
}

if ($PreflightOnly) {
    [pscustomobject]@{
        Result = 'pass'
        Mode = 'preflight-only'
        LivePrerequisite = 'exact clean literal-zero owned pass'
        RealPayloadFiles = $realHashes.Count
        CompiledShaders = @($manifest.compile).Count
        NativeE2aaReplacement = $false
        ContactFamilyUnchanged = $true
        ZeroParityAcknowledged = [bool]$AcknowledgeZeroVisualParity
        InstallPerformed = $false
    }
    exit 0
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$backup = Join-Path $backupBase ($timestamp + '-pre-clean-owned-real')
$backupMods = Join-Path $backup 'Mods'
$reportRoot = Join-Path $workspace ('artifacts\indirect-clean-owned-real-stage-' + $timestamp)
$reportPath = Join-Path $reportRoot 'stage-report.json'
$utf8 = [Text.UTF8Encoding]::new($false)
if (Test-Path -LiteralPath $backup) { throw "Backup already exists: $backup" }

[IO.Directory]::CreateDirectory($backupMods) | Out-Null
[IO.Directory]::CreateDirectory($reportRoot) | Out-Null
foreach ($name in $names) {
    $live = Join-Path $mods $name
    Copy-Item -LiteralPath $live -Destination (Join-Path $backupMods $name)
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $backupMods $name)).Hash -ne [string]$zeroHashes[$name]) {
        throw "Backup verification failed: $name"
    }
}
Copy-Item -LiteralPath $zeroReportPath -Destination (Join-Path $backup 'zero-stage-report.json')
Copy-Item -LiteralPath $contactReportPath -Destination (Join-Path $backup 'contact-family-install-report.json')
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $backup 'real-pack-manifest.json')

$installed = $false
try {
    foreach ($name in $names) {
        Copy-Item -LiteralPath (Join-Path $sourceMods $name) -Destination (Join-Path $mods $name) -Force
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $mods $name)).Hash -ne [string]$realHashes[$name]) {
            throw "Post-stage mismatch: $name"
        }
    }
    $installed = $true
}
catch {
    foreach ($name in $names) {
        Copy-Item -LiteralPath (Join-Path $backupMods $name) -Destination (Join-Path $mods $name) -Force
    }
    throw
}

$failures = [Collections.Generic.List[string]]::new()
foreach ($name in $names) {
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $mods $name)).Hash -ne [string]$realHashes[$name]) {
        $failures.Add("live real-pack mismatch: $name")
    }
}
if (Test-Path -LiteralPath $nativeE2aa) { $failures.Add('native e2aa replacement returned active') }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $contactIni).Hash -ne $contactReport.liveIniSha256) {
    $failures.Add('contact family changed during real SSGI stage')
}

$report = [ordered]@{
    schemaVersion = 1
    kind = 'ff7-remake-clean-owned-fullscreen-real-stage'
    installed = $installed -and $failures.Count -eq 0
    installedAt = (Get-Date).ToString('o')
    zeroVisualParityAcknowledged = $true
    gameRoot = $game
    packManifest = $manifestPath
    backupDirectory = $backup
    priorZeroStageReport = $zeroReportPath
    contactInstallReport = $contactReportPath
    architecture = 'single injector-owned fullscreen indirect composite; native e2aa replacement absent'
    controls = [ordered]@{
        F2 = 'real indirect pass off/on'
        F10 = 'native reload untouched'
        PageUp = 'untouched'
        PageDown = 'contact master untouched'
        Number1 = 'contact BaseT5'
        Number2 = 'contact BaseT4'
        Number3 = 'contact FrustumT4'
    }
    after = @($names | ForEach-Object { [ordered]@{ relativePath = ('Mods\' + $_); sha256 = [string]$realHashes[$_] } })
    nativeE2aaReplacement = 'absent'
    contactFamilyUnchanged = $true
    reloadRequired = $true
    liveRgbValidationPending = $true
    failures = @($failures)
}
$json = ($report | ConvertTo-Json -Depth 10) + [Environment]::NewLine
[IO.File]::WriteAllText($reportPath, $json, $utf8)
[IO.File]::WriteAllText((Join-Path $backup 'stage-report.json'), $json, $utf8)
if ($failures.Count) { throw "Clean real-stage verification failed: $($failures -join '; ')" }

Write-Host "BACKUP=$backup"
Write-Host "REPORT=$reportPath"
Write-Host 'PASS: clean single-path 25% indirect RGB candidate staged; native e2aa replacement remains absent; contact families unchanged; F10 reload required.'
