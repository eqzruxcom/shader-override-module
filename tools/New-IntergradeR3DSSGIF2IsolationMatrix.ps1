[CmdletBinding()]
param(
    [string]$SourceRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-true-noop-isolation'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-isolation-matrix')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$payloadNames = @(
    'Agent2R3DSSGICompositeE2AA_ps.hlsl',
    'Agent2R3DSSGIDenoise16_ps.hlsl',
    'Agent2R3DSSGIDenoise2_ps.hlsl',
    'Agent2R3DSSGIDenoise4_ps.hlsl',
    'Agent2R3DSSGIDenoise8_ps.hlsl',
    'Agent2R3DSSGITest.ini',
    'Agent2R3DSSGITraceE2AA_ps.hlsl'
)

$source = [IO.Path]::GetFullPath($SourceRoot)
$output = [IO.Path]::GetFullPath($OutputRoot)
$sourceMods = Join-Path $source 'Mods'
$fullIniPath = Join-Path $source 'previous-live-Agent2R3DSSGITest.ini'

if (-not (Test-Path -LiteralPath $sourceMods -PathType Container)) { throw "Source Mods directory is missing: $sourceMods" }
if (-not (Test-Path -LiteralPath $fullIniPath -PathType Leaf)) { throw "Full test INI is missing: $fullIniPath" }

$actualNames = @(Get-ChildItem -LiteralPath $sourceMods -File | ForEach-Object Name | Sort-Object)
if (@(Compare-Object ($payloadNames | Sort-Object) $actualNames).Count -ne 0) {
    throw "Source payload is not the exact seven-file set: $($actualNames -join ', ')"
}

$fullIni = Get-Content -Raw -LiteralPath $fullIniPath
$marker = '[ShaderOverrideAgent2R3DSSGIF2Test]'
$markerIndex = $fullIni.IndexOf($marker, [StringComparison]::Ordinal)
if ($markerIndex -lt 0) { throw 'Full INI is missing the expected e2aa override marker.' }
$prefix = $fullIni.Substring(0, $markerIndex)

if ([regex]::Matches($fullIni, '(?im)^\s*key\s*=.*(?<![A-Z0-9_])F2(?![A-Z0-9_]).*$').Count -ne 1 -or
    [regex]::Matches($fullIni, '(?im)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$').Count -ne 1) {
    throw 'Full INI does not have exactly one F2 binding and one e2aa owner.'
}

$commonSave = @(
    '    ResourceAgent2SSGIOriginalT110 = reference ps-t110',
    '    ResourceAgent2SSGIOriginalT111 = reference ps-t111',
    '    ResourceAgent2SSGIOriginalT112 = reference ps-t112',
    '    ResourceAgent2SSGIOriginalT113 = reference ps-t113',
    '    ResourceAgent2SSGIOriginalT114 = reference ps-t114',
    '    ResourceAgent2SSGITarget = reference o0',
    '    ResourceAgent2SSGINormal = reference ps-t0',
    '    ResourceAgent2SSGIDepth = reference ps-t5',
    '    ResourceAgent2SSGIMaterial = reference ps-t1',
    '    ResourceAgent2SSGIAlbedo = reference ps-t2'
)
$commonRestore = @(
    '    ps-t110 = reference ResourceAgent2SSGIOriginalT110',
    '    ps-t111 = reference ResourceAgent2SSGIOriginalT111',
    '    ps-t112 = reference ResourceAgent2SSGIOriginalT112',
    '    ps-t113 = reference ResourceAgent2SSGIOriginalT113',
    '    ps-t114 = reference ResourceAgent2SSGIOriginalT114'
)

