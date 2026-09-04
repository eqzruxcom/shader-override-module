[CmdletBinding()]
param(
    [string]$ControlPackPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\replacement-shaders\af6cd28a0108a18a-scene-saturation-control-pack.json'),
    [string]$ShaderMapPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Adapters\FF7RemakeIntergrade\shader-map.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')

function Resolve-ProjectFile([string]$RelativePath) {
    $full = [IO.Path]::GetFullPath((Join-Path $repoRoot ($RelativePath -replace '/', '\')))
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Referenced path escapes the project: $RelativePath"
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "Referenced file is missing: $RelativePath"
    }
    $full
}

function Assert-Hash([string]$Path, [string]$Expected, [string]$Context) {
    if ($Expected -notmatch '^[0-9A-Fa-f]{64}$') { throw "$Context has an invalid SHA-256 value." }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
    if ($actual -ne $Expected) { throw "$Context hash mismatch: expected $Expected, got $actual." }
}

$controlPackFull = (Resolve-Path -LiteralPath $ControlPackPath).Path
$shaderMapFull = (Resolve-Path -LiteralPath $ShaderMapPath).Path
$pack = Get-Content -Raw -LiteralPath $controlPackFull | ConvertFrom-Json
$map = Get-Content -Raw -LiteralPath $shaderMapFull | ConvertFrom-Json

if ($pack.schemaVersion -ne 1 -or $pack.shaderHash -ne 'af6cd28a0108a18a' -or $pack.stage -ne 'ps') {
    throw 'Control-pack identity is invalid.'
}
$expectedLevels = @(0.0, 0.25, 0.5, 0.75, 1.0)
$levels = @($pack.levels)
if ($levels.Count -ne $expectedLevels.Count) { throw "Expected five saturation levels, found $($levels.Count)." }

for ($index = 0; $index -lt $levels.Count; $index++) {
    $level = $levels[$index]
    if ([Math]::Abs([double]$level.saturation - $expectedLevels[$index]) -gt 0.000001) {
        throw "Unexpected saturation at level $index."
    }
    if ([double]$level.saturation -eq 1.0) {
        foreach ($property in @('source','sourceSha256','object','objectSha256')) {
            if ($null -ne $level.$property) { throw "Original level must not provide $property." }
        }
        if ($level.verification -ne 'game-original') { throw 'Original level has invalid verification status.' }
        continue
    }

    $source = Resolve-ProjectFile $level.source
    $object = Resolve-ProjectFile $level.object
    Assert-Hash $source $level.sourceSha256 "Saturation $($level.saturation) source"
    Assert-Hash $object $level.objectSha256 "Saturation $($level.saturation) object"

    $manifestPath = [IO.Path]::ChangeExtension($source, '.json')
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Variant manifest is missing: $manifestPath" }
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    if ([Math]::Abs([double]$manifest.saturation - [double]$level.saturation) -gt 0.000001) {
        throw "Variant manifest saturation mismatch for $($level.saturation)."
    }
    if ($manifest.sourceSha256 -ne $level.sourceSha256 -or $manifest.objectSha256 -ne $level.objectSha256) {
        throw "Variant manifest hash mismatch for $($level.saturation)."
    }
}

$generatorReport = Get-Content -Raw -LiteralPath (Resolve-ProjectFile $pack.testReport) | ConvertFrom-Json
if ($generatorReport.result -ne 'pass' -or @($generatorReport.levels).Count -ne 4) {
    throw 'Saturation generator report is not a passing four-level matrix.'
}

$pass = @($map.passes | Where-Object id -eq 'post_process_final')
if ($pass.Count -ne 1) { throw "Expected one post_process_final shader-map pass, found $($pass.Count)." }
$relativePack = $controlPackFull.Substring($repoRoot.Length + 1).Replace('\','/')
if ($pass[0].controlIntegration.controlPack -ne $relativePack) {
    throw 'Shader-map control-pack reference is stale.'
}
if (@($pass[0].controlIntegration.levels).Count -ne 5) {
    throw 'Shader-map saturation level count is stale.'
}

Write-Output 'Intergrade scene-saturation control-pack validation passed.'
[pscustomobject]@{
    ControlPackSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $controlPackFull).Hash
    ShaderMapSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $shaderMapFull).Hash
    Levels = $levels.Count
    Result = 'pass'
}
