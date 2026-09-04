[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = Split-Path $PSScriptRoot -Parent
$rebirthPath = Join-Path $workspace 'artifacts\analysis\rebirth-shader-injector-v2.2.1-family-catalog.json'
$remakePath = Join-Path $workspace 'artifacts\analysis\ff7-remake-intergrade-verified-family-catalog.json'
$resolver = Join-Path $PSScriptRoot 'Resolve-ShaderFamilyCatalogTarget.ps1'

& (Join-Path $PSScriptRoot 'Test-RebirthShaderFamilyCatalog.ps1')
& (Join-Path $PSScriptRoot 'Test-RemakeShaderFamilyCatalog.ps1')

$rebirthLocal = & $resolver -CatalogPath $rebirthPath -Stage ps -ShaderHash C9B3269F5B403EE2
if ($rebirthLocal.familyId -ne 'local-light' -or $rebirthLocal.identityModel -ne 'shader-injector-dxil-analysis-v1') { throw 'Rebirth LocalLight resolution regression' }
if ($rebirthLocal.versionGroup -ne 'GameVersion1005') { throw 'Rebirth target version regression' }

$remakeLocal = & $resolver -CatalogPath $remakePath -Stage cs -ShaderHash 62b33a2d1e505241
if ($remakeLocal.familyId -ne 'tiled-surface-light-evaluation' -or $remakeLocal.identityModel -ne '3dmigoto-dxbc-fnv1-v1') { throw 'Remake local-light resolution regression' }

$clothing = & $resolver -CatalogPath $remakePath -Stage ps -ShaderHash 8b1f6ebe443b5615
if ($clothing.familyId -ne 'material-gbuffer-producers') { throw 'Cloud clothing/material resolution regression' }
$clothingVs = & $resolver -CatalogPath $remakePath -Stage vs -ShaderHash 0fcd2a51d59b6599
if ($clothingVs.familyId -ne 'skinned-material-gbuffer-vertex-producer') { throw 'Cloud clothing vertex-peer resolution regression' }

$wrongStage = @(& $resolver -CatalogPath $remakePath -Stage ps -ShaderHash 62b33a2d1e505241 -AllowNoMatch)
if ($wrongStage.Count -ne 0) { throw 'Stage mismatch must not resolve' }
$unknown = @(& $resolver -CatalogPath $remakePath -Stage cs -ShaderHash 0000000000000000 -AllowNoMatch)
if ($unknown.Count -ne 0) { throw 'Unknown hash must not resolve' }

$malformedRejected = $false
try { & $resolver -CatalogPath $remakePath -Stage cs -ShaderHash BAD -AllowNoMatch | Out-Null }
catch { $malformedRejected = $_.Exception.Message -like 'ShaderHash must be exactly*' }
if (-not $malformedRejected) { throw 'Malformed shader hash was not rejected' }

Write-Host 'PASS: catalog resolver maps exact stage/hash targets to reviewed families and rejects wrong-stage, unknown, and malformed identities.'
