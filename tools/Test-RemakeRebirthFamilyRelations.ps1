[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = Split-Path $PSScriptRoot -Parent
$relationPath = Join-Path $workspace 'src\Adapters\FF7RemakeIntergrade\rebirth-family-relations.json'
$schemaPath = Join-Path $workspace 'src\Engine\ShaderFamilies\relations.schema.json'

& (Join-Path $PSScriptRoot 'Test-RebirthShaderFamilyCatalog.ps1')
& (Join-Path $PSScriptRoot 'Test-RemakeShaderFamilyCatalog.ps1')

$schema = Get-Content -Raw -LiteralPath $schemaPath | ConvertFrom-Json
$relations = Get-Content -Raw -LiteralPath $relationPath | ConvertFrom-Json
if ($schema.title -ne 'Explicit shader-family relations') { throw 'Relations schema is missing or unexpected' }
if ($relations.schemaVersion -ne 1 -or $relations.catalogs.Count -ne 2) { throw 'Relations envelope regression' }

$catalogs = @{}
foreach ($reference in @($relations.catalogs)) {
    $fullPath = Join-Path $workspace ([string]$reference.path)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Referenced catalog missing: $fullPath" }
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $fullPath).Hash.ToUpperInvariant()
    if ($actualHash -ne $reference.sha256) { throw "Catalog hash changed without relation review: $($reference.id)" }
    $catalog = Get-Content -Raw -LiteralPath $fullPath | ConvertFrom-Json
    if ($catalog.id -ne $reference.id) { throw "Catalog ID/path mismatch: $($reference.id)" }
    $catalogs[$reference.id] = $catalog
}

$accounted = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($relation in @($relations.relations)) {
    $fromCatalog = $catalogs[[string]$relation.from.catalog]
    $toCatalog = $catalogs[[string]$relation.to.catalog]
    if ($null -eq $fromCatalog -or $null -eq $toCatalog) { throw 'Relation references an undeclared catalog' }
    if (@($fromCatalog.families | Where-Object { $_.id -eq $relation.from.family }).Count -ne 1) { throw 'Relation source family is missing or ambiguous' }
    if (@($toCatalog.families | Where-Object { $_.id -eq $relation.to.family }).Count -ne 1) { throw 'Relation target family is missing or ambiguous' }
    $key = "$($relation.from.catalog)|$($relation.from.family)"
    if (-not $accounted.Add($key)) { throw "Duplicate donor-family decision: $key" }
}
foreach ($unresolved in @($relations.unresolved)) {
    $fromCatalog = $catalogs[[string]$unresolved.from.catalog]
    if ($null -eq $fromCatalog) { throw 'Unresolved entry references an undeclared catalog' }
    if (@($fromCatalog.families | Where-Object { $_.id -eq $unresolved.from.family }).Count -ne 1) { throw 'Unresolved source family is missing or ambiguous' }
    $key = "$($unresolved.from.catalog)|$($unresolved.from.family)"
    if (-not $accounted.Add($key)) { throw "Duplicate donor-family decision: $key" }
}

$rebirth = $catalogs['ff7-rebirth-shader-injector-v2-2-1']
if ($accounted.Count -ne $rebirth.families.Count -or $accounted.Count -ne 11) { throw 'Every donor family must have exactly one reviewed mapping decision' }
if ($relations.relations.Count -ne 3 -or $relations.unresolved.Count -ne 8) { throw 'Only one current cross-game relation is sufficiently proven' }
$verified = @($relations.relations | Where-Object { $_.from.family -eq 'local-light' })[0]
if ($verified.from.family -ne 'local-light' -or $verified.to.family -ne 'tiled-surface-light-evaluation') { throw 'Verified LocalLight relation regression' }
$fromStage = @($rebirth.families | Where-Object { $_.id -eq $verified.from.family })[0].implementations[0].stage
$remake = $catalogs['ff7-remake-intergrade-verified-area-20260831']
$toStage = @($remake.families | Where-Object { $_.id -eq $verified.to.family })[0].implementations[0].stage
if ($fromStage -ne 'ps' -or $toStage -ne 'cs') { throw 'Expected the verified semantic relation to retain its PS/CS backend boundary' }

$ssr = @($relations.relations | Where-Object { $_.from.family -eq 'ssr' })
if ($ssr.Count -ne 1 -or $ssr[0].to.family -ne 'screen-space-reflection-trace-resolve') { throw 'Verified SSR relation regression' }
$reflection = @($relations.relations | Where-Object { $_.from.family -eq 'reflection-environment' })
if ($reflection.Count -ne 1 -or $reflection[0].to.family -ne 'reflection-indirect-composite' -or $reflection[0].relationType -ne 'partial-semantic-role-adapter') {
    throw 'Verified partial reflection-environment relation regression'
}
if (@($relations.unresolved | Where-Object { $_.from.family -in @('ssr','reflection-environment') }).Count -ne 0) {
    throw 'Promoted SSR/reflection families remain duplicated in unresolved decisions'
}
foreach ($required in @('directional-light','local-light-ies')) {
    if (@($relations.unresolved | Where-Object { $_.from.family -eq $required }).Count -ne 1) { throw "Required unresolved family decision missing: $required" }
}

Write-Host 'PASS: all 11 Rebirth donor families have one explicit, hash-pinned Remake mapping decision; LocalLight, SSR, and the partial ReflectionEnvironment consumer boundary are promoted.'
