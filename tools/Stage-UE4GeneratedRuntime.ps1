[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$GeneratedRuntimeDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\generated-runtime\FF7RemakeIntergrade'),
    [string]$GameRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes',
    [string]$Version = '1.3.16',
    [ValidateSet('LogOnly', 'RenderTargets')]
    [string]$CaptureMode = 'LogOnly',
    [switch]$ExportShaders
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$generatedRoot = (Resolve-Path -LiteralPath $GeneratedRuntimeDirectory).Path.TrimEnd('\')
$allowedGeneratedRoot = [IO.Path]::GetFullPath((Join-Path $projectPath 'artifacts\generated-runtime')).TrimEnd('\')
$stageRoot = [IO.Path]::GetFullPath((Join-Path $projectPath 'artifacts\intergrade-runtime')).TrimEnd('\')
$modsPath = Join-Path $stageRoot 'Mods'
$generatedMods = Join-Path $generatedRoot 'Mods'
$generatedManifestPath = Join-Path $generatedRoot 'runtime-manifest.json'
$stageScript = Join-Path $projectPath 'tools\Stage-IntergradeRuntime.ps1'
$utf8 = [Text.UTF8Encoding]::new($false)

if (-not $generatedRoot.StartsWith($allowedGeneratedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Generated runtime must remain below $allowedGeneratedRoot."
}
if (-not (Test-Path -LiteralPath $generatedMods -PathType Container)) { throw "Generated Mods payload is missing: $generatedMods" }
if (-not (Test-Path -LiteralPath $generatedManifestPath -PathType Leaf)) { throw "Generated runtime manifest is missing: $generatedManifestPath" }
$generatedManifest = Get-Content -Raw -LiteralPath $generatedManifestPath | ConvertFrom-Json
if ([bool]$generatedManifest.licensedRegexDependency) { throw 'Refusing to stage a runtime with a licensed regex dependency.' }
if ([int]$generatedManifest.emittedPasses -lt 1) { throw 'Generated runtime contains no eligible passes.' }

$stageArgs = @{
    ProjectRoot = $projectPath
    GameRoot = $GameRoot
    Version = $Version
    CaptureMode = $CaptureMode
}
if ($ExportShaders) { $stageArgs.ExportShaders = $true }
& $stageScript @stageArgs | Out-Null

$resolvedStage = (Resolve-Path -LiteralPath $stageRoot).Path.TrimEnd('\')
$resolvedMods = (Resolve-Path -LiteralPath $modsPath).Path.TrimEnd('\')
if (-not $resolvedStage.StartsWith($projectPath + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Staged runtime escaped the project: $resolvedStage"
}
if (-not $resolvedMods.StartsWith($resolvedStage + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Staged Mods path escaped the runtime stage: $resolvedMods"
}

Remove-Item -LiteralPath $resolvedMods -Recurse -Force
Copy-Item -LiteralPath $generatedMods -Destination $modsPath -Recurse

$stageManifestPath = Join-Path $stageRoot 'stage-manifest.json'
$stageManifest = Get-Content -Raw -LiteralPath $stageManifestPath | ConvertFrom-Json
$files = foreach ($file in Get-ChildItem -LiteralPath $stageRoot -Recurse -File | Where-Object FullName -ne $stageManifestPath) {
    [pscustomobject][ordered]@{
        relativePath = $file.FullName.Substring($stageRoot.Length + 1)
        size = $file.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
    }
}
$stageManifest | Add-Member -NotePropertyName runtimeFlavor -NotePropertyValue 'generated-adapter' -Force
$stageManifest | Add-Member -NotePropertyName generatedAdapterId -NotePropertyValue ([string]$generatedManifest.adapterId) -Force
$stageManifest | Add-Member -NotePropertyName generatedRuntimeManifest -NotePropertyValue $generatedManifestPath.Substring($projectPath.Length + 1).Replace('\', '/') -Force
$stageManifest | Add-Member -NotePropertyName generatedRuntimeManifestSha256 -NotePropertyValue ((Get-FileHash -Algorithm SHA256 -LiteralPath $generatedManifestPath).Hash) -Force
$stageManifest | Add-Member -NotePropertyName emittedPasses -NotePropertyValue ([int]$generatedManifest.emittedPasses) -Force
$stageManifest | Add-Member -NotePropertyName blockedPasses -NotePropertyValue (@($generatedManifest.blockedPasses).Count) -Force
$stageManifest.files = @($files | Sort-Object relativePath)
[IO.File]::WriteAllText($stageManifestPath, ($stageManifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine, $utf8)

[pscustomobject]@{
    RuntimeFlavor = 'generated-adapter'
    Adapter = [string]$generatedManifest.adapterId
    EmittedPasses = [int]$generatedManifest.emittedPasses
    BlockedPasses = @($generatedManifest.blockedPasses).Count
    PayloadFiles = @($stageManifest.files).Count
    Output = $stageRoot
    Manifest = $stageManifestPath
    ManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $stageManifestPath).Hash
}