$variants = @(
    [ordered]@{ Name='00-true-noop'; Description='F2 toggles 0/1, but condition 2 prevents every command from running.'; Condition=2; Operations=@('    ResourceAgent2SSGIScene = copy o0','    run = CustomShaderAgent2R3DSSGITrace','    run = CustomShaderAgent2R3DSSGIDenoise16','    run = CustomShaderAgent2R3DSSGIDenoise8','    run = CustomShaderAgent2R3DSSGIDenoise4','    run = CustomShaderAgent2R3DSSGIDenoise2','    run = CustomShaderAgent2R3DSSGIComposite') },
    [ordered]@{ Name='01-references-only'; Description='Save/reference/restore commands only; no copy or custom shader runs.'; Condition=1; Operations=@() },
    [ordered]@{ Name='02-scene-copy-only'; Description='Adds only the scene-color copy from o0.'; Condition=1; Operations=@('    ResourceAgent2SSGIScene = copy o0') },
    [ordered]@{ Name='03-trace-only'; Description='Adds the half-resolution trace pass; no denoise or composite.'; Condition=1; Operations=@('    ResourceAgent2SSGIScene = copy o0','    run = CustomShaderAgent2R3DSSGITrace') },
    [ordered]@{ Name='04-trace-denoise'; Description='Adds all four denoise passes; no composite into the game target.'; Condition=1; Operations=@('    ResourceAgent2SSGIScene = copy o0','    run = CustomShaderAgent2R3DSSGITrace','    run = CustomShaderAgent2R3DSSGIDenoise16','    run = CustomShaderAgent2R3DSSGIDenoise8','    run = CustomShaderAgent2R3DSSGIDenoise4','    run = CustomShaderAgent2R3DSSGIDenoise2') },
    [ordered]@{ Name='05-zero-composite'; Description='Runs the complete chain with the diagnostic composite shader returning zero.'; Condition=1; Operations=@('    ResourceAgent2SSGIScene = copy o0','    run = CustomShaderAgent2R3DSSGITrace','    run = CustomShaderAgent2R3DSSGIDenoise16','    run = CustomShaderAgent2R3DSSGIDenoise8','    run = CustomShaderAgent2R3DSSGIDenoise4','    run = CustomShaderAgent2R3DSSGIDenoise2','    run = CustomShaderAgent2R3DSSGIComposite') }
)

$variants += [ordered]@{
    Name='06-zero-composite-no-depth'
    Description='Repeats the zero-output composite with depth testing, depth writes, and stencil explicitly disabled.'
    Condition=1
    DisableCompositeDepth=$true
    Operations=@(
        '    ResourceAgent2SSGIScene = copy o0',
        '    run = CustomShaderAgent2R3DSSGITrace',
        '    run = CustomShaderAgent2R3DSSGIDenoise16',
        '    run = CustomShaderAgent2R3DSSGIDenoise8',
        '    run = CustomShaderAgent2R3DSSGIDenoise4',
        '    run = CustomShaderAgent2R3DSSGIDenoise2',
        '    run = CustomShaderAgent2R3DSSGIComposite'
    )
}

$variants += [ordered]@{
    Name='07-zero-composite-no-draw'
    Description='Enters the zero-output composite and binds its resources, but issues no composite draw.'
    Condition=1
    DisableCompositeDraw=$true
    Operations=@(
        '    ResourceAgent2SSGIScene = copy o0',
        '    run = CustomShaderAgent2R3DSSGITrace',
        '    run = CustomShaderAgent2R3DSSGIDenoise16',
        '    run = CustomShaderAgent2R3DSSGIDenoise8',
        '    run = CustomShaderAgent2R3DSSGIDenoise4',
        '    run = CustomShaderAgent2R3DSSGIDenoise2',
        '    run = CustomShaderAgent2R3DSSGIComposite'
    )
}

if (Test-Path -LiteralPath $output -PathType Container) { [IO.Directory]::Delete($output, $true) }
[IO.Directory]::CreateDirectory($output) | Out-Null

