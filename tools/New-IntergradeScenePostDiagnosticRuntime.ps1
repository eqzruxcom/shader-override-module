[CmdletBinding()]
param(
    [string]$BaselineRuntimeDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\generated-runtime\FF7RemakeIntergrade'),
    [string]$ScenePostDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\scene-post-generator'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\generated-runtime\FF7RemakeIntergradeScenePostDiagnostic')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$baselineRoot = (Resolve-Path -LiteralPath $BaselineRuntimeDirectory).Path.TrimEnd('\')
$scenePostRoot = [IO.Path]::GetFullPath($ScenePostDirectory).TrimEnd('\')
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$allowedOutput = [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts\generated-runtime')).TrimEnd('\')
$utf8 = [Text.UTF8Encoding]::new($false)
if (-not $baselineRoot.StartsWith($allowedOutput + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Baseline runtime escaped artifacts/generated-runtime.' }
if (-not $outputRoot.StartsWith($allowedOutput + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Diagnostic runtime escaped artifacts/generated-runtime.' }

$baselineManifestPath = Join-Path $baselineRoot 'runtime-manifest.json'
$baselineIniPath = Join-Path $baselineRoot 'Mods\UE4EffectsGenerated.ini'
$scenePostManifestPath = Join-Path $scenePostRoot 'RebirthPostSceneControls_ps.json'
if (-not (Test-Path -LiteralPath $scenePostManifestPath -PathType Leaf)) {
    & (Join-Path $PSScriptRoot 'New-IntergradeScenePostVariant.ps1') -OutputDirectory $scenePostRoot | Out-Null
}
foreach ($path in @($baselineManifestPath,$baselineIniPath,$scenePostManifestPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required diagnostic input is missing: $path" }
}
$baselineManifest = Get-Content -Raw -LiteralPath $baselineManifestPath | ConvertFrom-Json
$scenePostManifest = Get-Content -Raw -LiteralPath $scenePostManifestPath | ConvertFrom-Json
if ($scenePostManifest.status -ne 'strict-compile-neutral-live-parity-pending') { throw 'Scene-post shader is not in the expected pre-live status.' }
$scenePostSource = [IO.Path]::GetFullPath((Join-Path $repoRoot ([string]$scenePostManifest.source -replace '/', '\')))
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $scenePostSource).Hash -ne [string]$scenePostManifest.sourceSha256) {
    throw 'Scene-post source hash does not match its manifest.'
}

$ini = [IO.File]::ReadAllText($baselineIniPath).Replace("`r`n", "`n")
$globalLine = 'global $ue4fx_ff7remakeintergrade_scene_saturation = 4'
if (([regex]::Matches($ini, [regex]::Escape($globalLine))).Count -ne 1) { throw 'Baseline scene-saturation global is not unique.' }
$ini = $ini.Replace($globalLine + "`n", '')
if (([regex]::Matches($ini, '(?m)^\[Constants\]$')).Count -ne 1) { throw 'Baseline Constants section is not unique.' }
$ini = $ini.Replace("[Constants]`n", "[Constants]`nx101 = 1.0`nw101 = 0.0`n")

$removeSections = @('KeyUE4FXFF7RemakeIntergradeSceneSaturation')
foreach ($index in 0..3) {
    $removeSections += "CustomShaderUE4FXFF7RemakeIntergradeSceneSaturationL$index"
    $removeSections += "ShaderOverrideUE4FXFF7RemakeIntergradeSceneSaturationL$index"
}
foreach ($section in $removeSections) {
    $pattern = '(?ms)^\[' + [regex]::Escape($section) + '\]\n.*?(?=^\[|\z)'
    $matches = [regex]::Matches($ini, $pattern)
    if ($matches.Count -ne 1) { throw "Expected one baseline INI section '$section', found $($matches.Count)." }
    $ini = [regex]::Replace($ini, $pattern, '', 1)
}
$diagnosticBlock = @'
[KeyUE4FXFF7RemakeIntergradeSceneSaturation]
key = no_modifiers VK_INSERT
type = cycle
smart = true
x101 = 1.0, 0.75, 0.5, 0.25, 0.0

[KeyUE4FXFF7RemakeIntergradeTonemapAB]
key = no_modifiers VK_PAGEDOWN
type = cycle
smart = true
w101 = 0.0, 1.0

[CustomShaderUE4FXFF7RemakeIntergradeScenePostDiagnostic]
ps = RebirthPostSceneControls_ps.hlsl
handling = skip
draw = from_caller

[ShaderOverrideUE4FXFF7RemakeIntergradeScenePostDiagnostic]
hash = af6cd28a0108a18a
allow_duplicate_hash = true
run = CustomShaderUE4FXFF7RemakeIntergradeScenePostDiagnostic
'@ -replace "`r`n", "`n"
$ini = $ini.TrimEnd() + "`n`n" + $diagnosticBlock.Trim() + "`n"
if (([regex]::Matches($ini, '(?m)^hash = af6cd28a0108a18a$')).Count -ne 1) { throw 'Diagnostic runtime must contain exactly one scene-post hash override.' }
if ($ini -match 'SceneSaturationL[0-3]|\$ue4fx_ff7remakeintergrade_scene_saturation') { throw 'Static scene-saturation runtime state leaked into the diagnostic INI.' }

if (Test-Path -LiteralPath $outputRoot -PathType Container) {
    $resolved = (Resolve-Path -LiteralPath $outputRoot).Path.TrimEnd('\')
    if (-not $resolved.StartsWith($allowedOutput + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to replace unsafe diagnostic output.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
$mods = Join-Path $outputRoot 'Mods'
[IO.Directory]::CreateDirectory($mods) | Out-Null
$diagnosticIniPath = Join-Path $mods 'UE4EffectsGenerated.ini'
$diagnosticShaderPath = Join-Path $mods 'RebirthPostSceneControls_ps.hlsl'
[IO.File]::WriteAllText($diagnosticIniPath, $ini.Replace("`n", "`r`n"), $utf8)
Copy-Item -LiteralPath $scenePostSource -Destination $diagnosticShaderPath

$files = foreach ($file in @($diagnosticIniPath,$diagnosticShaderPath)) {
    [pscustomobject][ordered]@{
        relativePath = 'Mods/' + [IO.Path]::GetFileName($file)
        size = (Get-Item -LiteralPath $file).Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash
    }
}
$manifest = [ordered]@{
    schemaVersion = 1
    adapterId = 'FF7RemakeIntergradeScenePostDiagnostic'
    renderer = 'D3D11'
    executable = $baselineManifest.executable
    sourceAdapter = [string]$baselineManifest.sourceAdapter
    sourceAdapterSha256 = [string]$baselineManifest.sourceAdapterSha256
    licensedRegexDependency = $false
    diagnosticOnly = $true
    failClosed = $true
    status = 'neutral-live-parity-pending'
    shaderHash = 'af6cd28a0108a18a'
    baselineRuntimeManifest = $baselineManifestPath.Substring($repoRoot.Length + 1).Replace('\','/')
    baselineRuntimeManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $baselineManifestPath).Hash
    scenePostManifest = $scenePostManifestPath.Substring($repoRoot.Length + 1).Replace('\','/')
    scenePostManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $scenePostManifestPath).Hash
    controls = @(
        [ordered]@{ key='VK_INSERT';effect='scene-saturation';values=@(1.0,0.75,0.5,0.25,0.0);default=1.0 },
        [ordered]@{ key='VK_PAGEDOWN';effect='tonemap-a-b';values=@(0.0,1.0);labels=@('none','reinhard');default=0.0 }
    )
    files = @($files)
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$manifestPath = Join-Path $outputRoot 'runtime-manifest.json'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 12)+[Environment]::NewLine, $utf8)

[pscustomobject]@{
    Adapter = [string]$manifest.adapterId
    Status = [string]$manifest.status
    Files = @($files).Count
    Output = $outputRoot
    Manifest = $manifestPath
    IniSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $diagnosticIniPath).Hash
    ShaderSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $diagnosticShaderPath).Hash
}
