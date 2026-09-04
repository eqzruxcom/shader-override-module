[CmdletBinding()]
param(
    [string]$PackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-temporal-history-pack')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifactsRoot = Join-Path $workspace 'artifacts'
$pack = [IO.Path]::GetFullPath($PackRoot).TrimEnd('\')
if (-not $pack.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'PackRoot must remain below workspace artifacts.'
}

$manifestPath = Join-Path $pack 'manifest.json'
$iniPath = Join-Path $pack 'Mods\Agent2R3DSSGITest.ini'
$temporalPath = Join-Path $pack 'Mods\Agent2R3DSSGITemporalHistory_ps.hlsl'
$commandListHeaderPath = Join-Path $workspace 'src\Backends\3DmigotoFork\DirectX11\CommandList.h'
$commandListPath = Join-Path $workspace 'src\Backends\3DmigotoFork\DirectX11\CommandList.cpp'
foreach ($path in @($manifestPath, $iniPath, $temporalPath, $commandListHeaderPath, $commandListPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file is missing: $path" }
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.result -ne 'pass' -or
    $manifest.variant -ne 'private-temporal-indirect-history' -or
    [bool]$manifest.runtimeEligible -or
    [bool]$manifest.installed -or
    [bool]$manifest.liveTestsPerformed) {
    throw 'Temporal-history manifest state is invalid.'
}
if ([int]$manifest.validation.compiledShaderCount -ne 8 -or
    [bool]$manifest.validation.nativeShaderReplacementIncluded -or
    -not [bool]$manifest.validation.exactNativeOffPath -or
    -not [bool]$manifest.validation.deterministicInitialization -or
    -not [bool]$manifest.validation.resolutionRecreationClear -or
    -not [bool]$manifest.validation.finishedSceneFeedbackAbsent -or
    -not [bool]$manifest.validation.motionSignLiveValidationPending) {
    throw 'Temporal-history validation contract is invalid.'
}
if (Test-Path -LiteralPath (Join-Path $pack 'ShaderFixes')) {
    throw 'Temporal-history pack must not contain native shader replacements.'
}

$sourceManifestPath = [string]$manifest.source.preTemporalManifest
if (-not (Test-Path -LiteralPath $sourceManifestPath -PathType Leaf) -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceManifestPath).Hash -ne
        [string]$manifest.source.preTemporalManifestSha256) {
    throw 'Pinned pre-temporal source manifest is missing or drifted.'
}
$trackedTemporalPath = [string]$manifest.source.temporalShader
if (-not (Test-Path -LiteralPath $trackedTemporalPath -PathType Leaf) -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $trackedTemporalPath).Hash -ne
        [string]$manifest.source.temporalShaderSha256) {
    throw 'Tracked temporal shader source is missing or drifted.'
}

$header = [IO.File]::ReadAllText($commandListHeaderPath)
$implementation = [IO.File]::ReadAllText($commandListPath)
foreach ($required in @(
    'CLEAR_ON_CREATE = 0x00000800',
    '{L"clear_on_create", ResourceCopyOptions::CLEAR_ON_CREATE}'
)) {
    if (-not $header.Contains($required)) { throw "clear_on_create header contract lacks: $required" }
}
foreach ($required in @(
    '!(operation->options & ResourceCopyOptions::COPY_DESC)',
    'if (resource_recreated && (options & ResourceCopyOptions::CLEAR_ON_CREATE))',
    'return res != NULL;'
)) {
    if (-not $implementation.Contains($required)) { throw "clear_on_create implementation lacks: $required" }
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $commandListHeaderPath).Hash -ne
        [string]$manifest.engine.clearOnCreateHeaderSha256 -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $commandListPath).Hash -ne
        [string]$manifest.engine.clearOnCreateImplementationSha256) {
    throw 'The wrapper source changed after the pack recorded clear_on_create.'
}

