[CmdletBinding()]
param(
    [string]$PackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-private-target-zero-pack'),
    [string]$SourceRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-zero-pack')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $PackRoot 'manifest.json'
$sourceManifestPath = Join-Path $SourceRoot 'manifest.json'
foreach ($path in @($manifestPath, $sourceManifestPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Manifest missing: $path" }
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$sourceManifest = Get-Content -Raw -LiteralPath $sourceManifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.result -ne 'pass' -or
    $manifest.variant -ne 'owned-fullscreen-private-target-zero-output' -or $manifest.runtimeEligible -ne $false -or
    $manifest.ownedPass.target -ne 'private copy_desc of captured target' -or $manifest.ownedPass.writeback -ne 'none' -or
    $manifest.source.manifestSha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceManifestPath).Hash) {
    throw 'Private-target manifest contract failed.'
}

$mods = Join-Path $PackRoot 'Mods'
$sourceMods = Join-Path $SourceRoot 'Mods'
$files = @($manifest.files)
if ($files.Count -ne 8) { throw 'Private-target pack must contain exactly eight files.' }
foreach ($file in $files) {
    $path = Join-Path $mods ([string]$file.name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$file.sha256) {
        throw "Private-target payload drifted: $($file.name)"
    }
}
foreach ($file in @($sourceManifest.files | Where-Object name -ne 'Agent2R3DSSGITest.ini')) {
    $name = [string]$file.name
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $mods $name)).Hash -ne
        (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $sourceMods $name)).Hash) {
        throw "Shader changed in target-only test: $name"
    }
}

$ini = Get-Content -Raw -LiteralPath (Join-Path $mods 'Agent2R3DSSGITest.ini')
if ([regex]::Matches($ini, '(?m)^\[ResourceAgent2SSGICompositeScratch\]\r?$').Count -ne 1 -or
    [regex]::Matches($ini, '(?m)^ResourceAgent2SSGICompositeScratch = copy_desc ResourceAgent2SSGITarget\r?$').Count -ne 1 -or
    [regex]::Matches($ini, '(?m)^o0 = set_viewport ResourceAgent2SSGICompositeScratch\r?$').Count -ne 1 -or
    [regex]::Matches($ini, '(?im)^\s*draw\s*=\s*3\s*,\s*0\s*$').Count -ne 1 -or
    $ini -match '(?ms)^\[CustomShaderAgent2R3DSSGIComposite\].*?^o0 = set_viewport ResourceAgent2SSGITarget\r?$' -or
    $ini -match '(?im)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F10(?![A-Z0-9_]).*$') {
    throw 'Private-target INI contract failed.'
}

[pscustomobject]@{
    Result='pass'; Files=$files.Count; ShadersByteIdentical=7; CompositeTarget='private scratch'; Writeback='none'
    F10='unbound'; RuntimeEligible=$false
}
