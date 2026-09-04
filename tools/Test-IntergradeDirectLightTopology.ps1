[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$scanner = Join-Path $PSScriptRoot 'Analyze-IntergradeDirectLightTopology.ps1'
$radialScanner = Join-Path $PSScriptRoot 'Find-IntergradeLocalLightRadialFamilies.ps1'
$assembly = Join-Path $root 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\assembly'
$radial = Join-Path $root 'artifacts\analysis\intergrade-local-light-radial-family-scan.json'
$a = Join-Path $root 'artifacts\analysis\ff7-remake-intergrade-direct-light-topology.test-a.json'
$b = Join-Path $root 'artifacts\analysis\ff7-remake-intergrade-direct-light-topology.test-b.json'
$expected = @('08bb8764f1840179','0e97888f9a8767da','5a9fbefe0ab6f815','62b33a2d1e505241','c30cdc8365df9840')

& $radialScanner -AssemblyDirectory $assembly -OutputPath $radial -ExpectedHashes $expected -RequireAtLeastOne | Out-Host
& $scanner -OutputPath $a | Out-Host
& $scanner -OutputPath $b | Out-Host
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $a).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $b).Hash) { throw 'Direct-light topology report is not deterministic' }

$report = Get-Content -Raw -LiteralPath $a | ConvertFrom-Json
if ($report.detector -ne 'ff7-remake-dxbc-direct-light-topology-v1') { throw 'Unexpected detector ID' }
if ($report.remakeCapture.verifiedSharedTiledLightVariantCount -ne 5) { throw 'Expected five shared tiled-light variants' }
if ($report.remakeCapture.localAndInfiniteBranchVariantCount -ne 5) { throw 'Expected every variant to contain both local and infinite/non-radial attenuation paths' }
if ($report.remakeCapture.readModifyWriteVariantCount -ne 3) { throw 'Expected three prior-lighting read/modify/write variants' }
if ($report.remakeCapture.directWriteVariantCount -ne 2) { throw 'Expected two direct-write variants' }
if ($report.remakeCapture.ambiguousCompositionVariantCount -ne 0) { throw 'An output-composition permutation became ambiguous' }
if (@($report.remakeCapture.variants | Where-Object dedicatedIesProfileTextureProven).Count -ne 0) { throw 'IES was labeled proven without dedicated profile evidence' }
if ($report.classification.directionalLight -notmatch 'not separately proven') { throw 'Directional-light policy no longer fails closed' }
if ($report.classification.localLightIES -notmatch 'not separately proven') { throw 'IES policy no longer fails closed' }

Remove-Item -LiteralPath $a,$b -Force
Write-Host 'PASS: shared Remake tiled-light topology is separated from Rebirth directional/local/IES donor filenames without overclaiming branch ownership.'
