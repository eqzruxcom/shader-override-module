[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$scanner = Join-Path $PSScriptRoot 'Find-IntergradeSampleGIFamilies.ps1'
$a = Join-Path $root 'artifacts\analysis\ff7-remake-intergrade-sample-gi-family-scan.test-a.json'
$b = Join-Path $root 'artifacts\analysis\ff7-remake-intergrade-sample-gi-family-scan.test-b.json'

& $scanner -OutputPath $a | Out-Host
& $scanner -OutputPath $b | Out-Host
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $a).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $b).Hash) { throw 'SampleGI scan is not deterministic' }

$report = Get-Content -Raw -LiteralPath $a | ConvertFrom-Json
if ($report.detector -ne 'ff7-remake-dxbc-sample-gi-binding-v1') { throw 'Unexpected detector ID' }
if ($report.capture.computeShaderCount -ne 18) { throw "Expected 18 captured compute shaders; found $($report.capture.computeShaderCount)" }
if ($report.exactCompatibleCount -ne 0) { throw 'A new exact SampleGI match appeared and requires manual review' }
if ($report.nearMatchCount -lt 1) { throw 'Expected at least one retained structural near-match' }
$b9e = @($report.allCandidates | Where-Object hash -eq 'b9e2305a994308f2')
if ($b9e.Count -ne 1 -or $b9e[0].resourceTotalCount -ne 4 -or $b9e[0].uavTotalCount -ne 2 -or @($b9e[0].threadGroup) -join ',' -ne '8,8,1') { throw 'b9e near-match evidence changed' }
if ($b9e[0].resourceTexture2DCount -ne 2 -or $b9e[0].resourceBufferCount -ne 2 -or $b9e[0].float4TextureUavCount -ne 1 -or $b9e[0].shadingModelDecode) { throw 'b9e disqualifying resource/dataflow evidence changed' }

Remove-Item -LiteralPath $a,$b -Force
Write-Host 'PASS: current regional capture has no strict SampleGI match; near matches remain explicitly disqualified.'
