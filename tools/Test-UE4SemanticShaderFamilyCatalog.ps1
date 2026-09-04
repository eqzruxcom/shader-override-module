[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = Split-Path $PSScriptRoot -Parent
$catalogPath = Join-Path $workspace 'artifacts\analysis\ue4-dxbc-semantic-family-catalog.json'
$descriptorDirectory = Join-Path $workspace 'src\Engine\UE4\PassDescriptors'

& (Join-Path $PSScriptRoot 'Test-UE4SemanticMatcher.ps1')
& (Join-Path $PSScriptRoot 'Export-UE4SemanticShaderFamilyCatalog.ps1') -OutputPath $catalogPath
& (Join-Path $PSScriptRoot 'Assert-ShaderFamilyCatalog.ps1') -CatalogPath $catalogPath

$catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
$descriptorFiles = @(Get-ChildItem -LiteralPath $descriptorDirectory -File -Filter '*.json' | Where-Object { $_.Name -ne 'schema.json' })
if ($catalog.families.Count -ne 12 -or $catalog.families.Count -ne $descriptorFiles.Count) { throw 'Semantic family-count regression' }
$targets = @($catalog.families.implementations.variants.targets)
if ($targets.Count -ne 36) { throw 'Semantic exact-fast-path count regression' }
foreach ($implementation in @($catalog.families.implementations)) {
    if ($implementation.api -ne 'D3D11' -or $implementation.bytecodeFormat -ne 'DXBC') { throw 'Semantic backend boundary regression' }
    if ($implementation.identityModel -ne 'ue4-dxbc-regex-semantic-v1') { throw 'Semantic identity-model regression' }
    if ($implementation.variants.Count -ne 1 -or $implementation.variants[0].identity.checks.Count -lt 1) { throw 'Semantic check preservation regression' }
}

$resolver = Join-Path $PSScriptRoot 'Resolve-ShaderFamilyCatalogTarget.ps1'
$ao = & $resolver -CatalogPath $catalogPath -Stage ps -ShaderHash a77b589dce5822d6
if ($ao.familyId -ne 'ue4-temporal-ssao-horizon-ps-sm5' -or $ao.identityModel -ne 'ue4-dxbc-regex-semantic-v1') { throw 'Semantic AO fast-path resolution regression' }
$fogA = & $resolver -CatalogPath $catalogPath -Stage ps -ShaderHash c25d7f5229662b97
$fogB = & $resolver -CatalogPath $catalogPath -Stage ps -ShaderHash cbc771ff8a37a0b3
if ($fogA.familyId -ne 'ue4-volumetric-fog-grid-injection-ps-sm5' -or $fogB.familyId -ne $fogA.familyId) { throw 'Two-hash semantic fog-family regression' }
$cascade = & $resolver -CatalogPath $catalogPath -Stage ps -ShaderHash aadc1c2374853914
if ($cascade.familyId -ne 'ue4-directional-cascade-shadow-projection-filter-ps-sm5') { throw 'Directional cascade projection fast-path regression' }
$skinnedCaster = & $resolver -CatalogPath $catalogPath -Stage vs -ShaderHash 40b611d369bc7b68
$staticCaster = & $resolver -CatalogPath $catalogPath -Stage vs -ShaderHash 49b1908cb47c0d29
if ($skinnedCaster.familyId -ne 'ue4-shadow-depth-caster-skinned-vs-sm5' -or $staticCaster.familyId -ne 'ue4-shadow-depth-caster-static-vs-sm5') { throw 'Shadow-depth caster family fast-path regression' }
$sampledWriter = & $resolver -CatalogPath $catalogPath -Stage ps -ShaderHash 07a10abbef52a0f2
$directWriter = & $resolver -CatalogPath $catalogPath -Stage ps -ShaderHash 50218fe92282b9b2
if ($sampledWriter.familyId -ne 'ue4-shadow-depth-writer-sampled-material-ps-sm5' -or $directWriter.familyId -ne 'ue4-shadow-depth-writer-direct-ps-sm5') { throw 'Shadow-depth writer family fast-path regression' }
$expandedSkinnedCaster = & $resolver -CatalogPath $catalogPath -Stage vs -ShaderHash 9b662afec48956ab
$expandedDirectWriter = & $resolver -CatalogPath $catalogPath -Stage ps -ShaderHash 33153ff4a6cd3b14
if ($expandedSkinnedCaster.familyId -ne 'ue4-shadow-depth-caster-skinned-vs-sm5' -or $expandedDirectWriter.familyId -ne 'ue4-shadow-depth-writer-direct-ps-sm5') { throw 'Expanded-census shadow-depth fast-path regression' }

Write-Host 'PASS: semantic catalog preserves twelve bounded structural rules, 36 exact fast paths, runtime contracts, and resolver behavior.'
