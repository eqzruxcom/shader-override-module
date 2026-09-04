[CmdletBinding()]
param(
    [string]$SourceRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-character-safe-pack'),
    [string]$VertexShaderPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Adapters\FF7RemakeIntergrade\R3DSSGIFullscreen_vs.hlsl'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-real-pack'),
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
foreach ($path in @((Join-Path $source 'manifest.json'), (Join-Path $source 'Mods'), $vertex, $FxcPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required input is missing: $path" }
}

$sourceManifestPath = Join-Path $source 'manifest.json'
$sourceManifest = Get-Content -Raw -LiteralPath $sourceManifestPath | ConvertFrom-Json
if ($sourceManifest.schemaVersion -ne 1 -or $sourceManifest.result -ne 'pass' -or
    $sourceManifest.variant -ne 'material-aware-bounded-hdr-character-safe-v1' -or
    $sourceManifest.target.shader -ne 'e2aa1c8cb39e0a55' -or
    $sourceManifest.controls.F2 -notmatch 'SSGI') {
    throw 'The selected real SSGI source manifest is not the reviewed character-safe candidate.'
}
$sourceMods = Join-Path $source 'Mods'
$sourceFiles = @($sourceManifest.files)
if ($sourceFiles.Count -ne 7) { throw 'The reviewed source pack must contain exactly seven files.' }
foreach ($file in $sourceFiles) {
    $name = Split-Path -Leaf ([string]$file.path)
    $path = Join-Path $sourceMods $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$file.sha256) {
        throw "Reviewed source payload drifted: $name"
    }
}

$iniPath = Join-Path $sourceMods 'Agent2R3DSSGITest.ini'
$compositePath = Join-Path $sourceMods 'Agent2R3DSSGICompositeE2AA_ps.hlsl'
$ini = Get-Content -Raw -LiteralPath $iniPath
$composite = Get-Content -Raw -LiteralPath $compositePath
if ($composite -notmatch '(?m)^\s*return float4\(indirectRadiance, 0\.0\);\s*$' -or
    $composite -match '(?s)float4 main\(FullscreenInput input\).*?return 0\.0;\s*\}') {
    throw 'The source composite is not the reviewed real indirect-light implementation.'
}
if ([regex]::Matches($ini,'(?im)^\s*key\s*=.*(?<![A-Z0-9_])F2(?![A-Z0-9_]).*$').Count -ne 1 -or
    $ini -match '(?im)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F10(?![A-Z0-9_]).*$') {
    throw 'Source key contract is invalid or attempts to bind F10.'
}

$sectionPattern = '(?ms)^\[CustomShaderAgent2R3DSSGIComposite\]\r?\n(?<body>.*?)(?=^\[|\z)'
$section = [regex]::Match($ini, $sectionPattern)
if (-not $section.Success) { throw 'Composite CustomShader section is missing.' }
$body = $section.Groups['body'].Value
if ([regex]::Matches($body, '(?m)^ps = Agent2R3DSSGICompositeE2AA_ps\.hlsl\r?$').Count -ne 1 -or
    [regex]::Matches($body, '(?m)^draw = from_caller\r?$').Count -ne 1) {
    throw 'Composite section does not match the expected adaptation points.'
}
$body = [regex]::Replace(
    $body,
    '(?m)^ps = Agent2R3DSSGICompositeE2AA_ps\.hlsl\r?$',
    @(
        'ps = Agent2R3DSSGICompositeE2AA_ps.hlsl'
        'vs = Agent2R3DSSGIFullscreen_vs.hlsl'
        'hs = null'
        'ds = null'
        'gs = null'
    ) -join "`r`n"
)
$body = [regex]::Replace(
    $body,
    '(?m)^blend = ADD ONE ONE\r?$',
    @(
        'blend = ADD ONE ONE'
        'depth_enable = false'
        'depth_write_mask = zero'
        'stencil_enable = false'
        'cull = none'
        'topology = triangle_list'
    ) -join "`r`n"
)
$body = [regex]::Replace($body, '(?m)^draw = from_caller\r?$', 'draw = 3, 0')
$ownedIni = $ini.Substring(0, $section.Index) + "[CustomShaderAgent2R3DSSGIComposite]`r`n" + $body + $ini.Substring($section.Index + $section.Length)

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
$compiled = @()
foreach ($file in Get-ChildItem -LiteralPath $outputMods -File -Filter '*.hlsl' | Sort-Object Name) {
    $isVertex = $file.Name.EndsWith('_vs.hlsl', [StringComparison]::OrdinalIgnoreCase)
    $profile = if ($isVertex) { 'vs_5_0' } else { 'ps_5_0' }
    $bin = Join-Path $compileRoot ($file.BaseName + '.bin')
    & $FxcPath /nologo /T $profile /E main /Fo $bin $file.FullName
    if ($LASTEXITCODE -ne 0) { throw "Shader compilation failed ($profile): $($file.Name)" }
    $compiled += [ordered]@{name=$file.Name;profile=$profile;bytecodeSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $bin).Hash}
}

$files = @(Get-ChildItem -LiteralPath $outputMods -File | Sort-Object Name | ForEach-Object {
    [ordered]@{name=$_.Name;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash;bytes=$_.Length}
})
$manifest = [ordered]@{
    schemaVersion=1
    result='pass'
    purpose='Run the reviewed real R3D SSGI composite on injector-owned fullscreen geometry.'
    source=[ordered]@{
        variant=[string]$sourceManifest.variant
        manifest=$sourceManifestPath
        manifestSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $sourceManifestPath).Hash
    }
    hook='e2aa1c8cb39e0a55-ps'
    controls=[ordered]@{F2='off/on';F10='native reload, unchanged';PageUp='unchanged';PageDown='unchanged'}
    preservedEffect=$sourceManifest.effect
    ownedComposite=[ordered]@{
        vertexShader='Agent2R3DSSGIFullscreen_vs.hlsl'
        vertexInput='SV_VertexID only'
        draw='3, 0'
        topology='triangle_list'
        hullShader='null'
        domainShader='null'
        geometryShader='null'
        depth='disabled'
        stencil='disabled'
        cull='none'
        blend='ADD ONE ONE'
    }
    compile=$compiled
    files=$files
    expectedVisual='F2 adds the reviewed indirect lighting without changing geometry coverage or skin through caller-draw inheritance.'
    runtimeEligible=$false
    installed=$false
    prerequisite='Complete zero-output variants 06 and 07, then validate the owned zero-output pack first.'
}
$manifestPath = Join-Path $output 'manifest.json'
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 12) + "`r`n"), [Text.UTF8Encoding]::new($false))
[pscustomobject]@{Result='pass';Files=$files.Count;Compiled=$compiled.Count;Output=$output;RuntimeEligible=$false}
