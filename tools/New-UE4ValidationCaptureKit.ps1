[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ue4-validation-capture-kit'),
    [string]$Version = '1.3.16'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$outputFull = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $projectPath 'artifacts')).TrimEnd('\')
$archivePath = Join-Path $projectPath "reference\3Dmigoto-$Version.zip"
$expandRoot = Join-Path $projectPath "artifacts\official-3dmigoto-$Version"
$utf8 = [Text.UTF8Encoding]::new($false)

if (-not $outputFull.StartsWith($allowedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Capture-kit output must remain below the project artifacts directory.'
}
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) { throw "Official 3Dmigoto archive is missing: $archivePath" }
if (-not (Test-Path -LiteralPath (Join-Path $expandRoot 'x64\d3d11.dll') -PathType Leaf)) {
    if (Test-Path -LiteralPath $expandRoot) { Remove-Item -LiteralPath $expandRoot -Recurse -Force }
    Expand-Archive -LiteralPath $archivePath -DestinationPath $expandRoot
}

if (Test-Path -LiteralPath $outputFull) { Remove-Item -LiteralPath $outputFull -Recurse -Force }
[IO.Directory]::CreateDirectory($outputFull) | Out-Null
$officialX64 = Join-Path $expandRoot 'x64'
foreach ($name in @('d3d11.dll','d3dcompiler_46.dll','nvapi64.dll','d3dx.ini')) {
    Copy-Item -LiteralPath (Join-Path $officialX64 $name) -Destination (Join-Path $outputFull $name)
}

$configPath = Join-Path $outputFull 'd3dx.ini'
$config = [IO.File]::ReadAllText($configPath)
$replacements = [ordered]@{
    'hunting=1' = 'hunting=2'
    'marking_actions = clipboard regex hlsl asm stereo_snapshot snapshot_if_pink' = 'marking_actions = clipboard hlsl asm mono_snapshot'
    'verbose_overlay = 0' = 'verbose_overlay = 1'
    ';analyse_frame = no_modifiers VK_F8' = 'analyse_frame = no_modifiers VK_F8'
    ';analyse_options = dump_rt jps clear_rt' = 'analyse_options = dump_rt jps mono desc'
    'cache_shaders=0' = 'cache_shaders=1'
    'export_shaders=0' = 'export_shaders=1'
}
foreach ($entry in $replacements.GetEnumerator()) {
    if (-not $config.Contains($entry.Key)) { throw "Expected official 3Dmigoto setting was not found: $($entry.Key)" }
    $config = $config.Replace($entry.Key, $entry.Value)
}
[IO.File]::WriteAllText($configPath, $config, $utf8)

$instructions = @'
UE4 DX11/SM5 validation capture kit

1. Confirm the game supports DirectX 11 / Shader Model 5.
2. From the project root, install this kit with:
   .\tools\Install-UE4ValidationCaptureKit.ps1 -GameExecutable '<game Win64 exe>' -CaptureId '<capture-id>'
3. Launch the game in DX11 mode and enter a representative gameplay scene.
4. Press F8 once for a frame analysis, then exercise several scenes/effects.
5. Exit normally so d3d11_log.txt and ShaderCache are flushed.
6. From the project root, import, scan, and produce fail-closed candidates with:
   .\tools\Invoke-UE4ValidationCapturePipeline.ps1 -CaptureDirectory '<game Win64 directory>' -CaptureId '<capture-id>' -InstallManifestPath '.\artifacts\installed-validation-capture-kits\<capture-id>.json'
7. Roll back the neutral capture runtime with:
   .\tools\Uninstall-UE4ValidationCaptureKit.ps1 -CaptureId '<capture-id>'

Candidate reports are review evidence only and can never enable runtime replacement by themselves.

This kit contains no game replacement shaders, Mods directory, or FF7 hashes.
Captured game shaders and disassembly are local research evidence and must not be redistributed.
'@
[IO.File]::WriteAllText((Join-Path $outputFull 'CAPTURE-INSTRUCTIONS.txt'), $instructions.Trim() + [Environment]::NewLine, $utf8)

$payload = foreach ($file in Get-ChildItem -LiteralPath $outputFull -File) {
    [pscustomobject][ordered]@{
        relativePath = $file.Name
        size = $file.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
    }
}
$manifest = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    purpose = 'game-neutral UE4 DX11/SM5 shader capture'
    renderer = 'D3D11'
    shaderModel = 'SM5'
    failClosed = $true
    containsReplacementShaders = $false
    containsGameShaderHashes = $false
    redistribution = 'runtime files retain upstream licenses; captured game shaders must not be redistributed'
    officialRuntime = [ordered]@{
        project = 'bo3b/3Dmigoto'
        version = $Version
        archiveSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash
        architecture = 'x64'
    }
    controls = [ordered]@{ analyseFrame = 'F8'; toggleHunting = 'Numpad0'; showOriginal = 'F9'; reload = 'F10' }
    files = @($payload | Sort-Object relativePath)
}
$manifestPath = Join-Path $outputFull 'capture-kit-manifest.json'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 7) + [Environment]::NewLine, $utf8)

[pscustomobject]@{
    Output = $outputFull
    PayloadFiles = @($manifest.files).Count
    Manifest = $manifestPath
    Result = 'generated-neutral-capture-kit'
}