$ini = [IO.File]::ReadAllText($iniPath).Replace("`r`n", "`n")
foreach ($required in @(
    '[ResourceAgent2SSGIHistory]',
    'format = R16G16B16A16_FLOAT',
    'width_multiply = 0.5',
    'height_multiply = 0.5',
    'bind_flags = shader_resource render_target',
    '[CustomShaderAgent2R3DSSGITemporalHistory]',
    'ResourceAgent2SSGITemporalScratch = copy_desc ResourceAgent2SSGIHistory',
    'ps-t111 = ResourceAgent2SSGIHistory',
    'ps-t113 = ResourceAgent2SSGIMotion',
    'post ResourceAgent2SSGIHistory = copy ResourceAgent2SSGITemporalScratch',
    'ResourceAgent2SSGIHistory = copy_desc clear_on_create ps-t2',
    'clear = ResourceAgent2SSGIHistory 0.0',
    'ResourceAgent2SSGIMotion = reference ps-t4',
    'run = CustomShaderAgent2R3DSSGITemporalHistory',
    'ps-t110 = ResourceAgent2SSGITemporalScratch',
    'key = no_modifiers F2',
    'post ps-t2 = reference ResourceAgent2SSGIOriginalT2'
)) {
    if (-not $ini.Contains($required)) { throw "INI contract is missing: $required" }
}
foreach ($forbidden in @(
    'ResourceAgent2SSGITarget = reference o0',
    'ResourceAgent2SSGIScene = copy o0',
    'ResourceAgent2SSGIHistory = copy o0',
    'ResourceAgent2SSGIHistory = reference o0',
    'hash = af6cd28a0108a18a'
)) {
    if ($ini.Contains($forbidden)) { throw "Finished-scene feedback or obsolete hook survived: $forbidden" }
}
if ($ini -match '(?im)^\s*key\s*=.*(?:F10|VK_PRIOR|VK_NEXT).*$') {
    throw 'Reserved key binding is present.'
}
if ([regex]::Matches($ini, '(?im)^\s*key\s*=.*F2\s*$').Count -ne 1) {
    throw 'F2 must have exactly one binding.'
}
if ([regex]::Matches($ini, '(?im)^\s*clear\s*=\s*ResourceAgent2SSGIHistory\s+0\.0\s*$').Count -ne 1) {
    throw 'F2 OFF must have exactly one deterministic history clear.'
}

$temporal = [IO.File]::ReadAllText($temporalPath).Replace("`r`n", "`n")
foreach ($required in @(
    'Texture2D<float4> RemakeCurrentIndirect : register(t110);',
    'Texture2D<float4> RemakePreviousIndirectDepth : register(t111);',
    'Texture2D<float> RemakeSceneDepth : register(t112);',
    'Texture2D<float4> RemakeEncodedMotion : register(t113);',
    'float4 RemakeViewData[140];',
    'float2 encoded = encodedMotion.zx;',
    'encoded - REMAKE_MOTION_CENTER',
    'abs(previous.a - currentDepthKey) <= REMAKE_HISTORY_DEPTH_THRESHOLD',
    'float3 decayedHistory = saturate(previous.rgb) * REMAKE_HISTORY_DECAY;',
    'return float4(saturate(resolvedIndirect), currentDepthKey);'
)) {
    if (-not $temporal.Contains($required)) { throw "Temporal shader contract is missing: $required" }
}
foreach ($forbidden in @(
    'Texture2D<float4> RemakeFinishedScene',
    'register(t2)',
    'register(t3)',
    'register(t4)'
)) {
    if ($temporal.Contains($forbidden)) { throw "Temporal shader directly consumes a forbidden native scene/history slot: $forbidden" }
}

$compiled = @($manifest.compile)
if ($compiled.Count -ne 8) { throw 'Compile receipt must contain eight shaders.' }
foreach ($entry in $compiled) {
    $base = [IO.Path]::GetFileNameWithoutExtension([string]$entry.name)
    $hlsl = Join-Path $pack ('Mods\' + [string]$entry.name)
    $binary = Join-Path $pack ('compile-verification\' + $base + '.bin')
    $assembly = Join-Path $pack ('compile-verification\' + $base + '.asm')
    foreach ($path in @($hlsl, $binary, $assembly)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Compile artifact is missing: $path" }
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $hlsl).Hash -ne [string]$entry.hlslSha256 -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $binary).Hash -ne [string]$entry.dxbcSha256 -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $assembly).Hash -ne [string]$entry.assemblySha256) {
        throw "Compile artifact drifted: $($entry.name)"
    }
}

