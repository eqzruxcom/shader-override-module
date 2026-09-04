[CmdletBinding()]
param(
    [string]$PackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-real-pack'),
    [string]$SourceRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-character-safe-pack')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$manifestPath = Join-Path $PackRoot 'manifest.json'
$sourceManifestPath = Join-Path $SourceRoot 'manifest.json'
foreach ($path in @($manifestPath, $sourceManifestPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Manifest is missing: $path" }
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$sourceManifest = Get-Content -Raw -LiteralPath $sourceManifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.result -ne 'pass' -or $manifest.runtimeEligible -ne $false -or
    $manifest.installed -ne $false -or $manifest.hook -ne 'e2aa1c8cb39e0a55-ps' -or
    $manifest.source.manifestSha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceManifestPath).Hash) {
    throw 'Owned real-pack manifest contract is invalid.'
}
$packMods = Join-Path $PackRoot 'Mods'
$sourceMods = Join-Path $SourceRoot 'Mods'
$files = @($manifest.files)
if ($files.Count -ne 8 -or @($manifest.compile).Count -ne 7) { throw 'Owned real pack must contain eight files and seven compiled shaders.' }
foreach ($file in $files) {
    $path = Join-Path $packMods ([string]$file.name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$file.sha256) {
        throw "Owned real-pack payload drifted: $($file.name)"
    }
}

foreach ($file in @($sourceManifest.files)) {
    $name = Split-Path -Leaf ([string]$file.path)
    if ($name -eq 'Agent2R3DSSGITest.ini') { continue }
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $sourceMods $name)).Hash
    $packHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $packMods $name)).Hash
    if ($sourceHash -ne $packHash) { throw "Effect shader changed while adapting pass ownership: $name" }
}

$ini = Get-Content -Raw -LiteralPath (Join-Path $packMods 'Agent2R3DSSGITest.ini')
$composite = Get-Content -Raw -LiteralPath (Join-Path $packMods 'Agent2R3DSSGICompositeE2AA_ps.hlsl')
$vs = Get-Content -Raw -LiteralPath (Join-Path $packMods 'Agent2R3DSSGIFullscreen_vs.hlsl')
if ([regex]::Matches($ini,'(?im)^\s*key\s*=.*(?<![A-Z0-9_])F2(?![A-Z0-9_]).*$').Count -ne 1 -or
    $ini -match '(?im)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F10(?![A-Z0-9_]).*$') {
    throw 'F2/F10 control contract failed.'
}
if ([regex]::Matches($ini,'(?im)^\s*draw\s*=\s*from_caller\s*$').Count -ne 5 -or
    [regex]::Matches($ini,'(?im)^\s*draw\s*=\s*3\s*,\s*0\s*$').Count -ne 1) {
    throw 'Only the composite may switch from caller geometry to owned Draw(3,0).'
}
foreach ($needle in @(
    'vs = Agent2R3DSSGIFullscreen_vs.hlsl','hs = null','ds = null','gs = null',
    'depth_enable = false','depth_write_mask = zero','stencil_enable = false',
    'cull = none','topology = triangle_list'
)) {
    if ($ini -notmatch ('(?im)^\s*' + [regex]::Escape($needle) + '\s*$')) { throw "Owned composite state is missing: $needle" }
}
if ($vs -notmatch 'SV_VertexID' -or $composite -notmatch '(?m)^\s*return float4\(indirectRadiance, 0\.0\);\s*$') {
    throw 'Owned VS or real indirect-light PS contract failed.'
}

[pscustomobject]@{
    Result='pass'
    Files=$files.Count
    Compiled=@($manifest.compile).Count
    CompositeDraw='owned Draw(3,0)'
    CallerDrawsPreserved=5
    EffectShadersUnchanged=6
    F10='unbound'
    RuntimeEligible=$manifest.runtimeEligible
}
