[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$GeneratedRuntimeDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\generated-runtime\FF7RemakeIntergradeScenePostDiagnostic'),
    [string]$InstallManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\installed-scene-post-diagnostic-overlay.json'),
    [string]$GameRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes',
    [int]$ProcessId = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$generatedRoot = (Resolve-Path -LiteralPath $GeneratedRuntimeDirectory).Path.TrimEnd('\')
$installPath = (Resolve-Path -LiteralPath $InstallManifestPath).Path
$liveRoot = [IO.Path]::GetFullPath((Join-Path $GameRoot 'End\Binaries\Win64')).TrimEnd('\')
$logPath = Join-Path $liveRoot 'd3d11_log.txt'
$liveIniPath = Join-Path $liveRoot 'Mods\UE4EffectsGenerated.ini'
$generatedManifestPath = Join-Path $generatedRoot 'runtime-manifest.json'
$baselinePath = Join-Path $generatedRoot 'live-reload-baseline.json'
$utf8 = [Text.UTF8Encoding]::new($false)
foreach ($path in @($logPath,$liveIniPath,$generatedManifestPath,$installPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required diagnostic reload input is missing: $path" }
}
$generated = Get-Content -Raw -LiteralPath $generatedManifestPath | ConvertFrom-Json
$installed = Get-Content -Raw -LiteralPath $installPath | ConvertFrom-Json
$neutralIsolation = [string]$generated.adapterId -eq 'FF7RemakeIntergradeScenePostNeutralIsolation'
$tonemapIsolation = [string]$generated.adapterId -eq 'FF7RemakeIntergradeScenePostTonemapIsolation'
$expectedStatus = if ($tonemapIsolation) { 'effect-live-validation-pending' } else { 'neutral-live-parity-pending' }
if (-not [bool]$generated.diagnosticOnly -or [string]$generated.status -ne $expectedStatus) {
    throw 'Generated runtime is not the pending scene-post diagnostic.'
}
if ([string]$generated.adapterId -ne [string]$installed.adapterId) { throw 'Diagnostic generated and installed adapter ids differ.' }
foreach ($record in @($installed.files)) {
    $destination = [IO.Path]::GetFullPath((Join-Path $liveRoot ([string]$record.relativePath -replace '/', '\')))
    if (-not $destination.StartsWith($liveRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Installed diagnostic path escaped the live runtime.' }
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) { throw "Installed diagnostic file is missing: $destination" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash -ne [string]$record.installedSha256) {
        throw "Installed diagnostic file hash changed: $($record.relativePath)"
    }
}
$process = @(if ($ProcessId -gt 0) {
    Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
} else {
    Get-Process -Name 'ff7remake_' -ErrorAction SilentlyContinue
})
if ($process.Count -ne 1) { throw "Expected one target process, found $($process.Count)." }
$log = Get-Item -LiteralPath $logPath
$baseline = [ordered]@{
    schemaVersion = 1
    adapterId = [string]$generated.adapterId
    diagnostic = if ($neutralIsolation) { 'scene-post-neutral-isolation' } elseif ($tonemapIsolation) { 'scene-post-tonemap-isolation' } else { 'scene-post-tonemap-a-b' }
    capturedAtUtc = [DateTime]::UtcNow.ToString('o')
    processId = [int]$process[0].Id
    processResponding = [bool]$process[0].Responding
    logPath = $logPath
    byteOffset = [long]$log.Length
    logLastWriteTimeUtc = $log.LastWriteTimeUtc.ToString('o')
    liveIniPath = $liveIniPath
    liveIniSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $liveIniPath).Hash
    installedOverlayManifest = $installPath.Substring($projectPath.Length + 1).Replace('\','/')
    installedOverlayManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $installPath).Hash
    generatedRuntimeManifest = $generatedManifestPath.Substring($projectPath.Length + 1).Replace('\','/')
    generatedRuntimeManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $generatedManifestPath).Hash
    expectedControlKeys = @(if ($neutralIsolation) {
        'UE4FXScenePostNeutralAB'
    } elseif ($tonemapIsolation) {
        'UE4FXScenePostTonemapAB'
    } else {
        'UE4FXFF7RemakeIntergradeTemporalVolume'
        'UE4FXFF7RemakeIntergradeSceneSaturation'
        'UE4FXFF7RemakeIntergradeAmbientOcclusion'
        'UE4FXFF7RemakeIntergradeTonemapAB'
    })
    expectedEligibleHashes = @(if ($neutralIsolation -or $tonemapIsolation) { 'af6cd28a0108a18a' } else { 'ef7fe8d9c4e9ad15'; 'af6cd28a0108a18a'; 'a77b589dce5822d6' })
    forbiddenBlockedHashes = @('e2aa1c8cb39e0a55')
}
[IO.File]::WriteAllText($baselinePath, ($baseline | ConvertTo-Json -Depth 7)+[Environment]::NewLine, $utf8)

[pscustomobject]@{
    Adapter = [string]$baseline.adapterId
    ProcessId = [int]$baseline.processId
    Responding = [bool]$baseline.processResponding
    ByteOffset = [long]$baseline.byteOffset
    Baseline = $baselinePath
    Result = 'captured-before-diagnostic-reload'
}
