[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$GeneratedRuntimeDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\generated-runtime\FF7RemakeIntergrade'),
    [string]$GameRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$generatedRoot = (Resolve-Path -LiteralPath $GeneratedRuntimeDirectory).Path.TrimEnd('\')
$liveRoot = [IO.Path]::GetFullPath((Join-Path $GameRoot 'End\Binaries\Win64')).TrimEnd('\')
$logPath = Join-Path $liveRoot 'd3d11_log.txt'
$liveIniPath = Join-Path $liveRoot 'Mods\UE4EffectsGenerated.ini'
$installManifestPath = Join-Path $projectPath 'artifacts\installed-generated-runtime-overlay.json'
$generatedManifestPath = Join-Path $generatedRoot 'runtime-manifest.json'
$baselinePath = Join-Path $generatedRoot 'live-reload-baseline.json'
$utf8 = [Text.UTF8Encoding]::new($false)

foreach ($required in @($logPath, $liveIniPath, $installManifestPath, $generatedManifestPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required live-reload input is missing: $required" }
}
$log = Get-Item -LiteralPath $logPath
$process = Get-Process -Name 'ff7remake_' -ErrorAction Stop
if (@($process).Count -ne 1) { throw "Expected one running FF7 process, found $(@($process).Count)." }
$generatedManifest = Get-Content -Raw -LiteralPath $generatedManifestPath | ConvertFrom-Json
$installManifest = Get-Content -Raw -LiteralPath $installManifestPath | ConvertFrom-Json
if ([string]$generatedManifest.adapterId -ne [string]$installManifest.adapterId) { throw 'Generated and installed adapter ids differ.' }
$installedIni = @($installManifest.files | Where-Object relativePath -eq 'Mods/UE4EffectsGenerated.ini')
if ($installedIni.Count -ne 1) { throw 'Installed overlay manifest does not contain exactly one generated INI.' }
$liveIniSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $liveIniPath).Hash
if ($liveIniSha -ne [string]$installedIni[0].installedSha256) { throw 'Live generated INI differs from the installed overlay manifest.' }

$baseline = [ordered]@{
    schemaVersion = 1
    adapterId = [string]$generatedManifest.adapterId
    capturedAtUtc = [DateTime]::UtcNow.ToString('o')
    processId = [int]$process.Id
    processResponding = [bool]$process.Responding
    logPath = $logPath
    byteOffset = [long]$log.Length
    logLastWriteTimeUtc = $log.LastWriteTimeUtc.ToString('o')
    liveIniPath = $liveIniPath
    liveIniSha256 = $liveIniSha
    installedOverlayManifest = $installManifestPath.Substring($projectPath.Length + 1).Replace('\', '/')
    installedOverlayManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $installManifestPath).Hash
    generatedRuntimeManifest = $generatedManifestPath.Substring($projectPath.Length + 1).Replace('\', '/')
    generatedRuntimeManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $generatedManifestPath).Hash
    expectedControlKeys = @(
        'UE4FXFF7RemakeIntergradeTemporalVolume',
        'UE4FXFF7RemakeIntergradeSceneSaturation',
        'UE4FXFF7RemakeIntergradeAmbientOcclusion'
    )
    expectedEligibleHashes = @('ef7fe8d9c4e9ad15','af6cd28a0108a18a','a77b589dce5822d6')
    forbiddenBlockedHashes = @('e2aa1c8cb39e0a55')
}
[IO.File]::WriteAllText($baselinePath, ($baseline | ConvertTo-Json -Depth 6) + [Environment]::NewLine, $utf8)

[pscustomobject]@{
    Adapter = $baseline.adapterId
    ProcessId = $baseline.processId
    Responding = $baseline.processResponding
    ByteOffset = $baseline.byteOffset
    Baseline = $baselinePath
    Result = 'captured'
}
