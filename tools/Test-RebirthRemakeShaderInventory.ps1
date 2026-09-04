[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\rebirth-v2.2.1-remake-area-inventory.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$generator = Join-Path $PSScriptRoot 'New-RebirthRemakeShaderInventory.ps1'
& $generator -OutputPath $OutputPath | Out-Host
$firstHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutputPath).Hash
& $generator -OutputPath $OutputPath | Out-Null
$secondHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutputPath).Hash
if ($firstHash -ne $secondHash) { throw 'Inventory generation is not deterministic.' }

$reportText = Get-Content -Raw -LiteralPath $OutputPath
$workspace = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent)).TrimEnd('\')
if ($reportText -match 'generatedAtUtc' -or $reportText.Contains($workspace,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Inventory contains volatile time or absolute workspace metadata.'
}
$report = $reportText | ConvertFrom-Json
if ($report.schemaVersion -ne 1) { throw 'Unexpected report schema.' }
if ($report.donor.packageCount -ne 44) { throw "Expected 44 donor packages, got $($report.donor.packageCount)." }
if ($report.donor.familyCount -ne 11) { throw "Expected 11 donor families, got $($report.donor.familyCount)." }
if ($report.donor.stageFamilyCounts.ps -ne 9) { throw 'Expected 9 donor PS families.' }
if ($report.donor.stageFamilyCounts.cs -ne 2) { throw 'Expected 2 donor CS families.' }
if ($report.donor.stageFamilyCounts.PSObject.Properties['vs']) { throw 'Donor unexpectedly contains a VS family.' }
if ($report.donor.versionGroups.Count -ne 4) { throw 'Expected four donor version groups.' }
if ($report.capture.shaderCount -ne 184) { throw "Expected 184 captured shaders, got $($report.capture.shaderCount)." }
if ($report.capture.stageShaderCounts.ps -ne 95) { throw 'Expected 95 captured PS shaders.' }
if ($report.capture.stageShaderCounts.vs -ne 70) { throw 'Expected 70 captured VS shaders.' }
if ($report.capture.stageShaderCounts.cs -ne 18) { throw 'Expected 18 captured CS shaders.' }
if ($report.capture.stageShaderCounts.gs -ne 1) { throw 'Expected one captured GS shader.' }
if ($report.capture.originalDisassemblerHeaderCount -ne 184) { throw 'Expected all 184 original disassembler headers.' }
if ($report.capture.semanticMatchCount -ne 8) { throw 'Expected eight verified semantic matches.' }

$requiredFamilies = @(
    'DirectionalLight','LocalLight','LocalLightIES','OceanA','PostProcessFinal',
    'PostProcessFog','ReflectionEnvironment','SampleGI','SSR','WaterA','WaterB'
)
$actualFamilies = @($report.donor.families.family | Sort-Object)
if ((Compare-Object ($requiredFamilies | Sort-Object) $actualFamilies)) {
    throw "Donor family inventory does not match the expected v2.2.1 package."
}

$requiredMatches = @(
    'af6cd28a0108a18a-ps','eda405f2d455d5c7-ps','e2aa1c8cb39e0a55-ps',
    'b2bc6059f9a39c7f-ps','a77b589dce5822d6-ps','c25d7f5229662b97-ps',
    'cbc771ff8a37a0b3-ps','ef7fe8d9c4e9ad15-cs'
)
$actualMatches = @($report.capture.semanticMatches | ForEach-Object { "$($_.hash)-$($_.stage)" } | Sort-Object)
if ((Compare-Object ($requiredMatches | Sort-Object) $actualMatches)) {
    throw 'Verified semantic-match inventory changed unexpectedly.'
}

Write-Host 'PASS: donor and Remake capture inventory is complete and internally consistent.'
