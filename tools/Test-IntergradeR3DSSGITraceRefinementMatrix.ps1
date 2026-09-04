[CmdletBinding()]
param(
    [string]$MatrixRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-trace-refinement-matrix')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$matrix = [IO.Path]::GetFullPath($MatrixRoot).TrimEnd('\')
if (-not $matrix.StartsWith($workspace + '\',[StringComparison]::OrdinalIgnoreCase)) {
    throw "Trace-refinement matrix escaped the workspace: $matrix"
}
$manifestPath = Join-Path $matrix 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Manifest is missing: $manifestPath" }
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json

$expected = [ordered]@{
    '00-descriptor-only'  = [ordered]@{Run=$false;Draw=$false;Ps='Agent2R3DSSGITraceE2AA_ps.hlsl';Setup=$false;OverrideDescriptor=$true}
    '01-custom-bind-only' = [ordered]@{Run=$true; Draw=$false;Ps='Agent2R3DSSGITraceE2AA_ps.hlsl';Setup=$false;OverrideDescriptor=$false}
    '02-setup-no-draw'    = [ordered]@{Run=$true; Draw=$false;Ps='Agent2R3DSSGITraceE2AA_ps.hlsl';Setup=$true; OverrideDescriptor=$false}
    '03-zero-output-draw' = [ordered]@{Run=$true; Draw=$true; Ps='Agent2R3DSSGITraceZero_ps.hlsl';Setup=$true; OverrideDescriptor=$false}
    '04-real-trace-draw'  = [ordered]@{Run=$true; Draw=$true; Ps='Agent2R3DSSGITraceE2AA_ps.hlsl';Setup=$true; OverrideDescriptor=$false}
}

if ($manifest.SchemaVersion -ne 1 -or $manifest.Result -ne 'pass' -or
    $manifest.Hook -ne 'e2aa1c8cb39e0a55-ps' -or
    $manifest.ParentMatrix -ne 'agent2-r3d-ssgi-f2-isolation-matrix/03-trace-only' -or
    $manifest.Controls.F2 -ne 'off/on' -or
    $manifest.Controls.F10 -ne 'unchanged 3DMigoto reload key' -or
    [string]$manifest.LiveDeployment -notmatch '^forbidden until') {
    throw 'Trace-refinement manifest contract is invalid.'
}
$actualNames = @($manifest.Variants | ForEach-Object Name)
if (@(Compare-Object @($expected.Keys) $actualNames -SyncWindow 0).Count -ne 0) {
    throw "Variant set/order is invalid: $($actualNames -join ', ')"
}

$rows = [Collections.Generic.List[object]]::new()
foreach ($variant in @($manifest.Variants)) {
    $name = [string]$variant.Name
    $contract = $expected[$name]
    $mods = Join-Path (Join-Path $matrix $name) 'Mods'
    $actualFiles = @(Get-ChildItem -LiteralPath $mods -File | Sort-Object Name)
    if ($actualFiles.Count -ne 8 -or @($variant.Files).Count -ne 8) {
        throw "$name does not contain the exact eight-file diagnostic payload."
    }
    foreach ($file in @($variant.Files)) {
        $path = Join-Path $mods ([string]$file.Name)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$file.Sha256 -or
            (Get-Item -LiteralPath $path).Length -ne [long]$file.Bytes) {
            throw "$name payload failed manifest verification: $($file.Name)"
        }
    }

    $iniPath = Join-Path $mods 'Agent2R3DSSGITest.ini'
    $ini = Get-Content -Raw -LiteralPath $iniPath
    if ([regex]::Matches($ini,'(?im)^\s*key\s*=.*(?<![A-Z0-9_])F2(?![A-Z0-9_]).*$').Count -ne 1 -or
        $ini -match '(?im)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F10(?![A-Z0-9_]).*$' -or
        $ini -match '(?im)^\s*key\s*=.*(?:PAGE_UP|PAGE_DOWN|VK_PRIOR|VK_NEXT).*$' -or
        [regex]::Matches($ini,'(?im)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$').Count -ne 1 -or
        [regex]::Matches($ini,'(?im)^\s*if\s+\$agent2_ssgi_test\s*==\s*1\s*$').Count -ne 1 -or
        [regex]::Matches($ini,'(?im)^\s*endif\s*$').Count -ne 1) {
        throw "$name key/owner/conditional structure is invalid."
    }

    $traceMatch = [regex]::Match($ini,'(?ms)^\[CustomShaderAgent2R3DSSGITrace\]\r?\n(?<body>.*?)(?=^\[CustomShaderAgent2R3DSSGIDenoise16\]\r?$)')
    $overrideMatch = [regex]::Match($ini,'(?ms)^\[ShaderOverrideAgent2R3DSSGIF2Test\]\r?\n(?<body>.*)$')
    if (-not $traceMatch.Success -or -not $overrideMatch.Success) { throw "$name section extraction failed." }
    $trace = $traceMatch.Groups['body'].Value
    $override = $overrideMatch.Groups['body'].Value

    $psMatches = [regex]::Matches($trace,'(?im)^\s*ps\s*=\s*(?<file>\S+)\s*$')
    if ($psMatches.Count -ne 1 -or $psMatches[0].Groups['file'].Value -ne $contract.Ps) {
        throw "$name binds the wrong trace pixel shader."
    }
    $hasRun = [regex]::Matches($override,'(?im)^\s*run\s*=\s*CustomShaderAgent2R3DSSGITrace\s*$').Count -eq 1
    $hasDraw = [regex]::Matches($trace,'(?im)^\s*draw\s*=\s*from_caller\s*$').Count -eq 1
    $hasSetup = @(
        'run\s*=\s*BuiltInCommandListUnbindAllRenderTargets',
        'ResourceAgent2SSGIPing\s*=\s*copy_desc\s+ResourceAgent2SSGITarget',
        'o0\s*=\s*set_viewport\s+ResourceAgent2SSGIPing',
        'ps-t110\s*=\s*ResourceAgent2SSGIScene',
        'ps-t111\s*=\s*ResourceAgent2SSGINormal',
        'ps-t112\s*=\s*ResourceAgent2SSGIDepth'
    ) | ForEach-Object { $trace -match ('(?im)^\s*' + $_ + '\s*$') }
    $setupComplete = @($hasSetup | Where-Object { $_ }).Count -eq 6
    $setupEmpty = @($hasSetup | Where-Object { $_ }).Count -eq 0
    $hasOverrideDescriptor = [regex]::Matches($override,'(?im)^\s*ResourceAgent2SSGIPing\s*=\s*copy_desc\s+ResourceAgent2SSGITarget\s*$').Count -eq 1

    if ($hasRun -ne [bool]$contract.Run -or $hasDraw -ne [bool]$contract.Draw -or
        $hasOverrideDescriptor -ne [bool]$contract.OverrideDescriptor -or
        ([bool]$contract.Setup -and -not $setupComplete) -or
        (-not [bool]$contract.Setup -and -not $setupEmpty)) {
        throw "$name does not isolate its declared trace boundary."
    }

    $rows.Add([ordered]@{
        Variant=$name
        Run=$hasRun
        Setup=$setupComplete
        Draw=$hasDraw
        PixelShader=[string]$contract.Ps
        Verified=$true
    })
}

$zeroPath = Join-Path (Join-Path (Join-Path $matrix '03-zero-output-draw') 'Mods') 'Agent2R3DSSGITraceZero_ps.hlsl'
$zero = Get-Content -Raw -LiteralPath $zeroPath
if ($zero -notmatch '(?s)float4\s+main\s*\(.*?\)\s*:\s*SV_Target0\s*\{\s*return\s+0\.0\.xxxx\s*;\s*\}') {
    throw 'Zero-output trace shader is not a literal-zero diagnostic.'
}

[pscustomobject]@{
    Result='pass'
    VariantsVerified=$rows.Count
    Controls='F2 only; F10/PageUp/PageDown unbound'
    LiveFilesChanged=0
    Rows=@($rows)
}
