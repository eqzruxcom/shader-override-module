[CmdletBinding()]
param(
    [string]$SourceMatrixRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-isolation-matrix'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-trace-refinement-matrix')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$source = [IO.Path]::GetFullPath($SourceMatrixRoot).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
foreach ($path in @($source,$output)) {
    if (-not $path.StartsWith($workspace + '\',[StringComparison]::OrdinalIgnoreCase)) {
        throw "Trace-refinement path escaped the workspace: $path"
    }
}

$sourceMods = Join-Path $source '03-trace-only\Mods'
$sourceManifestPath = Join-Path $source 'manifest.json'
$sourceIniPath = Join-Path $sourceMods 'Agent2R3DSSGITest.ini'
foreach ($path in @($sourceManifestPath,$sourceIniPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required source is missing: $path" }
}

$sourceManifest = Get-Content -Raw -LiteralPath $sourceManifestPath | ConvertFrom-Json
if ($sourceManifest.SchemaVersion -ne 1 -or $sourceManifest.Result -ne 'pass' -or
    $sourceManifest.Hook -ne 'e2aa1c8cb39e0a55-ps' -or
    $sourceManifest.Controls.F2 -ne 'off/on' -or
    $sourceManifest.Controls.F10 -ne 'unchanged 3DMigoto reload key') {
    throw 'Source isolation-matrix contract is invalid.'
}
$sourceEntry = @($sourceManifest.Variants | Where-Object Name -eq '03-trace-only')
if ($sourceEntry.Count -ne 1) { throw 'Source trace-only variant is missing or ambiguous.' }
foreach ($file in @($sourceEntry[0].Files)) {
    $path = Join-Path $sourceMods ([string]$file.Name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$file.Sha256 -or
        (Get-Item -LiteralPath $path).Length -ne [long]$file.Bytes) {
        throw "Source trace-only payload failed manifest verification: $($file.Name)"
    }
}

$sourceIni = Get-Content -Raw -LiteralPath $sourceIniPath
$overrideMarker = '[ShaderOverrideAgent2R3DSSGIF2Test]'
$markerIndex = $sourceIni.IndexOf($overrideMarker,[StringComparison]::Ordinal)
if ($markerIndex -lt 0) { throw 'Source INI is missing the expected e2aa override.' }
$prefix = $sourceIni.Substring(0,$markerIndex)
$tracePattern = '(?ms)^\[CustomShaderAgent2R3DSSGITrace\]\r?\n.*?(?=^\[CustomShaderAgent2R3DSSGIDenoise16\]\r?$)'
if ([regex]::Matches($prefix,$tracePattern).Count -ne 1) { throw 'Source INI does not contain one replaceable trace CustomShader section.' }

$zeroShaderName = 'Agent2R3DSSGITraceZero_ps.hlsl'
$zeroShader = @'
/*
 * Diagnostic only: preserve the trace-pass invocation and caller geometry while
 * proving whether the real trace math is responsible for a visible side effect.
 */
struct FullscreenInput
{
    float4 uvAndRay : TEXCOORD0;
    float4 position : SV_Position;
};

float4 main(FullscreenInput input) : SV_Target0
{
    return 0.0.xxxx;
}
'@

$traceBodyBindOnly = @'
[CustomShaderAgent2R3DSSGITrace]
ps = Agent2R3DSSGITraceE2AA_ps.hlsl

'@
$traceBodySetupNoDraw = @'
[CustomShaderAgent2R3DSSGITrace]
ps = Agent2R3DSSGITraceE2AA_ps.hlsl
sampler = linear_filter
blend = disable
run = BuiltInCommandListUnbindAllRenderTargets
ResourceAgent2SSGIPing = copy_desc ResourceAgent2SSGITarget
o0 = set_viewport ResourceAgent2SSGIPing
ps-t110 = ResourceAgent2SSGIScene
ps-t111 = ResourceAgent2SSGINormal
ps-t112 = ResourceAgent2SSGIDepth
post ps-t110 = null
post ps-t111 = null
post ps-t112 = null

'@
$traceBodyZeroDraw = @"
[CustomShaderAgent2R3DSSGITrace]
ps = $zeroShaderName
sampler = linear_filter
blend = disable
run = BuiltInCommandListUnbindAllRenderTargets
ResourceAgent2SSGIPing = copy_desc ResourceAgent2SSGITarget
o0 = set_viewport ResourceAgent2SSGIPing
ps-t110 = ResourceAgent2SSGIScene
ps-t111 = ResourceAgent2SSGINormal
ps-t112 = ResourceAgent2SSGIDepth
draw = from_caller
post ps-t110 = null
post ps-t111 = null
post ps-t112 = null

"@
$traceBodyRealDraw = @'
[CustomShaderAgent2R3DSSGITrace]
ps = Agent2R3DSSGITraceE2AA_ps.hlsl
sampler = linear_filter
blend = disable
run = BuiltInCommandListUnbindAllRenderTargets
ResourceAgent2SSGIPing = copy_desc ResourceAgent2SSGITarget
o0 = set_viewport ResourceAgent2SSGIPing
ps-t110 = ResourceAgent2SSGIScene
ps-t111 = ResourceAgent2SSGINormal
ps-t112 = ResourceAgent2SSGIDepth
draw = from_caller
post ps-t110 = null
post ps-t111 = null
post ps-t112 = null

'@

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
    [ordered]@{
        Name='00-descriptor-only'
        Description='Known-clean references and scene copy, then allocate the half-resolution trace descriptor without invoking a CustomShader.'
        Boundary='ResourceAgent2SSGIPing copy_desc allocation'
        TraceBody=$traceBodyBindOnly
        Operations=@('    ResourceAgent2SSGIScene = copy o0','    ResourceAgent2SSGIPing = copy_desc ResourceAgent2SSGITarget')
    },
    [ordered]@{
        Name='01-custom-bind-only'
        Description='Compile/bind the real trace pixel shader through CustomShader entry/exit, but do not alter targets, resources, or draw.'
        Boundary='CustomShader entry/exit and real trace-PS binding'
        TraceBody=$traceBodyBindOnly
        Operations=@('    ResourceAgent2SSGIScene = copy o0','    run = CustomShaderAgent2R3DSSGITrace')
    },
    [ordered]@{
        Name='02-setup-no-draw'
        Description='Apply trace target, viewport, sampler, blend, and SRV state inside the CustomShader, but issue no draw.'
        Boundary='Trace render-state setup and restoration'
        TraceBody=$traceBodySetupNoDraw
        Operations=@('    ResourceAgent2SSGIScene = copy o0','    run = CustomShaderAgent2R3DSSGITrace')
    },
    [ordered]@{
        Name='03-zero-output-draw'
        Description='Issue the caller draw into the offscreen trace target using a literal-zero pixel shader.'
        Boundary='Inherited caller geometry and draw invocation'
        TraceBody=$traceBodyZeroDraw
        Operations=@('    ResourceAgent2SSGIScene = copy o0','    run = CustomShaderAgent2R3DSSGITrace')
    },
    [ordered]@{
        Name='04-real-trace-draw'
        Description='Issue the same offscreen draw with the real R3D trace shader.'
        Boundary='R3D trace sampling and math'
        TraceBody=$traceBodyRealDraw
        Operations=@('    ResourceAgent2SSGIScene = copy o0','    run = CustomShaderAgent2R3DSSGITrace')
    }
)

if (Test-Path -LiteralPath $output -PathType Container) { [IO.Directory]::Delete($output,$true) }
[IO.Directory]::CreateDirectory($output) | Out-Null
$manifestVariants = [Collections.Generic.List[object]]::new()

foreach ($variant in $variants) {
    $variantMods = Join-Path (Join-Path $output $variant.Name) 'Mods'
    [IO.Directory]::CreateDirectory($variantMods) | Out-Null

    foreach ($file in @($sourceEntry[0].Files | Where-Object Name -ne 'Agent2R3DSSGITest.ini')) {
        [IO.File]::Copy((Join-Path $sourceMods ([string]$file.Name)),(Join-Path $variantMods ([string]$file.Name)),$false)
    }
    [IO.File]::WriteAllText((Join-Path $variantMods $zeroShaderName),$zeroShader.TrimStart("`r","`n") + "`r`n",[Text.UTF8Encoding]::new($false))

    $variantPrefix = [regex]::Replace($prefix,$tracePattern,[string]$variant.TraceBody)
    $override = [Collections.Generic.List[string]]::new()
    $override.Add($overrideMarker)
    $override.Add('hash = e2aa1c8cb39e0a55')
    $override.Add('allow_duplicate_hash = true')
    $override.Add("; TRACE REFINEMENT: $($variant.Name)")
    $override.Add("; $($variant.Description)")
    $override.Add('if $agent2_ssgi_test == 1')
    foreach ($line in $commonSave) { $override.Add($line) }
    foreach ($line in $variant.Operations) { $override.Add($line) }
    foreach ($line in $commonRestore) { $override.Add($line) }
    $override.Add('endif')

    $iniText = $variantPrefix.TrimEnd("`r","`n") + "`r`n`r`n" + ($override -join "`r`n") + "`r`n"
    $iniPath = Join-Path $variantMods 'Agent2R3DSSGITest.ini'
    [IO.File]::WriteAllText($iniPath,$iniText,[Text.UTF8Encoding]::new($false))

    $claims = Get-Content -Raw -LiteralPath $iniPath
    if ([regex]::Matches($claims,'(?im)^\s*key\s*=.*(?<![A-Z0-9_])F2(?![A-Z0-9_]).*$').Count -ne 1 -or
        $claims -match '(?im)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F10(?![A-Z0-9_]).*$' -or
        [regex]::Matches($claims,'(?im)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$').Count -ne 1 -or
        [regex]::Matches($claims,'(?im)^\s*if\s+\$agent2_ssgi_test').Count -ne 1 -or
        [regex]::Matches($claims,'(?im)^\s*endif\s*$').Count -ne 1) {
        throw "Generated control/owner structure is invalid: $($variant.Name)"
    }

    $drawCount = [regex]::Matches($claims,'(?im)^\s*draw\s*=\s*from_caller\s*$').Count
    # The four dormant denoise sections plus the dormant composite section retain
    # five draw directives in every file. Only the two trace-draw variants add a
    # sixth draw, and none of those dormant sections is invoked by this matrix.
    $expectedDrawCount = if ($variant.Name -in @('03-zero-output-draw','04-real-trace-draw')) { 6 } else { 5 }
    if ($drawCount -ne $expectedDrawCount) {
        throw "Generated trace draw boundary is invalid for $($variant.Name): expected $expectedDrawCount total draws, found $drawCount"
    }

    $files = @(Get-ChildItem -LiteralPath $variantMods -File | Sort-Object Name | ForEach-Object {
        [ordered]@{Name=$_.Name;Sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash;Bytes=$_.Length}
    })
    $manifestVariants.Add([ordered]@{
        Name=$variant.Name
        Description=$variant.Description
        Boundary=$variant.Boundary
        ExpectedVisual='Identical to F2 off; stop at the first variant that changes Cloud, lights, or the scene.'
        Files=$files
    })
}

$manifest = [ordered]@{
    SchemaVersion=1
    Result='pass'
    Purpose='Refine the first trace-only failure into descriptor, CustomShader, state, draw, or trace-math ownership.'
    ParentMatrix='agent2-r3d-ssgi-f2-isolation-matrix/03-trace-only'
    Controls=[ordered]@{F2='off/on';F10='unchanged 3DMigoto reload key';PageUp='unchanged';PageDown='unchanged'}
    Hook='e2aa1c8cb39e0a55-ps'
    LiveDeployment='forbidden until 03-trace-only is visually confirmed as the first failing parent variant'
    Variants=@($manifestVariants)
}
$manifestPath = Join-Path $output 'manifest.json'
[IO.File]::WriteAllText($manifestPath,(($manifest | ConvertTo-Json -Depth 10) + "`r`n"),[Text.UTF8Encoding]::new($false))

[pscustomobject]@{Result='pass';Variants=$variants.Count;Output=$output;Manifest=$manifestPath;LiveFilesChanged=0}
