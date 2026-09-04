[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$analyzer = Join-Path $PSScriptRoot 'Analyze-IntergradeContactSoftwareGateProvenance.ps1'
$a = Join-Path $root 'artifacts\analysis\intergrade-contact-software-gate-provenance.test-a.json'
$b = Join-Path $root 'artifacts\analysis\intergrade-contact-software-gate-provenance.test-b.json'

try {
    & $analyzer -OutputPath $a | Out-Host
    & $analyzer -OutputPath $b | Out-Host
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $a).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $b).Hash) { throw 'Software-gate provenance report is not deterministic' }
    $report = Get-Content -Raw -LiteralPath $a | ConvertFrom-Json
    if ($report.detector -ne 'ff7-remake-contact-software-gate-provenance-v1' -or $report.schemaVersion -ne 1) { throw 'Unexpected provenance report schema' }
    if ($report.currentGateStatus -ne 'correctly-rejected-stale-source-provenance' -or $report.currentMismatchCount -lt 1) { throw 'Current source drift was not fail-closed' }
    if (-not $report.pinnedHistoricalContactSource.matchesBothHistoricalManifests) { throw 'Historical contact source is not pinned' }
    if (@($report.sourceChecks | Where-Object { $_.path -eq 'src/Effects/Lighting/ContactShadows.hlsl' -and $_.currentMatchesEvidence }).Count -ne 0) { throw 'Current ContactShadows source unexpectedly matches old evidence' }
    if ($report.liveFilesModified) { throw 'Offline provenance audit claims live modification' }
} finally {
    foreach ($path in @($a,$b)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
}

Write-Host 'PASS: the historical software gate remains pinned to its exact source, while later source drift is rejected and cannot inherit the old evidence.'

