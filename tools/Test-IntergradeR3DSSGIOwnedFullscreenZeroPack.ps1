[CmdletBinding()]
param(
    [string]$PackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-zero-pack')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pack = [IO.Path]::GetFullPath($PackRoot).TrimEnd('\')
$manifestPath = Join-Path $pack 'manifest.json'
$mods = Join-Path $pack 'Mods'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $mods -PathType Container)) {
    throw 'Owned fullscreen pack or manifest is missing.'
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.result -ne 'pass' -or
    $manifest.basisVariant -ne '05-zero-composite' -or
    $manifest.hook -ne 'e2aa1c8cb39e0a55-ps' -or
    $manifest.runtimeEligible -ne $false -or $manifest.installed -ne $false) {
    throw 'Owned fullscreen manifest contract is invalid.'
}

$files = @(Get-ChildItem -LiteralPath $mods -File | Sort-Object Name)
if ($files.Count -ne 8 -or @($manifest.files).Count -ne 8) {
    throw 'Owned fullscreen pack must contain exactly eight Mods files.'
}
foreach ($record in @($manifest.files)) {
    $path = Join-Path $mods ([string]$record.name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$record.sha256 -or
        (Get-Item -LiteralPath $path).Length -ne [long]$record.bytes) {
        throw "Pack file failed manifest verification: $($record.name)"
    }
}

$ini = Get-Content -Raw -LiteralPath (Join-Path $mods 'Agent2R3DSSGITest.ini')
$composite = [regex]::Match($ini, '(?ms)^\[CustomShaderAgent2R3DSSGIComposite\]\r?\n(?<body>.*?)(?=^\[|\z)')
if (-not $composite.Success) { throw 'Owned composite section is missing.' }
$body = $composite.Groups['body'].Value
foreach ($line in @(
    'vs = Agent2R3DSSGIFullscreen_vs.hlsl',
    'hs = null',
    'ds = null',
    'gs = null',
    'blend = ADD ONE ONE',
    'depth_enable = false',
    'depth_write_mask = zero',
    'stencil_enable = false',
    'cull = none',
    'topology = triangle_list',
    'draw = 3, 0'
)) {
    if ([regex]::Matches($body, "(?m)^$([regex]::Escape($line))\r?$").Count -ne 1) {
        throw "Owned composite contract is missing or duplicates: $line"
    }
}
if ($body -match '(?im)^draw = from_caller\r?$' -or
    [regex]::Matches($ini, '(?im)^draw = from_caller\r?$').Count -ne 5) {
    throw 'Only the composite pass may stop using the caller draw.'
}
if ([regex]::Matches($ini, '(?im)^\s*key\s*=.*(?<![A-Z0-9_])F2(?![A-Z0-9_]).*\r?$').Count -ne 1 -or
    $ini -match '(?im)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F10(?![A-Z0-9_]).*\r?$') {
    throw 'Owned fullscreen pack changed the F2/F10 key contract.'
}

$vs = Get-Content -Raw -LiteralPath (Join-Path $mods 'Agent2R3DSSGIFullscreen_vs.hlsl')
$ps = Get-Content -Raw -LiteralPath (Join-Path $mods 'Agent2R3DSSGICompositeE2AA_ps.hlsl')
if ($vs -notmatch 'SV_VertexID' -or $vs -notmatch 'float2\(\(vertexId << 1\) & 2, vertexId & 2\)' -or
    $ps -notmatch '(?s)float4 main\(FullscreenInput input\) : SV_Target0\s*\{\s*// Diagnostic:.*?return 0\.0;') {
    throw 'Owned fullscreen shaders do not match the intended zero-output diagnostic.'
}

foreach ($compiled in @(
    'compile-verification\Agent2R3DSSGIFullscreen_vs.bin',
    'compile-verification\Agent2R3DSSGICompositeE2AA_ps.bin'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $pack $compiled) -PathType Leaf)) {
        throw "Compile-verification artifact is missing: $compiled"
    }
}

[pscustomobject]@{
    Result='pass'
    Files=$files.Count
    CompositeDraw='owned Draw(3,0)'
    CallerDrawsPreserved=5
    F10='unbound'
    RuntimeEligible=$false
}
