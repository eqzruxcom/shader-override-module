[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$GameRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes',
    [string]$Version = '1.3.16',
    [ValidateSet('LogOnly', 'RenderTargets')]
    [string]$CaptureMode = 'LogOnly',
    [switch]$ExportShaders
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$archivePath = Join-Path $projectPath "reference\3Dmigoto-$Version.zip"
$stageRoot = Join-Path $projectPath 'artifacts\intergrade-runtime'
$expandRoot = Join-Path $projectPath "artifacts\official-3dmigoto-$Version"
$overlayRoot = Join-Path $projectPath 'runtime\Intergrade'
$targetDirectory = Join-Path $GameRoot 'End\Binaries\Win64'

if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw "Official 3Dmigoto archive is missing: $archivePath"
}

if (-not (Test-Path -LiteralPath $overlayRoot -PathType Container)) {
    throw "Runtime overlay is missing: $overlayRoot"
}

function Assert-WorkspaceChild {
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not $fullPath.StartsWith($projectPath + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing operation outside project workspace: $fullPath"
    }
}

Assert-WorkspaceChild -Path $stageRoot
Assert-WorkspaceChild -Path $expandRoot

if (-not (Test-Path -LiteralPath (Join-Path $expandRoot 'x64\d3d11.dll'))) {
    if (Test-Path -LiteralPath $expandRoot) {
        Remove-Item -LiteralPath $expandRoot -Recurse -Force
    }
    Expand-Archive -LiteralPath $archivePath -DestinationPath $expandRoot
}

if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $stageRoot | Out-Null
$officialX64 = Join-Path $expandRoot 'x64'

foreach ($name in @('d3d11.dll', 'd3dcompiler_46.dll', 'nvapi64.dll', 'd3dx.ini')) {
    Copy-Item -LiteralPath (Join-Path $officialX64 $name) -Destination (Join-Path $stageRoot $name)
}

Copy-Item -LiteralPath (Join-Path $overlayRoot 'Mods') -Destination (Join-Path $stageRoot 'Mods') -Recurse

$adapterShaderFixes = Join-Path $projectPath 'src\Adapters\FF7RemakeIntergrade\ShaderFixes'
$stagedShaderFixes = Join-Path $stageRoot 'ShaderFixes'
if (Test-Path -LiteralPath $adapterShaderFixes -PathType Container) {
    Copy-Item -LiteralPath $adapterShaderFixes -Destination $stagedShaderFixes -Recurse
} else {
    New-Item -ItemType Directory -Path $stagedShaderFixes | Out-Null
}

$configPath = Join-Path $stageRoot 'd3dx.ini'
$config = Get-Content -Raw -LiteralPath $configPath
$replacements = [ordered]@{
    ';include_recursive = Mods' = 'include_recursive = Mods'
    'hunting=1' = 'hunting=2'
    'marking_actions = clipboard regex hlsl asm stereo_snapshot snapshot_if_pink' = 'marking_actions = clipboard hlsl asm mono_snapshot'
    ';previous_rendertarget = no_modifiers VK_INSERT' = 'previous_rendertarget = ctrl no_shift no_alt VK_INSERT'
    ';next_rendertarget = no_modifiers VK_HOME' = 'next_rendertarget = ctrl no_shift no_alt VK_HOME'
    ';mark_rendertarget = no_modifiers VK_PAGEUP' = 'mark_rendertarget = ctrl no_shift no_alt VK_PAGEUP'
    'verbose_overlay = 0' = 'verbose_overlay = 1'
    ';analyse_frame = no_modifiers VK_F8' = 'analyse_frame = no_modifiers VK_F8'
}

foreach ($entry in $replacements.GetEnumerator()) {
    if (-not $config.Contains($entry.Key)) {
        throw "Expected 3Dmigoto template setting not found: $($entry.Key)"
    }
    $config = $config.Replace($entry.Key, $entry.Value)
}

$captureTemplate = ';analyse_options = dump_rt jps clear_rt'
$captureOptions = switch ($CaptureMode) {
    'LogOnly' { 'mono' }
    'RenderTargets' { 'dump_rt jps mono desc' }
}
if (-not $config.Contains($captureTemplate)) {
    throw "Expected 3Dmigoto template setting not found: $captureTemplate"
}
$config = $config.Replace($captureTemplate, "analyse_options = $captureOptions")

if ($ExportShaders) {
    if (-not $config.Contains('export_shaders=0')) {
        throw 'Expected 3Dmigoto export_shaders setting not found.'
    }
    $config = $config.Replace('export_shaders=0', 'export_shaders=1')
}

Set-Content -LiteralPath $configPath -Value $config -Encoding UTF8

$files = foreach ($file in Get-ChildItem -LiteralPath $stageRoot -Recurse -File) {
    [pscustomobject]@{
        relativePath = $file.FullName.Substring($stageRoot.Length + 1)
        size = $file.Length
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
}

$manifest = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    renderer = 'D3D11'
    launchArgument = '-dx11'
    captureMode = $CaptureMode
    analyseOptions = $captureOptions
    exportShaders = [bool]$ExportShaders
    targetDirectory = $targetDirectory
    officialRuntime = [ordered]@{
        project = 'bo3b/3Dmigoto'
        version = $Version
        archiveSha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
        architecture = 'x64'
    }
    files = @($files | Sort-Object relativePath)
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $stageRoot 'stage-manifest.json') -Encoding UTF8

Write-Output "Staged official 3Dmigoto $Version x64 runtime at:"
Write-Output $stageRoot
Write-Output "Intended game directory (not modified):"
Write-Output $targetDirectory
