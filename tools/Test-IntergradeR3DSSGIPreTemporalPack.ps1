[CmdletBinding()]
param(
    [string]$PackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-pre-temporal-pack')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifactsRoot = Join-Path $workspace 'artifacts'
$pack = [IO.Path]::GetFullPath($PackRoot).TrimEnd('\')
if (-not $pack.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'PackRoot must remain below artifacts.' }
$manifestPath = Join-Path $pack 'manifest.json'
$iniPath = Join-Path $pack 'Mods\Agent2R3DSSGITest.ini'
$compositePath = Join-Path $pack 'Mods\Agent2R3DSSGICompositeE2AA_ps.hlsl'
foreach ($path in @($manifestPath, $iniPath, $compositePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required pack file is missing: $path" }
}
$commandListPath = Join-Path $workspace 'reference\external\3dmigoto-source-official\DirectX11\CommandList.cpp'
$commandListHeaderPath = Join-Path $workspace 'reference\external\3dmigoto-source-official\DirectX11\CommandList.h'
$officialExamplePath = Join-Path $workspace 'reference\external\3dmigoto-source-official\Dependencies\ShaderFixes\3dvision2sbs.ini'
foreach ($path in @($commandListPath, $commandListHeaderPath, $officialExamplePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Pinned 3DMigoto semantics source is missing: $path" }
}
$commandList = Get-Content -Raw -LiteralPath $commandListPath
$commandListHeader = Get-Content -Raw -LiteralPath $commandListHeaderPath
$officialExample = Get-Content -Raw -LiteralPath $officialExamplePath
$semanticsChecks = [ordered]@{
    copyDescOption = $commandListHeader -match 'COPY_DESC\s*=\s*0x00000080'
    copyDescCreatesCompatibleResource = $commandList -match 'if \(options & ResourceCopyOptions::COPY_DESC\)'
    destinationAccumulatesRtvSrvFlags = $commandList -match 'custom_resource->bind_flags \| operation->dst\.BindFlags'
    customShaderSavesOutputMerger = $commandList -match 'save_om_state\(state->mOrigContext1, &om_state\)'
    customShaderRestoresOutputMerger = $commandList -match 'restore_om_state\(mOrigContext1, &om_state\)'
    referenceSaveExample = $officialExample -match 'Resource\w+BackupTexture = reference ps-t\d+'
    referencePostRestoreExample = $officialExample -match 'post ps-t\d+ = reference Resource\w+BackupTexture'
    resizedTargetExample = $officialExample -match 'copy_desc bb'
    viewportTargetExample = $officialExample -match 'o0 = set_viewport Resource'
}
foreach ($check in $semanticsChecks.GetEnumerator()) {
    if (-not [bool]$check.Value) { throw "Pinned 3DMigoto semantics assertion failed: $($check.Key)" }
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.result -ne 'pass' -or $manifest.variant -ne 'pre-temporal-native-c473-input' -or
    [bool]$manifest.runtimeEligible -or [bool]$manifest.installed -or [bool]$manifest.liveTestsPerformed) {
    throw 'Pre-temporal manifest state is invalid.'
}
if (-not [bool]$manifest.validation.feedbackSourceAbsent -or
    [bool]$manifest.validation.nativeTemporalReplacementIncluded -or
    [bool]$manifest.validation.nativeLateSceneReplacementIncluded -or
    [int]$manifest.validation.compiledShaderCount -ne 7 -or [int]$manifest.validation.viewBufferRows -ne 140) {
    throw 'Pre-temporal validation contract is invalid.'
}
if (Test-Path -LiteralPath (Join-Path $pack 'ShaderFixes')) { throw 'Pre-temporal pack must not contain native shader replacements.' }

$ini = [IO.File]::ReadAllText($iniPath).Replace("`r`n", "`n")
foreach ($required in @(
    '[ShaderOverrideAgent2R3DSSGICaptureGBuffer]',
    'hash = e2aa1c8cb39e0a55',
    '[ShaderOverrideAgent2R3DSSGIPreTemporal]',
    'hash = c473ab75b7519f7e',
    'ResourceAgent2SSGITarget = reference ps-t2',
    'ResourceAgent2SSGIScene = reference ps-t2',
    'ps-t115 = ResourceAgent2SSGIScene',
    'ps-t2 = ResourceAgent2SSGICompositeScratch',
    'post ps-t2 = reference ResourceAgent2SSGIOriginalT2',
    'key = no_modifiers F2',
    'blend = disable'
)) {
    if (-not $ini.Contains($required)) { throw "INI contract is missing: $required" }
}
foreach ($forbidden in @('af6cd28a0108a18a', 'reference o0', 'copy o0', 'ps-t110 = ResourceAgent2SSGICompositeScratch')) {
    if ($ini.Contains($forbidden)) { throw "Unsafe/obsolete INI fragment survived: $forbidden" }
}
if ($ini -match '(?im)^\s*key\s*=.*(?:F10|VK_PRIOR|VK_NEXT).*$') { throw 'Reserved key binding is present.' }
if ([regex]::Matches($ini, '(?im)^\s*key\s*=.*F2\s*$').Count -ne 1) { throw 'F2 must have exactly one binding.' }

$composite = [IO.File]::ReadAllText($compositePath).Replace("`r`n", "`n")
foreach ($required in @(
    'Texture2D<float4> Agent2TemporalScene : register(t115);',
    'float4 RemakeViewData[140];',
    'return nativeScene;',
    'return float4(nativeScene.rgb + indirectRadiance, nativeScene.a);'
)) {
    if (-not $composite.Contains($required)) { throw "Composite contract is missing: $required" }
}
if ($composite.Contains('return float4(indirectRadiance, 0.0);')) { throw 'Late-scene indirect-only return survived.' }

$compiled = @($manifest.compile)
if ($compiled.Count -ne 7) { throw 'Compile receipt must contain seven shaders.' }
foreach ($entry in $compiled) {
    $hlsl = Join-Path $pack ('Mods\' + [string]$entry.name)
    $binary = Join-Path $pack ('compile-verification\' + [IO.Path]::GetFileNameWithoutExtension([string]$entry.name) + '.bin')
    $assembly = Join-Path $pack ('compile-verification\' + [IO.Path]::GetFileNameWithoutExtension([string]$entry.name) + '.asm')
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
if ($payload.Count -ne 8) { throw "Expected eight Mods payload files; found $($payload.Count)." }
foreach ($entry in $payload) {
    $path = Join-Path $pack ('Mods\' + [string]$entry.name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$entry.sha256) {
        throw "Payload file drifted: $($entry.name)"
    }
}

$temporalPath = [string]$manifest.validation.temporalAssemblyPath
if (-not (Test-Path -LiteralPath $temporalPath -PathType Leaf) -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $temporalPath).Hash -ne [string]$manifest.validation.temporalAssemblySha256) {
    throw 'Retained c473 temporal assembly evidence is missing or drifted.'
}
$temporal = [IO.File]::ReadAllText($temporalPath)
foreach ($required in @('dcl_resource_texture2d (float,float,float,float) t2','dcl_resource_texture2d (float,float,float,float) t3','dcl_resource_texture2d (float,float,float,float) t4','sample_l_indexable(texture2d)')) {
    if (-not $temporal.Contains($required)) { throw "Native temporal contract is missing: $required" }
}

Write-Host 'PASS: pre-temporal SSGI pack preserves F10/Page keys, has an exact native OFF path, uses c473 current-scene t2 without o0 feedback, preserves native history/motion inputs, matches pinned 3DMigoto copy/reference/state semantics, compiles seven SM5 shaders strictly, and ships no native shader replacement.'
