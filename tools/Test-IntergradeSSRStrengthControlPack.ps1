[CmdletBinding()]
param(
    [string]$ControlPackPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\replacement-shaders\b2bc6059f9a39c7f-ssr-strength-control-pack.json'),
    [string]$ShaderMapPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Adapters\FF7RemakeIntergrade\shader-map.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')

function Resolve-ProjectFile([string]$RelativePath) {
    $full = [IO.Path]::GetFullPath((Join-Path $repoRoot ($RelativePath -replace '/', '\')))
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Referenced path escapes the project: $RelativePath" }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Referenced file is missing: $RelativePath" }
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

if ($pack.schemaVersion -ne 1 -or $pack.shaderHash -ne 'b2bc6059f9a39c7f' -or $pack.stage -ne 'ps' -or $pack.effect -ne 'screen-space-reflection-strength') {
    throw 'SSR control-pack identity is invalid.'
}
if (($pack.controlledChannels -join ',') -ne 'x,y,z' -or ($pack.preservedChannels -join ',') -ne 'w') {
    throw 'SSR control-pack packed-channel safety contract is invalid.'
}
if ($pack.formula -ne 'rgb = original.rgb * strength; a = original.a') { throw 'SSR control formula is stale.' }

$expectedLevels = @(0.0, 0.25, 0.5, 0.75, 1.0)
$levels = @($pack.levels)
if ($levels.Count -ne $expectedLevels.Count) { throw "Expected five SSR levels, found $($levels.Count)." }
for ($index = 0; $index -lt $levels.Count; $index++) {
    $level = $levels[$index]
    if ([Math]::Abs([double]$level.strength - $expectedLevels[$index]) -gt 0.000001) { throw "Unexpected SSR strength at level $index." }
    if ([double]$level.strength -eq 1.0) {
        foreach ($property in @('source','sourceSha256','object','objectSha256')) {
            if ($null -ne $level.$property) { throw "Original level must not provide $property." }
        }
        if ($level.verification -ne 'game-original') { throw 'Original SSR level has invalid verification status.' }
        continue
    }
    $source = Resolve-ProjectFile $level.source
    $object = Resolve-ProjectFile $level.object
    Assert-Hash $source $level.sourceSha256 "SSR $($level.strength) source"
    Assert-Hash $object $level.objectSha256 "SSR $($level.strength) object"
    $manifestPath = [IO.Path]::ChangeExtension($source, '.json')
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    if ([Math]::Abs([double]$manifest.strength - [double]$level.strength) -gt 0.000001) { throw "Variant manifest strength mismatch for $($level.strength)." }
    if ($manifest.sourceSha256 -ne $level.sourceSha256 -or $manifest.objectSha256 -ne $level.objectSha256) { throw "Variant manifest hash mismatch for $($level.strength)." }
    if (($manifest.preservedChannels -join ',') -ne 'w') { throw "Variant does not preserve alpha at $($level.strength)." }
}

$generatorReport = Get-Content -Raw -LiteralPath (Resolve-ProjectFile $pack.testReport) | ConvertFrom-Json
if ($generatorReport.result -ne 'pass' -or @($generatorReport.variants).Count -ne 4) { throw 'SSR generator report is not a passing four-level matrix.' }
$pass = @($map.passes | Where-Object id -eq 'screen_space_reflections')
if ($pass.Count -ne 1) { throw "Expected one screen_space_reflections shader-map pass, found $($pass.Count)." }
if ($pass[0].hashes -notcontains $pack.shaderHash) { throw 'Shader-map SSR hash reference is stale.' }
$descriptor = Get-Content -Raw -LiteralPath (Resolve-ProjectFile 'src/Engine/UE4/PassDescriptors/screen-space-reflection-trace-resolve-ps-sm5.json') | ConvertFrom-Json
if ($descriptor.hashFastPaths.hash -notcontains $pack.shaderHash) { throw 'Semantic descriptor SSR fast path is stale.' }

Write-Output 'Intergrade SSR strength control-pack validation passed.'
[pscustomobject]@{
    ControlPackSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $controlPackFull).Hash
    ShaderMapSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $shaderMapFull).Hash
    Levels = $levels.Count
    RuntimeAdapterEligible = [bool]$pack.runtimeAdapterEligible
    Result = 'pass'
}
