[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$generator = Join-Path $root 'tools\New-IntergradeR3DSSGIF2OwnerIntegrationPack.ps1'
$owner = Join-Path $root 'runtime\Intergrade\Mods\RebirthEffectsDX11.ini'
$testRoot = Join-Path $root ('artifacts\agent2-r3d-ssgi-f2-pack-test\' + [guid]::NewGuid().ToString('N'))
$first = Join-Path $testRoot 'first'
$second = Join-Path $testRoot 'second'
$testPrefix = [IO.Path]::GetFullPath((Join-Path $root 'artifacts\agent2-r3d-ssgi-f2-pack-test')).TrimEnd('\') + '\'

if (-not ([IO.Path]::GetFullPath($testRoot).StartsWith($testPrefix, [StringComparison]::OrdinalIgnoreCase))) {
    throw 'Test output escaped its dedicated artifact root.'
}

$ownerBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $owner).Hash
try {
    & $generator -OutputDirectory $first | Out-Null
    & $generator -OutputDirectory $second | Out-Null

    $manifestA = Join-Path $first 'manifest.json'
    $manifestB = Join-Path $second 'manifest.json'
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $manifestA).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestB).Hash) {
        throw 'Pack manifests are not deterministic.'
    }

    $filesA = Get-ChildItem -LiteralPath $first -Recurse -File | ForEach-Object {
        [pscustomobject]@{ Relative = [IO.Path]::GetRelativePath($first, $_.FullName); Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash }
    }
    $filesB = @{}
    foreach ($file in Get-ChildItem -LiteralPath $second -Recurse -File) {
        $filesB[[IO.Path]::GetRelativePath($second, $file.FullName)] = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
    }
    foreach ($file in $filesA) {
        if (-not $filesB.ContainsKey($file.Relative) -or $filesB[$file.Relative] -ne $file.Hash) {
            throw "Pack output is not deterministic: $($file.Relative)"
        }
    }
    if ($filesA.Count -ne $filesB.Count) { throw 'Pack output file counts differ.' }

    $ini = Get-Content -Raw -LiteralPath (Join-Path $first 'Mods\RebirthEffectsDX11.ini')
    if ([regex]::Matches($ini, '(?im)^\s*key\s*=\s*no_modifiers\s+F2\s*$').Count -ne 1) { throw 'F2 must be emitted exactly once.' }
    if ([regex]::Matches($ini, '(?im)^\s*key\s*=\s*no_modifiers\s+F1\s*$').Count -ne 0) { throw 'F1 must remain reserved and unbound.' }
    if ([regex]::Matches($ini, '(?im)^\s*key\s*=\s*no_modifiers\s+F3\s*$').Count -ne 1) { throw 'The existing F3 rolling A/B binding was not preserved.' }
    if ($ini -match 'endifif' -or $ini -notmatch '(?m)^endif\r?\nif \$rebirth_ab_current == 0\r?$') {
        throw 'The injected F2 block is not cleanly separated from the preserved rolling A/B branch.'
    }
    if ($ini -notmatch '(?s)if \$agent2_ssgi_test == 1.*?ResourceAgent2SSGIScene = copy o0.*?CustomShaderAgent2R3DSSGITrace.*?CustomShaderAgent2R3DSSGIDenoise16.*?CustomShaderAgent2R3DSSGIDenoise8.*?CustomShaderAgent2R3DSSGIDenoise4.*?CustomShaderAgent2R3DSSGIDenoise2.*?CustomShaderAgent2R3DSSGIComposite.*?endif') {
        throw 'The six-pass F2 pipeline is incomplete or out of order.'
    }
    if ($ini -match '(?im)^\s*Resource\w+\s*=\s*(?:copy|reference)\s+rt\d+\s*$') {
        throw 'Invalid 3DMigoto render-target alias found: command-list render targets must use oN, not rtN.'
    }
    $overrideSection = [regex]::Match($ini, '(?ms)^\[ShaderOverrideRebirthABShared\]\r?\n(?<body>.*?)(?=^\[|\z)')
    if (-not $overrideSection.Success) { throw 'The shared e2aa owner override is missing.' }
    $overrideBody = $overrideSection.Groups['body'].Value
    $compositeRunIndex = $overrideBody.IndexOf('run = CustomShaderAgent2R3DSSGIComposite')
    $f2EndIndex = $overrideBody.IndexOf('endif', $compositeRunIndex)
    foreach ($slot in @(110, 111, 112, 113, 114)) {
        $backupResource = "ResourceAgent2SSGIOriginalT$slot"
        if ([regex]::Matches($ini, "(?m)^\[$([regex]::Escape($backupResource))\]\r?$").Count -ne 1) {
            throw "High SRV backup resource must be declared exactly once: $backupResource"
        }
        $backup = "$backupResource = reference ps-t$slot"
        $restore = "ps-t$slot = reference $backupResource"
        if ([regex]::Matches($overrideBody, '(?m)^\s*' + [regex]::Escape($backup) + '\s*$').Count -ne 1) {
            throw "High SRV slot backup must occur exactly once: $backup"
        }
        if ([regex]::Matches($overrideBody, '(?m)^\s*' + [regex]::Escape($restore) + '\s*$').Count -ne 1) {
            throw "High SRV slot restoration must occur exactly once: $restore"
        }
        $backupIndex = $overrideBody.IndexOf($backup)
        $restoreIndex = $overrideBody.IndexOf($restore)
        if ($backupIndex -lt 0 -or $backupIndex -gt $overrideBody.IndexOf('run = CustomShaderAgent2R3DSSGITrace') -or $restoreIndex -le $compositeRunIndex -or $restoreIndex -ge $f2EndIndex) {
            throw "High SRV slot $slot is not preserved around the complete F2 pipeline."
        }
    }
    foreach ($sectionName in @('Trace', 'Denoise16', 'Denoise8', 'Denoise4', 'Denoise2', 'Composite')) {
        $section = [regex]::Match($ini, "(?ms)^\[CustomShaderAgent2R3DSSGI$sectionName\]\r?\n(?<body>.*?)(?=^\[|\z)")
        if (-not $section.Success -or $section.Groups['body'].Value -match '(?im)^\s*handling\s*=\s*skip\s*$') {
            throw "Injected prepass $sectionName is missing or suppresses the native/owner e2aa draw."
        }
        if ($section.Groups['body'].Value -notmatch '(?im)^\s*sampler\s*=\s*linear_filter\s*$') {
            throw "Injected prepass $sectionName does not explicitly use the restored linear-clamp sampler."
        }
    }
    $compositeSection = [regex]::Match($ini, '(?ms)^\[CustomShaderAgent2R3DSSGIComposite\]\r?\n(?<body>.*?)(?=^\[|\z)')
    foreach ($binding in @(
        'ps-t110 = ResourceAgent2SSGIPing',
        'ps-t111 = ResourceAgent2SSGINormal',
        'ps-t112 = ResourceAgent2SSGIDepth',
        'ps-t113 = ResourceAgent2SSGIMaterial',
        'ps-t114 = ResourceAgent2SSGIAlbedo',
        'post ps-t110 = null', 'post ps-t111 = null', 'post ps-t112 = null', 'post ps-t113 = null', 'post ps-t114 = null'
    )) {
        if (-not $compositeSection.Success -or $compositeSection.Groups['body'].Value -notmatch ('(?im)^\s*' + [regex]::Escape($binding) + '\s*$')) {
            throw "Composite binding/cleanup is missing: $binding"
        }
    }
    foreach ($reference in @(
        'ResourceAgent2SSGIMaterial = reference ps-t1',
        'ResourceAgent2SSGIAlbedo = reference ps-t2'
    )) {
        if ($ini -notmatch ('(?im)^\s*' + [regex]::Escape($reference) + '\s*$')) { throw "Native e2aa input reference is missing: $reference" }
    }
    $traceShader = Get-Content -Raw -LiteralPath (Join-Path $first 'Mods\Agent2R3DSSGITraceE2AA_ps.hlsl')
    $denoiseShader = Get-Content -Raw -LiteralPath (Join-Path $first 'Mods\Agent2R3DSSGIDenoise16_ps.hlsl')
    foreach ($source in @($traceShader, $denoiseShader)) {
        if ($source -notmatch 'centerDepth\s*<=\s*AGENT2_DEPTH_CLEAR_EPSILON' -or $source -notmatch 'sampleDepth\s*<=\s*AGENT2_DEPTH_CLEAR_EPSILON') {
            throw 'Trace and denoise shaders must reject the captured 0.0 reversed-Z clear value.'
        }
        if ($source -match '(?:centerDepth|sampleDepth)\s*>=\s*0\.999999') {
            throw 'A forward-Z 1.0 background rejection regressed into the Remake adapter.'
        }
    }
    if ($traceShader -notmatch 'Agent2SceneDepth\.Load\(' -or $traceShader -notmatch 'sampleDepth\s*=\s*Agent2SceneDepth\.SampleLevel') {
        throw 'Trace sampling must point-fetch receiver depth while preserving filtered neighbor tracing.'
    }
    foreach ($pattern in @('Agent2DenoiseDepth\.Load\(', 'Agent2DenoiseNormal\.Load\(', 'Agent2DenoiseSource\.Load\(')) {
        if ($denoiseShader -notmatch $pattern) { throw "A-trous point-fetch contract is missing: $pattern" }
    }
    if ($denoiseShader -match 'Agent2Denoise(?:Source|Normal|Depth)\.SampleLevel') {
        throw 'A-trous geometry/source taps must not be linearly filtered across silhouettes.'
    }
    $compositeShader = Get-Content -Raw -LiteralPath (Join-Path $first 'Mods\Agent2R3DSSGICompositeE2AA_ps.hlsl')
    foreach ($pattern in @(
        'AGENT2_UPSAMPLE_DEPTH_TOLERANCE_METERS\s*=\s*0\.05',
        'Agent2AccumulateUpsampleTap\(p00', 'Agent2AccumulateUpsampleTap\(p10',
        'Agent2AccumulateUpsampleTap\(p01', 'Agent2AccumulateUpsampleTap\(p11',
        'receiverDiffuse\s*=\s*albedo \* \(1\.0 - metallic\) \* AGENT2_INV_PI'
    )) {
        if ($compositeShader -notmatch $pattern) { throw "Depth-aware diffuse composite contract is missing: $pattern" }
    }
    $manifest = Get-Content -Raw -LiteralPath $manifestA | ConvertFrom-Json
    if ($manifest.compile.Count -ne 6 -or $manifest.effect.depthClear -ne 0.0 -or $manifest.effect.depthConvention -ne 'captured reversed-Z' -or $manifest.effect.sampling -ne 'point receiver depth; linear trace neighbors/radiance; point A-trous taps' -or $manifest.effect.upsample -ne 'four-tap reconstructed-depth bilateral, 0.05 meter tolerance' -or $manifest.effect.receiverDiffuse -ne 'e2aa t2.rgb * (1 - e2aa t1.x metallic) / pi' -or (@($manifest.effect.highSrvSlotsRestored) -join ',') -ne '110,111,112,113,114' -or $manifest.policy.runtimeEligible -or $manifest.policy.installed -or $manifest.policy.gameFilesTouched) {
        throw 'Pack policy or compile count is unsafe.'
    }

    $ownerAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $owner).Hash
    if ($ownerAfter -ne $ownerBefore) { throw 'Shared runtime owner changed during offline generation.' }

    [pscustomobject]@{
        result = 'pass'
        deterministicFiles = $filesA.Count
        shadersCompiled = $manifest.compile.Count
        ownerUnchanged = $true
        F1Reserved = $true
        F2TestToggle = $true
        F3Preserved = $true
        highSrvSlotsRestored = $true
        runtimeEligible = $false
        installed = $false
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        [IO.Directory]::Delete([IO.Path]::GetFullPath($testRoot), $true)
    }
}
