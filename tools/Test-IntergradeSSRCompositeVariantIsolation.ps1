[CmdletBinding()]
param(
    [string]$VariantDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ssr-composite-strength-variants'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ssr-composite-strength-variant-isolation.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$levels = @(
    @{ Label = '000'; Literal = '0.0'; Strength = 0.0 },
    @{ Label = '025'; Literal = '0.25'; Strength = 0.25 },
    @{ Label = '050'; Literal = '0.5'; Strength = 0.5 },
    @{ Label = '075'; Literal = '0.75'; Strength = 0.75 },
    @{ Label = '100'; Literal = '1.0'; Strength = 1.0 }
)
$normalized = [Collections.Generic.List[string]]::new()
$records = [Collections.Generic.List[object]]::new()
$assemblyMarker = '/*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~'
$declarationPattern = 'float ssrCompositeStrength = (?<literal>0\.0|0\.25|0\.5|0\.75|1\.0);'
$controlledEquation = 'r2.xyz = r2.xyz * r0.www + r11.xyz * ssrCompositeStrength;'
$hitMaskEquation = 'r11.w = 1 + -r11.w;'

foreach ($level in $levels) {
    $path = Join-Path $VariantDirectory "RebirthSSRCompositeStrength$($level.Label)_ps.hlsl"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing SSR composite variant: $path" }
    $text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $path))
    $source = $text.Split($assemblyMarker, 2, [StringSplitOptions]::None)[0]
    $declarations = [regex]::Matches($source, $declarationPattern)
    if ($declarations.Count -ne 1) { throw "Expected one strength declaration in $path, found $($declarations.Count)." }
    if ($declarations[0].Groups['literal'].Value -ne $level.Literal) { throw "Unexpected strength literal in $path." }
    if (($source.Split($controlledEquation).Count - 1) -ne 1) { throw "Controlled SSR equation is not unique in $path." }
    if (($source.Split($hitMaskEquation).Count - 1) -ne 1) { throw "SSR hit-mask inversion path is not preserved exactly once in $path." }
    $normalizedSource = [regex]::Replace($source, $declarationPattern, 'float ssrCompositeStrength = STRENGTH;')
    $normalized.Add($normalizedSource)
    $bytes = [Text.Encoding]::UTF8.GetBytes($normalizedSource)
    $normalizedHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    $records.Add([ordered]@{
        strength = $level.Strength
        source = [IO.Path]::GetRelativePath((Split-Path -Parent $PSScriptRoot), (Resolve-Path -LiteralPath $path)).Replace('\','/')
        sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
        normalizedSourceSha256 = $normalizedHash
    })
}

$uniqueNormalizedBodies = @($normalized | Select-Object -Unique)
if ($uniqueNormalizedBodies.Count -ne 1) { throw "SSR composite variants differ outside the strength literal: $($uniqueNormalizedBodies.Count) normalized bodies." }

$report = [ordered]@{
    schemaVersion = 1
    shaderHash = 'e2aa1c8cb39e0a55'
    stage = 'ps'
    invariant = 'All five source bodies are identical after normalizing the single ssrCompositeStrength literal.'
    controlledEquation = $controlledEquation
    preservedHitMaskEquation = $hitMaskEquation
    uniqueNormalizedBodies = $uniqueNormalizedBodies.Count
    levels = @($records)
    result = 'pass'
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
[IO.File]::WriteAllText($OutputPath, (($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

Write-Output 'Intergrade SSR composite variant-isolation validation passed.'
[pscustomobject]@{
    Levels = $records.Count
    UniqueNormalizedBodies = $uniqueNormalizedBodies.Count
    Report = $OutputPath
    Result = 'pass'
}