$manifestVariants = [Collections.Generic.List[object]]::new()
foreach ($variant in $variants) {
    $variantRoot = Join-Path $output $variant.Name
    $variantMods = Join-Path $variantRoot 'Mods'
    [IO.Directory]::CreateDirectory($variantMods) | Out-Null

    foreach ($name in $payloadNames | Where-Object { $_ -ne 'Agent2R3DSSGITest.ini' }) {
        [IO.File]::Copy((Join-Path $sourceMods $name), (Join-Path $variantMods $name), $false)
    }

    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add($marker)
    $lines.Add('hash = e2aa1c8cb39e0a55')
    $lines.Add('allow_duplicate_hash = true')
    $lines.Add("; ISOLATION MATRIX: $($variant.Name)")
    $lines.Add("; $($variant.Description)")
    $lines.Add("if `$agent2_ssgi_test == $($variant.Condition)")
    foreach ($line in $commonSave) { $lines.Add($line) }
    foreach ($line in $variant.Operations) { $lines.Add($line) }
    foreach ($line in $commonRestore) { $lines.Add($line) }
    $lines.Add('endif')
    $variantPrefix = $prefix
    if ($variant.Contains('DisableCompositeDepth') -and $variant.DisableCompositeDepth) {
        $compositeNeedle = "[CustomShaderAgent2R3DSSGIComposite]`r`nps = Agent2R3DSSGICompositeE2AA_ps.hlsl`r`nsampler = linear_filter`r`nblend = ADD ONE ONE"
        $compositeReplacement = $compositeNeedle + "`r`ndepth_enable = false`r`ndepth_write_mask = zero`r`nstencil_enable = false"
        if ([regex]::Matches($variantPrefix, [regex]::Escape($compositeNeedle)).Count -ne 1) {
            throw 'Composite section does not match the expected state-isolation insertion point.'
        }
        $variantPrefix = $variantPrefix.Replace($compositeNeedle, $compositeReplacement)
    }
    if ($variant.Contains('DisableCompositeDraw') -and $variant.DisableCompositeDraw) {
        $drawNeedle = "ps-t114 = ResourceAgent2SSGIAlbedo`r`ndraw = from_caller"
        if ([regex]::Matches($variantPrefix, [regex]::Escape($drawNeedle)).Count -ne 1) {
            throw 'Composite section does not match the expected no-draw insertion point.'
        }
        $variantPrefix = $variantPrefix.Replace($drawNeedle, 'ps-t114 = ResourceAgent2SSGIAlbedo')
    }
    $iniText = $variantPrefix.TrimEnd("`r","`n") + "`r`n`r`n" + ($lines -join "`r`n") + "`r`n"
    $iniPath = Join-Path $variantMods 'Agent2R3DSSGITest.ini'
    [IO.File]::WriteAllText($iniPath, $iniText, [Text.UTF8Encoding]::new($false))

    $claims = Get-Content -Raw -LiteralPath $iniPath
    if ([regex]::Matches($claims, '(?im)^\s*key\s*=.*(?<![A-Z0-9_])F2(?![A-Z0-9_]).*$').Count -ne 1 -or
        [regex]::Matches($claims, '(?im)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$').Count -ne 1 -or
        [regex]::Matches($claims, '(?im)^\s*if\s+\$agent2_ssgi_test').Count -ne 1 -or
        [regex]::Matches($claims, '(?im)^\s*endif\s*$').Count -ne 1) {
        throw "Generated control/owner structure is invalid: $($variant.Name)"
    }

    $declaredResources = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($match in [regex]::Matches($claims, '(?im)^\[(Resource[A-Z0-9_]+)\]\s*\r?$')) {
        [void]$declaredResources.Add($match.Groups[1].Value)
    }
    foreach ($match in [regex]::Matches($claims, '(?im)^\s*(Resource[A-Z0-9_]+)\s*=')) {
        if (-not $declaredResources.Contains($match.Groups[1].Value)) {
            throw "Generated operation writes undeclared resource $($match.Groups[1].Value): $($variant.Name)"
        }
    }

    $files = @(Get-ChildItem -LiteralPath $variantMods -File | Sort-Object Name | ForEach-Object {
        [ordered]@{ Name=$_.Name; Sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash; Bytes=$_.Length }
    })
    $manifestVariants.Add([ordered]@{
        Name=$variant.Name
        Description=$variant.Description
        Condition=$variant.Condition
        ExpectedVisual='Identical to native; stop at the first variant that changes Cloud or the scene.'
        Files=$files
    })
}

$manifest = [ordered]@{
    SchemaVersion=1
    Result='pass'
    Purpose='Locate the first resource/state/render operation that changes Cloud while the composite output is zero.'
    Controls=[ordered]@{ F2='off/on'; F10='unchanged 3DMigoto reload key'; PageUp='unchanged'; PageDown='unchanged' }
    Hook='e2aa1c8cb39e0a55-ps'
    Variants=@($manifestVariants)
}
$manifestPath = Join-Path $output 'manifest.json'
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 10) + "`r`n"), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{ Result='pass'; Variants=$variants.Count; Output=$output; Manifest=$manifestPath }