$payload = @($manifest.files)
if ($payload.Count -ne 9) { throw "Expected nine Mods payload files; found $($payload.Count)." }
foreach ($entry in $payload) {
    $path = Join-Path $pack ('Mods\' + [string]$entry.name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$entry.sha256) {
        throw "Payload file drifted: $($entry.name)"
    }
}

function Invoke-TemporalModel {
    param(
        [double[]]$Current,
        [double[]]$Previous,
        [double]$CurrentDepthKey,
        [double]$PreviousDepthKey,
        [bool]$InsideHistory = $true
    )
    if ($CurrentDepthKey -le 0.0) { return [double[]]@(0.0, 0.0, 0.0, 0.0) }
    $valid = $InsideHistory -and $PreviousDepthKey -gt 0.0 -and
        [math]::Abs($PreviousDepthKey - $CurrentDepthKey) -le 0.12
    if (-not $valid) { return [double[]]@($Current[0], $Current[1], $Current[2], $CurrentDepthKey) }

    $decayed = [double[]]@(
        ($Previous[0] * 0.985),
        ($Previous[1] * 0.985),
        ($Previous[2] * 0.985))
    $currentPeak = [math]::Max($Current[0], [math]::Max($Current[1], $Current[2]))
    $historyPeak = [math]::Max($decayed[0], [math]::Max($decayed[1], $decayed[2]))
    $refresh = if ($currentPeak -ge $historyPeak * 0.95) { 0.35 } else { 0.015 }
    return [double[]]@(
        ($decayed[0] + ($Current[0] - $decayed[0]) * $refresh),
        ($decayed[1] + ($Current[1] - $decayed[1]) * $refresh),
        ($decayed[2] + ($Current[2] - $decayed[2]) * $refresh),
        $CurrentDepthKey)
}

$first = Invoke-TemporalModel -Current @(0.4, 0.2, 0.1) -Previous @(0.0, 0.0, 0.0) -CurrentDepthKey 4.0 -PreviousDepthKey 0.0
if ([math]::Abs($first[0] - 0.4) -gt 1e-9 -or $first[3] -ne 4.0) {
    throw 'Behavior model failed deterministic first-frame initialization.'
}
$rejected = Invoke-TemporalModel -Current @(0.1, 0.1, 0.1) -Previous @(0.8, 0.8, 0.8) -CurrentDepthKey 4.0 -PreviousDepthKey 4.5
if ([math]::Abs($rejected[0] - 0.1) -gt 1e-9) {
    throw 'Behavior model failed depth-disocclusion rejection.'
}
$outside = Invoke-TemporalModel -Current @(0.2, 0.1, 0.05) -Previous @(0.9, 0.9, 0.9) -CurrentDepthKey 4.0 -PreviousDepthKey 4.0 -InsideHistory $false
if ([math]::Abs($outside[0] - 0.2) -gt 1e-9) {
    throw 'Behavior model failed off-screen history rejection.'
}
$retained = [double[]]@(0.6, 0.3, 0.15)
for ($frame = 0; $frame -lt 10; $frame++) {
    $step = Invoke-TemporalModel -Current @(0.0, 0.0, 0.0) -Previous $retained -CurrentDepthKey 4.0 -PreviousDepthKey 4.0
    $retained = [double[]]@($step[0], $step[1], $step[2])
}
if ($retained[0] -le 0.4 -or $retained[0] -ge 0.6) {
    throw 'Behavior model does not retain and bound a temporarily absent source.'
}
$rising = Invoke-TemporalModel -Current @(0.8, 0.4, 0.2) -Previous @(0.1, 0.05, 0.025) -CurrentDepthKey 4.0 -PreviousDepthKey 4.0
if ($rising[0] -le 0.3 -or $rising[0] -ge 0.8) {
    throw 'Behavior model failed the fast-rise response contract.'
}

Write-Host 'PASS: private temporal SSGI history compiles eight SM5 shaders, uses a half-resolution RGBA16F GI-only history, clears deterministically on allocation/resize and F2 OFF, preserves F10/Page keys and the native OFF path, rejects depth/viewport discontinuities, retains a bounded temporarily absent source, and contains no finished-scene feedback path.'
