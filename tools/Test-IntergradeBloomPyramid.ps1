[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$analyzer = Join-Path $PSScriptRoot 'Analyze-IntergradeBloomPyramid.ps1'
$a = Join-Path $root 'artifacts\analysis\ff7-remake-intergrade-bloom-pyramid.test-a.json'
$b = Join-Path $root 'artifacts\analysis\ff7-remake-intergrade-bloom-pyramid.test-b.json'
& $analyzer -OutputPath $a | Out-Host
& $analyzer -OutputPath $b | Out-Host
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $a).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $b).Hash) { throw 'Bloom-pyramid report is not deterministic' }
$report = Get-Content -Raw -LiteralPath $a | ConvertFrom-Json
if ($report.detector -ne 'ff7-remake-dxbc-bloom-pyramid-v1') { throw 'Unexpected detector ID' }
if (@($report.sequence.c583DownsampleEvents) -join ',' -ne '1144') { throw 'Expected c583 to be bound at the start of the nine-draw downsample run' }
if (@($report.sequence.c583DownsampleDrawEvents) -join ',' -ne '1144,1145,1146,1147,1148,1149,1150,1151,1152') { throw 'Expected c583 to own the complete nine-draw downsample run' }
if (@($report.sequence.c587PyramidEvents).Count -ne 9) { throw 'Expected nine recorded c587 pyramid-stage shader binds' }
if (@($report.sequence.upsampleCombineEvents).Count -ne 9) { throw 'Expected nine recorded upsample/combine shader binds' }
if (@($report.sequence.bloomCompositeEvents) -join ',' -ne '1173') { throw 'Expected bloom composite at event 1173' }
if (@($report.sequence.finalColorEvents) -join ',' -ne '1174') { throw 'Expected final-color pass at event 1174' }
if ($report.shaderRoles.downsample.texture2DCount -ne 1 -or $report.shaderRoles.downsample.sampleInstructionCount -ne 4) { throw 'c583 one-input four-sample signature changed' }
if ($report.shaderRoles.upsampleCombine.texture2DCount -ne 2) { throw 'Upsample/combine two-input signature changed' }
if ($report.classification.relationshipToIndirectLighting -notmatch 'not an indirect-light producer') { throw 'c583 indirect-light boundary changed' }
Remove-Item -LiteralPath $a,$b -Force
Write-Host 'PASS: c583 is pinned as the bloom-pyramid resample family, not an indirect-light producer.'
