[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = Split-Path $PSScriptRoot -Parent
$classificationPath = Join-Path $workspace 'src\Adapters\FF7RemakeIntergrade\verified-shader-classifications.json'
$catalogPath = Join-Path $workspace 'artifacts\analysis\ff7-remake-intergrade-verified-family-catalog.json'

& (Join-Path $PSScriptRoot 'Test-RemakeVerifiedShaderClassifications.ps1')
& (Join-Path $PSScriptRoot 'Export-RemakeShaderFamilyCatalog.ps1') -OutputPath $catalogPath
& (Join-Path $PSScriptRoot 'Assert-ShaderFamilyCatalog.ps1') -CatalogPath $catalogPath

$source = Get-Content -Raw -LiteralPath $classificationPath | ConvertFrom-Json
$catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
if ($catalog.schemaVersion -ne 1 -or $catalog.kind -ne 'shader-family-catalog') { throw 'Catalog envelope regression' }
if ($catalog.families.Count -ne $source.families.Count -or $catalog.families.Count -ne 13) { throw 'Remake family-count regression' }

$sourceKeys = @($source.families | ForEach-Object { $stage=$_.stage; @($_.hashes | ForEach-Object { "$stage|$($_.hash.ToUpperInvariant())" }) } | Sort-Object)
$catalogKeys = @($catalog.families | ForEach-Object { $implementation=$_.implementations[0]; @($implementation.variants.targets | ForEach-Object { "$($implementation.stage)|$($_.shaderHash)" }) } | Sort-Object)
if ($sourceKeys.Count -ne 34 -or @(Compare-Object $sourceKeys $catalogKeys).Count -ne 0) { throw 'Remake stage/hash preservation regression' }

foreach ($implementation in @($catalog.families.implementations)) {
    if ($implementation.api -ne 'D3D11' -or $implementation.bytecodeFormat -ne 'DXBC') { throw 'Remake backend boundary regression' }
    if ($implementation.identityModel -ne '3dmigoto-dxbc-fnv1-v1') { throw 'Remake identity-model regression' }
    foreach ($variant in @($implementation.variants)) {
        if ($variant.identity.canonicalShaderHash -ne $variant.targets[0].shaderHash) { throw 'Exact identity/target mismatch' }
    }
}

$requiredSplits = @(
    'shadow-depth-caster-skinned-vertex',
    'shadow-depth-caster-static-vertex',
    'shadow-depth-writer-sampled-material-pixel',
    'shadow-depth-writer-direct-pixel',
    'material-gbuffer-producers',
    'skinned-material-gbuffer-vertex-producer',
    'tiled-surface-light-evaluation',
    'temporal-screen-space-ambient-occlusion',
    'screen-space-reflection-trace-resolve',
    'reflection-indirect-composite'
)
foreach ($familyId in $requiredSplits) {
    if (@($catalog.families | Where-Object { $_.id -eq $familyId }).Count -ne 1) { throw "Required family split missing: $familyId" }
}
$local = @($catalog.families | Where-Object { $_.id -eq 'tiled-surface-light-evaluation' })[0]
if ($local.implementations[0].variants.Count -ne 5) { throw 'Five-variant local-light family regression' }

Write-Host 'PASS: portable Remake catalog preserves all 34 exact identities and all verified dynamic/static/material/light family boundaries.'
