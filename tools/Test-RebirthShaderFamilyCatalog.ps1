[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = Split-Path $PSScriptRoot -Parent
$auditTest = Join-Path $PSScriptRoot 'Test-RebirthShaderInjectorPresetAudit.ps1'
$exporter = Join-Path $PSScriptRoot 'Export-RebirthShaderFamilyCatalog.ps1'
$catalogPath = Join-Path $workspace 'artifacts\analysis\rebirth-shader-injector-v2.2.1-family-catalog.json'
$schemaPath = Join-Path $workspace 'src\Engine\ShaderFamilies\schema.json'

& $auditTest
& $exporter -OutputPath $catalogPath
& (Join-Path $PSScriptRoot 'Assert-ShaderFamilyCatalog.ps1') -CatalogPath $catalogPath

$schema = Get-Content -Raw -LiteralPath $schemaPath | ConvertFrom-Json
$catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
if ($schema.title -ne 'Portable shader-family catalog') { throw 'Family catalog schema is missing or unexpected' }
if ($catalog.schemaVersion -ne 1 -or $catalog.kind -ne 'shader-family-catalog') { throw 'Catalog envelope regression' }
if ($catalog.families.Count -ne 11) { throw 'Expected 11 logical families' }

$familyIds = @($catalog.families.id)
if (@($familyIds | Sort-Object -Unique).Count -ne 11) { throw 'Family IDs must be unique' }
$implementationIds = @($catalog.families.implementations.id)
if (@($implementationIds | Sort-Object -Unique).Count -ne 11) { throw 'Implementation IDs must be unique' }

$allTargets = @($catalog.families.implementations.variants.targets)
if ($allTargets.Count -ne 44) { throw "Expected 44 preserved targets; found $($allTargets.Count)" }
$targetKeys = @($catalog.families | ForEach-Object {
    $family = $_
    @($family.implementations | ForEach-Object {
        $implementation = $_
        @($implementation.variants | ForEach-Object {
            @($_.targets | ForEach-Object { "$($implementation.stage)|$($_.shaderHash)" })
        })
    })
})
if (@($targetKeys | Sort-Object -Unique).Count -ne 44) { throw 'Stage/hash target identities must be unique' }

$pixelFamilies = @($catalog.families | Where-Object { $_.implementations[0].stage -eq 'ps' })
$computeFamilies = @($catalog.families | Where-Object { $_.implementations[0].stage -eq 'cs' })
if ($pixelFamilies.Count -ne 9 -or $computeFamilies.Count -ne 2) { throw 'Expected 9 PS and 2 CS logical families' }

foreach ($name in @('DirectionalLight', 'LocalLight', 'LocalLightIES', 'SampleGI')) {
    $family = @($catalog.families | Where-Object { $_.logicalName -eq $name })
    if ($family.Count -ne 1 -or $family[0].implementations[0].variants.Count -ne 1 -or $family[0].implementations[0].variants[0].targets.Count -ne 4) {
        throw "Stable-family grouping regression: $name"
    }
}
$water = @($catalog.families | Where-Object { $_.logicalName -eq 'WaterA' })
if ($water.Count -ne 1 -or $water[0].implementations[0].variants.Count -le 1) { throw 'Expected WaterA to retain multiple verified identity variants' }

foreach ($implementation in @($catalog.families.implementations)) {
    if ($implementation.api -ne 'D3D12' -or $implementation.bytecodeFormat -ne 'DXIL') { throw 'Donor backend boundary regression' }
    if ($implementation.identityModel -ne 'shader-injector-dxil-analysis-v1') { throw 'Donor identity-model regression' }
}

Write-Host 'PASS: portable family catalog preserves all Rebirth targets, backend boundaries, and legitimate cross-version variants.'
