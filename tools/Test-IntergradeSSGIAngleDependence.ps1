[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$resolver = Join-Path $PSScriptRoot 'Resolve-IntergradeSSGIAngleDependence.ps1'
$a = Join-Path $root 'artifacts\analysis\intergrade-ssgi-angle-dependence.test-a.json'
$b = Join-Path $root 'artifacts\analysis\intergrade-ssgi-angle-dependence.test-b.json'

try {
    & $resolver -OutputPath $a | Out-Host
    & $resolver -OutputPath $b | Out-Host
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $a).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $b).Hash) { throw 'Angle-dependence report is not deterministic' }
    $report = Get-Content -Raw -LiteralPath $a | ConvertFrom-Json
    if ($report.detector -ne 'ff7-remake-ssgi-angle-dependence-v1') { throw 'Unexpected detector ID' }
    if (@($report.verifiedContract.PSObject.Properties | Where-Object { $_.Value -ne $true }).Count -ne 0) { throw 'A verified trace/temporal contract is false' }
    if (@($report.failureModes).Count -ne 2) { throw 'Expected two distinct angle-dependence modes' }
    if ((@($report.failureModes.id) -join ',') -ne 'visible-small-source-sampling-phase,offscreen-or-occluded-source-loss') { throw 'Failure-mode identities changed' }
    if ($report.safetyPolicy.installed -ne $false -or $report.safetyPolicy.liveFilesModified -ne $false) { throw 'Offline safety contract regressed' }
    if ($report.safetyPolicy.keys -notmatch '^F10 reload only') { throw 'Key contract regressed' }
} finally {
    foreach ($path in @($a,$b)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
}

Write-Host 'PASS: visible-source sampling misses and off-screen source loss remain separate, fail-closed SSGI limitations.'
