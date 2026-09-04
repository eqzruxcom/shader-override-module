[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$resolver = Join-Path $PSScriptRoot 'Resolve-IntergradeDirectLightTopology.ps1'
$a = Join-Path $root 'artifacts\analysis\intergrade-direct-light-topology-resolved.test-a.json'
$b = Join-Path $root 'artifacts\analysis\intergrade-direct-light-topology-resolved.test-b.json'

try {
    & $resolver -OutputPath $a | Out-Host
    & $resolver -OutputPath $b | Out-Host
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $a).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $b).Hash) { throw 'Resolved direct-light topology is not deterministic' }
    $report = Get-Content -Raw -LiteralPath $a | ConvertFrom-Json
    if ($report.detector -ne 'ff7-remake-dxbc-direct-light-topology-v2-resolved' -or $report.schemaVersion -ne 2) { throw 'Unexpected resolved topology schema' }
    if ($report.sharedTiledSurfaceLightFamily.variantCount -ne 5) { throw 'Expected five shared variants' }
    if (@($report.sharedTiledSurfaceLightFamily.variants | Where-Object outputComposition -ne 'read-modify-write-existing-lighting').Count -ne 0) { throw 'All-five composition proof regressed' }
    if (@($report.sharedTiledSurfaceLightFamily.variants | Where-Object { -not $_.angularProfileAtlas.conditionalPerLight }).Count -ne 0) { throw 'Profile branch is not proven in every variant' }
    if ((@($report.sharedTiledSurfaceLightFamily.variants.angularProfileAtlas.textureSlot | Sort-Object -Unique) -join ',') -ne '7,8') { throw 'Profile texture layouts changed' }
    if ((@($report.sharedTiledSurfaceLightFamily.variants.angularProfileAtlas.priorLightingTextureSlot | Sort-Object -Unique) -join ',') -ne '8,9') { throw 'Prior-lighting layouts changed' }
    if ($report.sharedTiledSurfaceLightFamily.directionalLight -notmatch '^not separately proven') { throw 'Directional fail-closed gate regressed' }
} finally {
    foreach ($path in @($a,$b)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
}

Write-Host 'PASS: resolved topology pins five read/modify/write evaluators, five integrated profile branches, and an unproven directional owner.'
