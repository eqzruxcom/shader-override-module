[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$resolver = Join-Path $PSScriptRoot 'Resolve-IntergradeDirectionalLightCoverage.ps1'
$a = Join-Path $root 'artifacts\analysis\intergrade-directional-light-coverage.test-a.json'
$b = Join-Path $root 'artifacts\analysis\intergrade-directional-light-coverage.test-b.json'

try {
    & $resolver -OutputPath $a | Out-Host
    & $resolver -OutputPath $b | Out-Host
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $a).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $b).Hash) {
        throw 'Directional-light coverage report is not deterministic'
    }
    $report = Get-Content -Raw -LiteralPath $a | ConvertFrom-Json
    if ($report.detector -ne 'ff7-remake-directional-light-coverage-boundary-v1') { throw 'Unexpected detector ID' }
    if ($report.verifiedCascadeShadowProjection.hash -ne 'aadc1c2374853914') { throw 'Verified cascade hash changed' }
    if ($report.verifiedCascadeShadowProjection.semanticChecksPassed -ne 10) { throw 'Cascade semantic evidence count changed' }
    if ($report.verifiedCascadeShadowProjection.directionalLightEvaluator -ne $false) { throw 'Cascade producer was mislabeled as directional evaluator' }
    if ($report.rejectedCascadeNearMatches.count -ne 5) { throw 'Cascade near-match rejection count changed' }
    if (@($report.rejectedCascadeNearMatches.records | Where-Object { $_.failedChecks.Count -lt 1 }).Count -ne 0) { throw 'A rejected near match has no failed check' }
    if (@($report.acceptedFiveShaderLightingFamily.hashes).Count -ne 5) { throw 'Five-shader lighting family changed' }
    if ($report.acceptedFiveShaderLightingFamily.directionalOwnership -ne 'not proven') { throw 'Directional ownership was overclaimed' }
    if ($report.coverageBoundary.directionalSurfaceLightingEvaluator -ne 'unresolved') { throw 'Directional evaluator was promoted without runtime evidence' }
    if ($report.safetyPolicy.liveInstall -ne 'deferred while the user sleeps') { throw 'Overnight live-install gate regressed' }
    if ($report.safetyPolicy.keys -notmatch '^F10 remains shader reload') { throw 'Key contract regressed' }
} finally {
    foreach ($path in @($a,$b)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
}

Write-Host 'PASS: cascade shadow production is verified while directional surface-light ownership remains fail-closed.'
