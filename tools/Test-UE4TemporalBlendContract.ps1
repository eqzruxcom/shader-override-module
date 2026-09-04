[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$analyzer = Join-Path $repoRoot 'tools\Get-UE4TemporalBlendContract.ps1'
$fixtures = Join-Path $repoRoot 'src\Tests\Fixtures\UE4TemporalBlend'
$output = Join-Path $repoRoot 'artifacts\ue4-temporal-blend-contract-test'

$fixedReport = Join-Path $output 'fixed.json'
$dynamicReport = Join-Path $output 'dynamic.json'
& $analyzer -AssemblyPath (Join-Path $fixtures 'fixed-history-weight-cs.asm') -OutputPath $fixedReport | Out-Null
& $analyzer -AssemblyPath (Join-Path $fixtures 'dynamic-history-weight-cs.asm') -OutputPath $dynamicReport | Out-Null

$fixed = Get-Content -Raw -LiteralPath $fixedReport | ConvertFrom-Json
$dynamic = Get-Content -Raw -LiteralPath $dynamicReport | ConvertFrom-Json

if ($fixed.temporalBlend.status -ne 'fixed') { throw 'Fixed temporal blend was not classified as fixed.' }
if ([Math]::Abs([double]$fixed.temporalBlend.historyWeight - 0.85) -gt 0.000001) { throw 'Fixed history weight was not recovered.' }
if ([Math]::Abs([double]$fixed.temporalBlend.currentWeight - 0.15) -gt 0.000001) { throw 'Fixed current weight was not recovered.' }
if ($fixed.temporalBlend.steadyStateCompensationEligible -ne $true) { throw 'Fixed blend should allow steady-state compensation.' }

if ($dynamic.temporalBlend.status -ne 'dynamic') { throw 'Dynamic temporal blend was not classified as dynamic.' }
if ($dynamic.temporalBlend.steadyStateCompensationEligible -ne $false) { throw 'Dynamic blend must fail closed for steady-state compensation.' }
if (@($dynamic.temporalBlend.dynamicScaleFactors) -notcontains 0.7) { throw 'Dynamic 0.7 scale factor was not recovered.' }
if ($dynamic.temporalBlend.historyWeight -ne $null -or $dynamic.temporalBlend.currentWeight -ne $null) {
    throw 'Dynamic blend incorrectly reported fixed weights.'
}
foreach ($report in @($fixed, $dynamic)) {
    if (-not $report.structuralEvidence.historySample -or -not $report.structuralEvidence.historyDifference -or -not $report.structuralEvidence.temporalBlend -or -not $report.structuralEvidence.volumeStore) {
        throw 'Temporal contract report is missing structural metadata.'
    }
}

Write-Output 'UE4 temporal blend contract tests passed.'
Write-Output "Reports: $output"
