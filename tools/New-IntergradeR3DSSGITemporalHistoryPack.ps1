[CmdletBinding()]
param(
    [string]$SourcePackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-pre-temporal-pack'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-temporal-history-pack'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$utf8 = [Text.UTF8Encoding]::new($false)
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifactsRoot = Join-Path $workspace 'artifacts'
$source = [IO.Path]::GetFullPath($SourcePackRoot).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
foreach ($path in @($source, $output)) {
    if (-not $path.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'SourcePackRoot and OutputRoot must remain below workspace artifacts.'
    }
}

$sourceManifestPath = Join-Path $source 'manifest.json'
$sourceMods = Join-Path $source 'Mods'
$temporalSourcePath = Join-Path $workspace 'src\Adapters\FF7RemakeIntergrade\R3DSSGITemporalHistory_ps.hlsl'
$commandListHeaderPath = Join-Path $workspace 'src\Backends\3DmigotoFork\DirectX11\CommandList.h'
$commandListPath = Join-Path $workspace 'src\Backends\3DmigotoFork\DirectX11\CommandList.cpp'
foreach ($path in @($sourceManifestPath, $sourceMods, $temporalSourcePath, $commandListHeaderPath, $commandListPath, $FxcPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required input is missing: $path" }
}
if (Test-Path -LiteralPath $output) { throw "OutputRoot already exists; preserve prior evidence: $output" }

$sourceManifest = Get-Content -Raw -LiteralPath $sourceManifestPath | ConvertFrom-Json
if ($sourceManifest.result -ne 'pass' -or
    $sourceManifest.variant -ne 'pre-temporal-native-c473-input' -or
    -not [bool]$sourceManifest.validation.feedbackSourceAbsent -or
    [bool]$sourceManifest.runtimeEligible -or
    [bool]$sourceManifest.installed) {
    throw 'The pre-temporal source pack does not satisfy its recorded offline contract.'
}
foreach ($entry in @($sourceManifest.files)) {
    $path = Join-Path $sourceMods ([string]$entry.name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$entry.sha256) {
        throw "Pre-temporal source payload drifted: $($entry.name)"
    }
}

$commandListHeader = [IO.File]::ReadAllText($commandListHeaderPath)
$commandList = [IO.File]::ReadAllText($commandListPath)
foreach ($required in @(
    'CLEAR_ON_CREATE = 0x00000800',
    '{L"clear_on_create", ResourceCopyOptions::CLEAR_ON_CREATE}'
)) {
    if (-not $commandListHeader.Contains($required)) { throw "Engine header lacks: $required" }
}
foreach ($required in @(
    'if ((operation->options & ResourceCopyOptions::CLEAR_ON_CREATE)',
    'if (resource_recreated && (options & ResourceCopyOptions::CLEAR_ON_CREATE))',
    'return res != NULL;'
)) {
    if (-not $commandList.Contains($required)) { throw "Engine implementation lacks: $required" }
}

$modsOutput = Join-Path $output 'Mods'
$compileOutput = Join-Path $output 'compile-verification'
[void][IO.Directory]::CreateDirectory($modsOutput)
[void][IO.Directory]::CreateDirectory($compileOutput)
foreach ($file in @(Get-ChildItem -LiteralPath $sourceMods -File)) {
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $modsOutput $file.Name)
}
$temporalOutputPath = Join-Path $modsOutput 'Agent2R3DSSGITemporalHistory_ps.hlsl'
Copy-Item -LiteralPath $temporalSourcePath -Destination $temporalOutputPath

$iniPath = Join-Path $modsOutput 'Agent2R3DSSGITest.ini'
$ini = [IO.File]::ReadAllText($iniPath).Replace("`r`n", "`n")
$ini = $ini.Replace(
    '; Agent 2 pre-temporal R3D SSGI integration candidate. Offline only.',
    '; Agent 2 private temporal-history R3D SSGI integration candidate. Offline only.')

$resourceNeedle = '[ResourceAgent2SSGIOriginalT2]'
if ([regex]::Matches($ini, [regex]::Escape($resourceNeedle)).Count -ne 1) {
    throw 'Original t2 resource declaration is not unique.'
}
$temporalResources = @'
[ResourceAgent2SSGIHistory]
format = R16G16B16A16_FLOAT
width_multiply = 0.5
height_multiply = 0.5
bind_flags = shader_resource render_target
[ResourceAgent2SSGITemporalScratch]
format = R16G16B16A16_FLOAT
bind_flags = shader_resource render_target
[ResourceAgent2SSGIMotion]
'@.Replace("`r`n", "`n").TrimEnd("`r", "`n")
$ini = $ini.Replace($resourceNeedle, $temporalResources + "`n" + $resourceNeedle)

$compositePattern = '(?ms)^\[CustomShaderAgent2R3DSSGIComposite\]\n.*?(?=^\[ShaderOverrideAgent2R3DSSGICaptureGBuffer\])'
$compositeMatches = [regex]::Matches($ini, $compositePattern)
if ($compositeMatches.Count -ne 1) { throw 'Composite custom-shader section is not unique.' }
$compositeSection = $compositeMatches[0].Value
if ([regex]::Matches($compositeSection, '(?m)^ps-t110 = ResourceAgent2SSGIPing$').Count -ne 1) {
    throw 'Composite filtered-input binding is not uniquely patchable.'
}
$compositeSection = $compositeSection.Replace(
    'ps-t110 = ResourceAgent2SSGIPing',
    'ps-t110 = ResourceAgent2SSGITemporalScratch')

$temporalSection = @'
[CustomShaderAgent2R3DSSGITemporalHistory]
ps = Agent2R3DSSGITemporalHistory_ps.hlsl
vs = Agent2R3DSSGIFullscreen_vs.hlsl
hs = null
ds = null
gs = null
sampler = linear_filter
blend = disable
depth_enable = false
depth_write_mask = zero
stencil_enable = false
cull = none
topology = triangle_list
run = BuiltInCommandListUnbindAllRenderTargets
ResourceAgent2SSGITemporalScratch = copy_desc ResourceAgent2SSGIHistory
o0 = set_viewport ResourceAgent2SSGITemporalScratch
ps-t110 = ResourceAgent2SSGIPing
ps-t111 = ResourceAgent2SSGIHistory
ps-t112 = ResourceAgent2SSGIDepth
ps-t113 = ResourceAgent2SSGIMotion
draw = 3, 0
post ps-t110 = null
post ps-t111 = null
post ps-t112 = null
post ps-t113 = null
post ResourceAgent2SSGIHistory = copy ResourceAgent2SSGITemporalScratch

'@.Replace("`r`n", "`n")
$ini = [regex]::Replace($ini, $compositePattern, $temporalSection + $compositeSection, 1)

$overridePattern = '(?ms)^\[ShaderOverrideAgent2R3DSSGICaptureGBuffer\]\n.*\z'
if ([regex]::Matches($ini, $overridePattern).Count -ne 1) {
    throw 'Could not isolate the pre-temporal override tail.'
}
$replacementOverrides = @'
[ShaderOverrideAgent2R3DSSGICaptureGBuffer]
hash = e2aa1c8cb39e0a55
allow_duplicate_hash = true
; Capture only current-frame geometry and material inputs.
if $agent2_ssgi_test == 1
    ResourceAgent2SSGINormal = reference ps-t0
    ResourceAgent2SSGIDepth = reference ps-t5
    ResourceAgent2SSGIMaterial = reference ps-t1
    ResourceAgent2SSGIAlbedo = reference ps-t2
endif

[ShaderOverrideAgent2R3DSSGITemporalHistory]
hash = c473ab75b7519f7e
allow_duplicate_hash = true
; Allocate a private half-resolution RGBA16F history from c473's current-scene
; descriptor. The engine clears it only when first created or resized.
ResourceAgent2SSGIHistory = copy_desc clear_on_create ps-t2
ResourceAgent2SSGIOriginalT2 = reference ps-t2
if $agent2_ssgi_test == 0
    ; OFF is native and clears history every frame, preventing stale resurrection.
    clear = ResourceAgent2SSGIHistory 0.0
else
    ResourceAgent2SSGITarget = reference ps-t2
    ResourceAgent2SSGIScene = reference ps-t2
    ResourceAgent2SSGIMotion = reference ps-t4
    run = CustomShaderAgent2R3DSSGITrace
    run = CustomShaderAgent2R3DSSGIDenoise16
    run = CustomShaderAgent2R3DSSGIDenoise8
    run = CustomShaderAgent2R3DSSGIDenoise4
    run = CustomShaderAgent2R3DSSGIDenoise2
    run = CustomShaderAgent2R3DSSGITemporalHistory
    run = CustomShaderAgent2R3DSSGIComposite
    ps-t2 = ResourceAgent2SSGICompositeScratch
endif
post ps-t2 = reference ResourceAgent2SSGIOriginalT2
'@.Replace("`r`n", "`n").TrimEnd("`r", "`n")
$ini = [regex]::Replace($ini, $overridePattern, $replacementOverrides, 1)

foreach ($required in @(
    'key = no_modifiers F2',
    'format = R16G16B16A16_FLOAT',
    'ResourceAgent2SSGIHistory = copy_desc clear_on_create ps-t2',
    'clear = ResourceAgent2SSGIHistory 0.0',
    'ResourceAgent2SSGIMotion = reference ps-t4',
    'run = CustomShaderAgent2R3DSSGITemporalHistory',
    'post ResourceAgent2SSGIHistory = copy ResourceAgent2SSGITemporalScratch',
    'ps-t110 = ResourceAgent2SSGITemporalScratch',
    'post ps-t2 = reference ResourceAgent2SSGIOriginalT2'
)) {
    if (-not $ini.Contains($required)) { throw "Temporal-history INI lacks: $required" }
}
foreach ($forbidden in @(
    'ResourceAgent2SSGITarget = reference o0',
    'ResourceAgent2SSGIScene = copy o0',
    'ResourceAgent2SSGIHistory = copy o0',
    'ResourceAgent2SSGIHistory = reference o0',
    'hash = af6cd28a0108a18a'
)) {
    if ($ini.Contains($forbidden)) { throw "Unsafe or obsolete binding survived: $forbidden" }
}
if ($ini -match '(?im)^\s*key\s*=.*(?:F10|VK_PRIOR|VK_NEXT).*$') {
    throw 'Reserved key binding leaked into the temporal-history pack.'
}
if ([regex]::Matches($ini, '(?im)^\s*key\s*=.*F2\s*$').Count -ne 1) {
    throw 'F2 must have exactly one binding.'
}
[IO.File]::WriteAllText($iniPath, $ini.Replace("`n", "`r`n") + "`r`n", $utf8)

$compiled = [Collections.Generic.List[object]]::new()
foreach ($file in @(Get-ChildItem -LiteralPath $modsOutput -Filter '*.hlsl' -File | Sort-Object Name)) {
    $profile = if ($file.Name.EndsWith('_vs.hlsl', [StringComparison]::OrdinalIgnoreCase)) { 'vs_5_0' } else { 'ps_5_0' }
    $binary = Join-Path $compileOutput ($file.BaseName + '.bin')
    $assembly = Join-Path $compileOutput ($file.BaseName + '.asm')
    & $FxcPath /nologo /Ges /WX /O3 /T $profile /E main /Fo $binary /Fc $assembly $file.FullName
    if ($LASTEXITCODE -ne 0) { throw "Strict HLSL compilation failed ($profile): $($file.Name)" }
    $compiled.Add([ordered]@{
        name = $file.Name
        profile = $profile
        hlslSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
        dxbcSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $binary).Hash
        assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assembly).Hash
    })
}
if ($compiled.Count -ne 8) { throw "Expected eight compiled HLSL shaders; found $($compiled.Count)." }

