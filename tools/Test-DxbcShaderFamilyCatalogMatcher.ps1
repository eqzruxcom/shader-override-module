[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = Split-Path $PSScriptRoot -Parent
$catalogPath = Join-Path $workspace 'artifacts\analysis\ue4-dxbc-semantic-family-catalog.json'
$fixtureDirectory = Join-Path $workspace 'src\Tests\Fixtures\UE4Semantic'
$outputPath = Join-Path $workspace 'artifacts\ue4-semantic-catalog-matcher-test\report.json'

& (Join-Path $PSScriptRoot 'Test-UE4SemanticShaderFamilyCatalog.ps1')
& (Join-Path $PSScriptRoot 'Match-DxbcShaderFamilyCatalog.ps1') -ShaderDirectory $fixtureDirectory -CatalogPath $catalogPath -OutputPath $outputPath

$report = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json
if ($report.schemaVersion -ne 1 -or $report.matcher -ne 'portable-family-catalog-dxbc-semantic') { throw 'Catalog matcher envelope regression' }
if ($report.catalog.id -ne 'ue4-dxbc-semantic-descriptors-v1' -or $report.catalog.semanticImplementationCount -ne 6) { throw 'Catalog matcher identity regression' }
if ($report.catalog.sha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $catalogPath).Hash.ToUpperInvariant()) { throw 'Catalog matcher did not pin its input hash' }
if ($report.matches.Count -ne 8 -or $report.matchTimeouts.Count -ne 0) { throw 'Catalog semantic match-count or timeout regression' }

$expectedReport = Get-Content -Raw -LiteralPath (Join-Path $workspace 'artifacts\ue4-semantic-matcher-test\report.json') | ConvertFrom-Json
$expectedKeys = @($expectedReport.matches | ForEach-Object { "$($_.descriptor)|$($_.stage)|$($_.hash)" } | Sort-Object)
$actualKeys = @($report.matches | ForEach-Object { "$($_.descriptor)|$($_.stage)|$($_.hash)" } | Sort-Object)
if (@(Compare-Object $expectedKeys $actualKeys).Count -ne 0) { throw 'Catalog consumer does not preserve hardened matcher results' }

$remakeCatalog = Join-Path $workspace 'artifacts\analysis\ff7-remake-intergrade-verified-family-catalog.json'
& (Join-Path $PSScriptRoot 'Test-RemakeShaderFamilyCatalog.ps1')
$exactOnlyRejected=$false
try { & (Join-Path $PSScriptRoot 'Match-DxbcShaderFamilyCatalog.ps1') -ShaderDirectory $fixtureDirectory -CatalogPath $remakeCatalog -OutputPath (Join-Path $workspace 'artifacts\ue4-semantic-catalog-matcher-test\exact-only-negative.json') | Out-Null }
catch { $exactOnlyRejected=$_.Exception.Message -like 'Catalog contains no ue4-dxbc-regex-semantic-v1*' }
if (-not $exactOnlyRejected) { throw 'Exact-only catalog was not rejected by the structural matcher' }

Write-Host 'PASS: portable catalog drives the hardened DXBC semantic matcher with identical results and rejects exact-only catalogs.'
