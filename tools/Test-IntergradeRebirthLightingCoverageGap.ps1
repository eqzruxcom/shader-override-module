[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$first = Join-Path $workspace 'artifacts\analysis\intergrade-rebirth-lighting-coverage-gap.test-a.json'
$second = Join-Path $workspace 'artifacts\analysis\intergrade-rebirth-lighting-coverage-gap.test-b.json'
$analyzer = Join-Path $PSScriptRoot 'Analyze-IntergradeRebirthLightingCoverageGap.ps1'

& $analyzer -OutputPath $first | Out-Host
& $analyzer -OutputPath $second | Out-Host

$aHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $first).Hash
$bHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $second).Hash
if ($aHash -ne $bHash) { throw 'Lighting coverage gap report is not deterministic' }

$report = Get-Content -Raw -LiteralPath $first | ConvertFrom-Json
if ($report.schemaVersion -ne 1) { throw 'Unexpected report schema' }
if ($report.inventory.rebirthDonorFamilyCount -ne 11 -or $report.inventory.rebirthTargetCount -ne 44) { throw 'Rebirth inventory changed' }
if ($report.inventory.remakeVerifiedFamilyCount -ne 10 -or $report.inventory.remakeVerifiedTargetCount -ne 29) { throw 'Remake inventory changed' }
if ($report.inventory.regionalShaderCount -ne 184 -or $report.inventory.regionalCompatibleLocalLightCount -ne 5) { throw 'Regional coverage changed' }
if ($report.inventory.regionalStructuralExceptionCount -ne 0) { throw 'Unexpected regional structural exceptions' }
if ($report.inventory.sampleGIComputeShaderCount -ne 18 -or $report.inventory.sampleGIExactCompatibleCount -ne 0) { throw 'SampleGI regional evidence changed' }
if ($report.inventory.directLightSharedVariantCount -ne 5 -or $report.inventory.directLightLocalAndInfiniteBranchCount -ne 5) { throw 'Shared direct-light topology changed' }
if ($report.inventory.directLightReadModifyWriteVariantCount -ne 3 -or $report.inventory.directLightDirectWriteVariantCount -ne 2) { throw 'Direct-light output permutations changed' }
if ($report.coreLightingMatrix.Count -ne 8) { throw 'Expected eight core/deferred donor-family rows' }
if ($report.excludedDonorFamilies.Count -ne 3) { throw 'Expected three water/ocean exclusions' }

$local = @($report.coreLightingMatrix | Where-Object donorFamily -eq 'LocalLight')
$sampleGi = @($report.coreLightingMatrix | Where-Object donorFamily -eq 'SampleGI')
$reflection = @($report.coreLightingMatrix | Where-Object donorFamily -eq 'ReflectionEnvironment')
if ($local.Count -ne 1 -or $local[0].classification -ne 'verified-shared-tiled-evaluator-five-regional-variants') { throw 'LocalLight classification changed' }
if ($sampleGi.Count -ne 1 -or $sampleGi[0].classification -ne 'no-strict-sample-gi-match-in-current-regional-capture') { throw 'SampleGI gap classification changed' }
if ($reflection.Count -ne 1 -or $reflection[0].remakeEvidence -notcontains 'e2aa1c8cb39e0a55-ps') { throw 'ReflectionEnvironment adapter evidence changed' }
if ($report.acceptedLiveCoverage.materialAwareSSGI.targetShader -ne 'e2aa1c8cb39e0a55') { throw 'SSGI target changed' }

Remove-Item -LiteralPath $first, $second -Force
Write-Host 'PASS: lighting coverage gap report is deterministic and preserves all verified family boundaries.'
