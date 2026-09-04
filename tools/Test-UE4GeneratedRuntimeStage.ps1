[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$generatedRoot = Join-Path $repoRoot 'artifacts\generated-runtime\FF7RemakeIntergrade'
$generatedManifestPath = Join-Path $generatedRoot 'runtime-manifest.json'
$stageScript = Join-Path $repoRoot 'tools\Stage-UE4GeneratedRuntime.ps1'
$stageRoot = Join-Path $repoRoot 'artifacts\intergrade-runtime'

& $stageScript -ProjectRoot $repoRoot -GeneratedRuntimeDirectory $generatedRoot | Out-Null
$stageManifestPath = Join-Path $stageRoot 'stage-manifest.json'
$stageManifest = Get-Content -Raw -LiteralPath $stageManifestPath | ConvertFrom-Json
$generatedManifest = Get-Content -Raw -LiteralPath $generatedManifestPath | ConvertFrom-Json

if ($stageManifest.runtimeFlavor -ne 'generated-adapter') { throw 'Staged runtime flavor is not generated-adapter.' }
if ($stageManifest.generatedAdapterId -ne $generatedManifest.adapterId) { throw 'Staged adapter id mismatch.' }
if ($stageManifest.generatedRuntimeManifestSha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $generatedManifestPath).Hash) {
    throw 'Staged generated-runtime manifest hash mismatch.'
}
if ($stageManifest.emittedPasses -ne 3 -or $stageManifest.blockedPasses -ne 1) { throw 'Staged pass counts are incorrect.' }
$generatedPayload = @($generatedManifest.files)
$stagedMods = @(Get-ChildItem -LiteralPath (Join-Path $stageRoot 'Mods') -File)
if ($stagedMods.Count -ne $generatedPayload.Count) { throw 'Staged Mods payload contains stale or missing files.' }
foreach ($record in $generatedPayload) {
    $path = Join-Path $stageRoot ($record.relativePath -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Staged generated payload is missing: $path" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$record.sha256) {
        throw "Staged generated payload hash mismatch: $path"
    }
}
$ini = Get-Content -Raw -LiteralPath (Join-Path $stageRoot 'Mods\UE4EffectsGenerated.ini')
if ($ini -match 'e2aa1c8cb39e0a55') { throw 'Blocked SSR pass leaked into the staged runtime.' }
if (Test-Path -LiteralPath (Join-Path $stageRoot 'Mods\RebirthEffectsDX11.ini')) { throw 'Legacy rolling A/B config leaked into the clean generated stage.' }
if (Test-Path -LiteralPath (Join-Path $stageRoot 'Mods\RebirthFogGlobalDX11.ini')) { throw 'Legacy fog config leaked into the clean generated stage.' }

Write-Output 'UE4 generated runtime staging test passed.'
[pscustomobject]@{
    Adapter = $stageManifest.generatedAdapterId
    EmittedPasses = $stageManifest.emittedPasses
    BlockedPasses = $stageManifest.blockedPasses
    ModsFiles = $stagedMods.Count
    Result = 'pass'
}
