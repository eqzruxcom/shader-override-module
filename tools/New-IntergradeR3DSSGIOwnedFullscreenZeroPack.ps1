[CmdletBinding()]
param(
    [string]$SourceRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-isolation-matrix\05-zero-composite'),
    [string]$VertexShaderPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Adapters\FF7RemakeIntergrade\R3DSSGIFullscreen_vs.hlsl'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-zero-pack'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$source = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
$vertex = [IO.Path]::GetFullPath($VertexShaderPath)
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$artifactsRoot = Join-Path $workspace 'artifacts'

if (-not $source.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
    -not $output.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Source and output must be children of the workspace artifacts directory.'
}
if (-not $vertex.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The fullscreen vertex shader must be inside the workspace.'
}
foreach ($path in @($source, (Join-Path $source 'Mods'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Required directory is missing: $path" }
}
foreach ($path in @($vertex, $FxcPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file is missing: $path" }
}

$sourceMods = Join-Path $source 'Mods'
$iniPath = Join-Path $sourceMods 'Agent2R3DSSGITest.ini'
$zeroPixelPath = Join-Path $sourceMods 'Agent2R3DSSGICompositeE2AA_ps.hlsl'
$ini = Get-Content -Raw -LiteralPath $iniPath
$zeroPixel = Get-Content -Raw -LiteralPath $zeroPixelPath
if ($ini -notmatch '(?m)^; ISOLATION MATRIX: 05-zero-composite\r?$' -or
    $zeroPixel -notmatch '(?s)float4 main\(FullscreenInput input\) : SV_Target0\s*\{\s*// Diagnostic:.*?return 0\.0;') {
    throw 'The source is not the verified zero-output composite isolation variant.'
}

$sectionPattern = '(?ms)^\[CustomShaderAgent2R3DSSGIComposite\]\r?\n(?<body>.*?)(?=^\[|\z)'
$section = [regex]::Match($ini, $sectionPattern)
if (-not $section.Success) { throw 'Composite CustomShader section is missing.' }
$body = $section.Groups['body'].Value
$stateNeedle = "ps = Agent2R3DSSGICompositeE2AA_ps.hlsl`r`nsampler = linear_filter`r`nblend = ADD ONE ONE"
$stateReplacement = @(
    'ps = Agent2R3DSSGICompositeE2AA_ps.hlsl'
    'vs = Agent2R3DSSGIFullscreen_vs.hlsl'
    'hs = null'
    'ds = null'
    'gs = null'
    'sampler = linear_filter'
    'blend = ADD ONE ONE'
    'depth_enable = false'
    'depth_write_mask = zero'
    'stencil_enable = false'
    'cull = none'
    'topology = triangle_list'
) -join "`r`n"
if ([regex]::Matches($body, [regex]::Escape($stateNeedle)).Count -ne 1 -or
    [regex]::Matches($body, '(?m)^draw = from_caller\r?$').Count -ne 1) {
    throw 'Composite section does not match the expected owned-pass insertion points.'
}
$body = $body.Replace($stateNeedle, $stateReplacement)
$body = [regex]::Replace($body, '(?m)^draw = from_caller\r?$', 'draw = 3, 0')
$replacementSection = "[CustomShaderAgent2R3DSSGIComposite]`r`n" + $body
$ownedIni = $ini.Substring(0, $section.Index) + $replacementSection + $ini.Substring($section.Index + $section.Length)

if (Test-Path -LiteralPath $output -PathType Container) { [IO.Directory]::Delete($output, $true) }
$outputMods = Join-Path $output 'Mods'
[IO.Directory]::CreateDirectory($outputMods) | Out-Null
foreach ($file in Get-ChildItem -LiteralPath $sourceMods -File) {
    [IO.File]::Copy($file.FullName, (Join-Path $outputMods $file.Name), $false)
}
[IO.File]::Copy($vertex, (Join-Path $outputMods 'Agent2R3DSSGIFullscreen_vs.hlsl'), $false)
[IO.File]::WriteAllText((Join-Path $outputMods 'Agent2R3DSSGITest.ini'), $ownedIni, [Text.UTF8Encoding]::new($false))

$compileRoot = Join-Path $output 'compile-verification'
[IO.Directory]::CreateDirectory($compileRoot) | Out-Null
$vsBin = Join-Path $compileRoot 'Agent2R3DSSGIFullscreen_vs.bin'
$psBin = Join-Path $compileRoot 'Agent2R3DSSGICompositeE2AA_ps.bin'
& $FxcPath /nologo /T vs_5_0 /E main /Fo $vsBin (Join-Path $outputMods 'Agent2R3DSSGIFullscreen_vs.hlsl')
if ($LASTEXITCODE -ne 0) { throw "Fullscreen VS compilation failed: $LASTEXITCODE" }
& $FxcPath /nologo /T ps_5_0 /E main /Fo $psBin (Join-Path $outputMods 'Agent2R3DSSGICompositeE2AA_ps.hlsl')
if ($LASTEXITCODE -ne 0) { throw "Zero-output composite PS compilation failed: $LASTEXITCODE" }

$files = @(Get-ChildItem -LiteralPath $outputMods -File | Sort-Object Name | ForEach-Object {
    [ordered]@{
        name=$_.Name
        sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
        bytes=$_.Length
    }
})
$manifest = [ordered]@{
    schemaVersion=1
    result='pass'
    variant='owned-fullscreen-zero-output'
    purpose='Prove a zero-output composite using injector-owned fullscreen geometry and explicit render state.'
    basisVariant='05-zero-composite'
    hook='e2aa1c8cb39e0a55-ps'
    controls=[ordered]@{F2='off/on';F10='native reload, unchanged';PageUp='unchanged';PageDown='unchanged'}
    ownedPass=[ordered]@{
        vertexShader='Agent2R3DSSGIFullscreen_vs.hlsl'
        vertexInput='SV_VertexID only'
        topology='triangle_list'
        draw='3, 0'
        hullShader='null'
        domainShader='null'
        geometryShader='null'
        depth='disabled'
        stencil='disabled'
        cull='none'
        blend='ADD ONE ONE'
        output='literal float4(0,0,0,0)'
    }
    compile=[ordered]@{
        fxcPath=$FxcPath
        fxcSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $FxcPath).Hash
        vsProfile='vs_5_0'
        vsBytecodeSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $vsBin).Hash
        psProfile='ps_5_0'
        psBytecodeSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $psBin).Hash
    }
    expectedVisual='Identical to F2 off. Any skin change would implicate target/resource binding rather than caller geometry.'
    files=$files
    runtimeEligible=$false
    installed=$false
}
$manifestPath = Join-Path $output 'manifest.json'
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 10) + "`r`n"), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Result='pass'
    Files=$files.Count
    Output=$output
    Manifest=$manifestPath
    RuntimeEligible=$false
}
