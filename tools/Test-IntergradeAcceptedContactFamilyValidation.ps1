[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$resolver = Join-Path $PSScriptRoot 'Resolve-IntergradeAcceptedContactFamilyValidation.ps1'
$a = Join-Path $root 'artifacts\analysis\intergrade-accepted-contact-family-validation.test-a.json'
$b = Join-Path $root 'artifacts\analysis\intergrade-accepted-contact-family-validation.test-b.json'

try {
    & $resolver -OutputPath $a | Out-Host
    & $resolver -OutputPath $b | Out-Host
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $a).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $b).Hash) { throw 'Accepted contact-family validation report is not deterministic' }
    $report = Get-Content -Raw -LiteralPath $a | ConvertFrom-Json
    if ($report.detector -ne 'ff7-remake-accepted-contact-family-validation-v1' -or $report.schemaVersion -ne 1) { throw 'Unexpected validation report schema' }
    if (@($report.acceptedShaderSet).Count -ne 5) { throw 'Accepted shader-set count changed' }
    if ($report.engineEquivalentContract.result -ne 'passed' -or -not $report.engineEquivalentContract.exactExpectedSet -or -not $report.engineEquivalentContract.uniqueFamilyMembership) { throw 'Engine-equivalent contract is no longer exact and unique' }
    if ($report.engineEquivalentContract.familyCounts.ShaderRegexUE4FXRemakeContactBaseT5 -ne 3 -or $report.engineEquivalentContract.familyCounts.ShaderRegexUE4FXRemakeContactBaseT4 -ne 1 -or $report.engineEquivalentContract.familyCounts.ShaderRegexUE4FXRemakeContactFrustumT4 -ne 1) { throw 'Expected 3+1+1 family split changed' }
    if ($report.structureOnlyDiagnostic.result -ne 'expected-overlap-detected' -or @($report.structureOnlyDiagnostic.overlaps).Count -ne 2) { throw 'Known T4 structural overlap was not represented exactly' }
    $base = @($report.runtimeGuards | Where-Object family -eq 'ShaderRegexUE4FXRemakeContactBaseT4')
    $frustum = @($report.runtimeGuards | Where-Object family -eq 'ShaderRegexUE4FXRemakeContactFrustumT4')
    if ($base.Count -ne 1 -or $base[0].minimumInstructions -ne 631 -or $base[0].maximumInstructions -ne 631) { throw 'Base-T4 exact guard changed' }
    if ($frustum.Count -ne 1 -or $frustum[0].minimumInstructions -ne 478 -or $frustum[0].maximumInstructions -ne 478) { throw 'Frustum-T4 exact guard changed' }
    if (-not $report.safetyConclusion.accepted -or $report.liveFilesModified) { throw 'Safety conclusion or offline-only invariant changed' }
} finally {
    foreach ($path in @($a,$b)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
}

Write-Host 'PASS: the complete ShaderRegex contract uniquely accepts exactly five shaders (3+1+1); the known T4 structure-only overlap is documented and fail-closed by exact instruction guards.'

