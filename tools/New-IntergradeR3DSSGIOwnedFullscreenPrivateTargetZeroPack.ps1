[CmdletBinding()]
param(
    [string]$SourceRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-zero-pack'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-private-target-zero-pack')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$source = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$artifacts = Join-Path $workspace 'artifacts'
foreach ($path in @($source, $output)) {
    if (-not $path.StartsWith($artifacts + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Pack path escaped artifacts: $path"
    }
}

$sourceManifestPath = Join-Path $source 'manifest.json'
if (-not (Test-Path -LiteralPath $sourceManifestPath -PathType Leaf)) { throw "Source manifest missing: $sourceManifestPath" }
$sourceManifest = Get-Content -Raw -LiteralPath $sourceManifestPath | ConvertFrom-Json
if ($sourceManifest.schemaVersion -ne 1 -or $sourceManifest.result -ne 'pass' -or
    $sourceManifest.variant -ne 'owned-fullscreen-zero-output' -or $sourceManifest.runtimeEligible -ne $false -or
    $sourceManifest.ownedPass.draw -ne '3, 0' -or @($sourceManifest.files).Count -ne 8) {
    throw 'Owned zero source manifest contract failed.'
}

$sourceMods = Join-Path $source 'Mods'
foreach ($file in @($sourceManifest.files)) {
    $path = Join-Path $sourceMods ([string]$file.name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$file.sha256) {
        throw "Owned zero source drifted: $($file.name)"
    }
}

$iniPath = Join-Path $sourceMods 'Agent2R3DSSGITest.ini'
$ini = Get-Content -Raw -LiteralPath $iniPath
$declaration = '[ResourceAgent2SSGITarget]'
if ([regex]::Matches($ini, '(?m)^\[ResourceAgent2SSGITarget\]\r?$').Count -ne 1 -or
    $ini -match '(?m)^\[ResourceAgent2SSGICompositeScratch\]\r?$') {
    throw 'Private-target declaration insertion point is invalid.'
}
$ini = $ini.Replace($declaration, $declaration + "`r`n[ResourceAgent2SSGICompositeScratch]")

$section = [regex]::Match($ini, '(?ms)^\[CustomShaderAgent2R3DSSGIComposite\]\r?\n(?<body>.*?)(?=^\[|\z)')
if (-not $section.Success) { throw 'Composite section missing.' }
$body = $section.Groups['body'].Value
$targetLine = 'o0 = set_viewport ResourceAgent2SSGITarget'
if ([regex]::Matches($body, '(?m)^' + [regex]::Escape($targetLine) + '\r?$').Count -ne 1) {
    throw 'Live-target binding is not unique in the composite section.'
}
$privateLines = "ResourceAgent2SSGICompositeScratch = copy_desc ResourceAgent2SSGITarget`r`no0 = set_viewport ResourceAgent2SSGICompositeScratch"
$body = $body.Replace($targetLine, $privateLines)
$patched = $ini.Substring(0, $section.Index) + "[CustomShaderAgent2R3DSSGIComposite]`r`n" + $body + $ini.Substring($section.Index + $section.Length)
if ($patched -match '(?ms)^\[CustomShaderAgent2R3DSSGIComposite\].*?^o0 = set_viewport ResourceAgent2SSGITarget\r?$') {
    throw 'Composite still writes the live target.'
}

if (Test-Path -LiteralPath $output -PathType Container) { [IO.Directory]::Delete($output, $true) }
$outputMods = Join-Path $output 'Mods'
[IO.Directory]::CreateDirectory($outputMods) | Out-Null
foreach ($file in Get-ChildItem -LiteralPath $sourceMods -File) {
    [IO.File]::Copy($file.FullName, (Join-Path $outputMods $file.Name), $false)
}
[IO.File]::WriteAllText((Join-Path $outputMods 'Agent2R3DSSGITest.ini'), $patched, [Text.UTF8Encoding]::new($false))

$files = @(Get-ChildItem -LiteralPath $outputMods -File | Sort-Object Name | ForEach-Object {
    [ordered]@{ name=$_.Name; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash; bytes=$_.Length }
})
$manifest = [ordered]@{
    schemaVersion=1
    result='pass'
    variant='owned-fullscreen-private-target-zero-output'
    purpose='Prove whether an owned zero-output draw is safe when redirected away from the live e2aa render target.'
    source=[ordered]@{ manifest=$sourceManifestPath; manifestSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $sourceManifestPath).Hash }
    hook='e2aa1c8cb39e0a55-ps'
    controls=[ordered]@{ F2='off/on'; F10='native reload, unchanged'; PageUp='unchanged'; PageDown='unchanged' }
    ownedPass=[ordered]@{
        vertexShader='Agent2R3DSSGIFullscreen_vs.hlsl'; vertexInput='SV_VertexID only'; topology='triangle_list'; draw='3, 0'
        depth='disabled'; stencil='disabled'; cull='none'; blend='ADD ONE ONE'; output='literal float4(0,0,0,0)'
        target='private copy_desc of captured target'; writeback='none'
    }
    expectedVisual='Identical to F2 off. A clean result proves the live e2aa target write, not the owned draw, causes white skin.'
    files=$files
    runtimeEligible=$false
    installed=$false
}
$manifestPath = Join-Path $output 'manifest.json'
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 10) + "`r`n"), [Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Result='pass'; Variant=$manifest.variant; Files=$files.Count; Output=$output; RuntimeEligible=$false }
