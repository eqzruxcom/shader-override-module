[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ssr-composite-strength-test')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$generator = Join-Path $repoRoot 'tools\New-IntergradeSSRCompositeStrengthVariant.ps1'
$levels = @('0', '0.25', '0.5', '0.75', '1')
$results = foreach ($level in $levels) {
    & $generator -Strength $level -OutputDirectory $OutputDirectory
}

if ($results.Count -ne 5) { throw "Expected five downstream SSR strength variants, got $($results.Count)." }
if (@($results.ObjectSha256 | Select-Object -Unique).Count -ne 5) {
    throw 'Downstream SSR strength variants did not produce five unique objects.'
}

foreach ($result in $results) {
    $manifest = Get-Content -Raw -LiteralPath $result.Manifest | ConvertFrom-Json
    if ([double]$manifest.strength -ne [double]$result.Strength) { throw "Strength mismatch for $($result.Strength)." }
    if ($manifest.shaderHash -ne 'e2aa1c8cb39e0a55') { throw 'Unexpected downstream composite hash.' }
    if ($manifest.runtimeAdapterEligible -ne $false) { throw 'Unvalidated downstream full replacement must remain adapter-ineligible.' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $result.Source).Hash -ne $manifest.sourceSha256) {
        throw "Source hash mismatch for strength $($result.Strength)."
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $result.Object).Hash -ne $manifest.objectSha256) {
        throw "Object hash mismatch for strength $($result.Strength)."
    }
    $source = [IO.File]::ReadAllText($result.Source)
    if ([regex]::Matches($source, 'r11\.w = 1 \+ -r11\.w;').Count -ne 1) {
        throw "SSR alpha inversion was not preserved for strength $($result.Strength)."
    }
    if ([regex]::Matches($source, 'r2\.xyz = r2\.xyz \* r11\.www;').Count -ne 1) {
        throw "Environment fallback weighting was not preserved for strength $($result.Strength)."
    }
}

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    liveNeutralParity = 'pending'
    runtimeAdapterEligible = $false
    variants = @($results | ForEach-Object {
        [ordered]@{
            strength = $_.Strength
            sourceSha256 = $_.SourceSha256
            objectSha256 = $_.ObjectSha256
        }
    })
}
$reportPath = Join-Path $OutputDirectory 'report.json'
[IO.File]::WriteAllText($reportPath, (($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

Write-Output 'Intergrade downstream SSR composite strength tests passed.'
Write-Output "Report: $reportPath"