$files = @(Get-ChildItem -LiteralPath $modsOutput -File | Sort-Object Name | ForEach-Object {
    [ordered]@{
        name = $_.Name
        bytes = $_.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
    }
})
$manifest = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    variant = 'private-temporal-indirect-history'
    purpose = 'Reproject and retain only filtered indirect lighting in private RGBA16F history, with depth rejection and no finished-scene feedback.'
    source = [ordered]@{
        preTemporalManifest = $sourceManifestPath
        preTemporalManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceManifestPath).Hash
        temporalShader = $temporalSourcePath
        temporalShaderSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $temporalSourcePath).Hash
    }
    hooks = [ordered]@{
        geometryCapture = 'e2aa1c8cb39e0a55-ps'
        temporalHost = 'c473ab75b7519f7e-ps'
        currentScene = 'c473 ps-t2 by reference'
        motion = 'c473 ps-t4 by reference'
        pairedVertexShader = '1bf99472af1427ba-vs'
    }
    controls = [ordered]@{
        F2 = 'off/on for this SSGI candidate only; OFF clears private history'
        F10 = 'native reload, unchanged'
        PageUp = 'unchanged'
        PageDown = 'unchanged'
    }
    architecture = [ordered]@{
        historyContents = 'filtered indirect RGB plus logarithmic DeviceW validity key in alpha'
        historyFormat = 'R16G16B16A16_FLOAT'
        historyScale = 0.5
        initialization = 'clear_on_create when first allocated or resized'
        offReset = 'explicit zero clear on every c473 invocation while F2 is off'
        update = 'temporal scratch copied into private history only after the temporal draw'
        sourceRadiance = 'native current-frame scene c473 t2'
        finishedSceneFeedback = $false
        depthThreshold = 0.12
        decay = 0.985
        fastRefresh = 0.35
        slowRefresh = 0.015
        motionDecode = 'c473 t4.zx, center 0.499992371, scale 4.008016; inferred previous-UV sign pending live validation'
    }
    engine = [ordered]@{
        clearOnCreateHeaderSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $commandListHeaderPath).Hash
        clearOnCreateImplementationSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $commandListPath).Hash
        requiresRebuiltWrapper = $true
    }
    validation = [ordered]@{
        compiledShaderCount = $compiled.Count
        nativeShaderReplacementIncluded = $false
        exactNativeOffPath = $true
        deterministicInitialization = $true
        resolutionRecreationClear = $true
        finishedSceneFeedbackAbsent = $true
        motionSignLiveValidationPending = $true
    }
    compile = @($compiled)
    files = $files
    prerequisite = 'Offline verification must pass before packaging the rebuilt wrapper and this F2 candidate for controlled live motion/disocclusion testing.'
    runtimeEligible = $false
    installed = $false
    liveTestsPerformed = $false
    generatedUtc = [DateTime]::UtcNow.ToString('o')
}
$manifestPath = Join-Path $output 'manifest.json'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 12) + [Environment]::NewLine, $utf8)

[pscustomobject]@{
    OutputRoot = $output
    Manifest = $manifestPath
    PayloadFiles = $files.Count
    CompiledShaders = $compiled.Count
    FinishedSceneFeedbackAbsent = $true
    RuntimeEligible = $false
}
