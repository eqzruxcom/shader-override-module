[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-ao-shader-test-matrix-test'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$analyzer = Join-Path $repoRoot 'tools\Analyze-IntergradeAOShaderTestMatrix.ps1'
$output = Join-Path $OutputDirectory 'report.json'
& $analyzer -OutputPath $output
$report = Get-Content -Raw -LiteralPath $output | ConvertFrom-Json
if ($report.result -ne 'pass' -or $report.requiredShaderCount -ne 14 -or $report.allRequiredShadersPresent -ne $true) {
    throw 'AO shader test matrix is incomplete.'
}
if (@($report.testGroups.changed).Count -ne 1 -or $report.testGroups.changed[0].hash -ne 'e2aa1c8cb39e0a55') {
    throw 'Changed shader set is not exactly e2aa.'
}
if (@($report.testGroups.nativeAOChainMustRemainUnchanged).Count -ne 5 -or @($report.testGroups.directLightConsumersMustRemainUnchanged).Count -ne 5) {
    throw 'AO chain or direct-light invariant group is incomplete.'
}
if (@($report.testGroups.reflectionAndOcclusionInvariants).Count -ne 2 -or @($report.testGroups.captureRequiredDoNotPatch).Count -ne 1) {
    throw 'Reflection/occlusion or capture-required group is incomplete.'
}
if (@($report.packOverrideHashes).Count -ne 1 -or $report.packOverrideHashes[0] -ne 'e2aa1c8cb39e0a55' -or $report.currentRuntimeF2ClaimCount -ne 0) {
    throw 'F2 pack/runtime scope is invalid.'
}
Write-Output 'Intergrade Agent 2 AO shader test-matrix tests passed.'
Write-Output "Report: $output"
