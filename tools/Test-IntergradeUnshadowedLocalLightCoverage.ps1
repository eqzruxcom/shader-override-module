[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$resolver = Join-Path $PSScriptRoot 'Resolve-IntergradeUnshadowedLocalLightCoverage.ps1'
$a = Join-Path $root 'artifacts\analysis\intergrade-unshadowed-local-light-coverage.test-a.json'
$b = Join-Path $root 'artifacts\analysis\intergrade-unshadowed-local-light-coverage.test-b.json'

try {
    & $resolver -OutputPath $a | Out-Host
    & $resolver -OutputPath $b | Out-Host
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $a).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $b).Hash) { throw 'Unshadowed-light coverage report is not deterministic' }
    $report = Get-Content -Raw -LiteralPath $a | ConvertFrom-Json
    if ($report.detector -ne 'ff7-remake-unshadowed-local-light-coverage-v1') { throw 'Unexpected detector ID' }
    if ($report.shader.hash -ne 'adb544f9a11d6c7e') { throw 'Candidate hash changed' }
    if (@($report.structuralChecks.PSObject.Properties | Where-Object { $_.Value -ne $true }).Count -ne 0) { throw 'A structural check is false' }
    if ($report.retainedCensusCohort.count -ne 1) { throw 'Structural cohort is no longer unique' }
    if ($report.classification.confidence -notmatch 'runtime ownership pending') { throw 'Runtime uncertainty was lost' }
    if ($report.runtimeBoundary.capturedScenePresent -ne $false -or $report.runtimeBoundary.automaticPatchEligible -ne $false) { throw 'Uncaptured shader was promoted' }
    if ($report.safetyPolicy.liveInstall -ne 'deferred while the user sleeps') { throw 'Overnight live-install gate regressed' }
    if ($report.safetyPolicy.keys -notmatch '^F10 reload only') { throw 'Key contract regressed' }
} finally {
    foreach ($path in @($a,$b)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
}

Write-Host 'PASS: adb544 is a unique high-confidence unshadowed tiled local-light candidate, but remains runtime-unowned and unpatched.'
