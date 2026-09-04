[CmdletBinding()]
param(
    [string]$SourcePackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-late-scene-pack'),
    [string]$TemporalAssemblyPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\assembly\c473ab75b7519f7e-ps.asm'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-pre-temporal-pack'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifactsRoot = Join-Path $workspace 'artifacts'
$source = [IO.Path]::GetFullPath($SourcePackRoot).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
foreach ($path in @($source, $output)) {
    if (-not $path.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'SourcePackRoot and OutputRoot must remain below workspace artifacts.'
    }
}
foreach ($path in @((Join-Path $source 'manifest.json'), (Join-Path $source 'Mods'), $TemporalAssemblyPath, $FxcPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required input is missing: $path" }
}
if (Test-Path -LiteralPath $output) { throw "OutputRoot already exists; preserve prior evidence: $output" }

$sourceManifestPath = Join-Path $source 'manifest.json'
$sourceManifest = Get-Content -Raw -LiteralPath $sourceManifestPath | ConvertFrom-Json
if ($sourceManifest.result -ne 'pass' -or $sourceManifest.variant -ne 'late-scene-native-af6cd-writeback' -or
    -not [bool]$sourceManifest.validation.feedbackSourceAbsent) {
    throw 'The preserved working late-scene source pack does not satisfy its recorded contract.'
}
$acceptancePath = Join-Path $source 'validation\live-visual-acceptance-20260903.json'
if (-not (Test-Path -LiteralPath $acceptancePath -PathType Leaf)) { throw 'Working live visual-acceptance evidence is missing.' }
$acceptance = Get-Content -Raw -LiteralPath $acceptancePath | ConvertFrom-Json
if (-not [bool]$acceptance.confirmed.currentFrameUpdatesWithoutF10 -or
    -not [bool]$acceptance.confirmed.visibleIndirectLighting -or
    [bool]$acceptance.confirmed.previousFrameFeedbackDefectReproducedAfterFix) {
    throw 'The source pack has not passed the required no-feedback live observations.'
}

$sourceMods = Join-Path $source 'Mods'
foreach ($entry in @($sourceManifest.payloadFiles | Where-Object relativePath -like 'Mods/*')) {
    $leaf = Split-Path -Leaf ([string]$entry.relativePath)
    $path = Join-Path $sourceMods $leaf
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$entry.sha256) {
        throw "Working source payload drifted: $leaf"
    }
}

$temporalAssembly = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $TemporalAssemblyPath).Path).Replace("`r`n", "`n")
foreach ($required in @(
    'ps_5_0',
    'dcl_constantbuffer CB1[140]',
    'dcl_resource_texture2d (float,float,float,float) t2',
    'dcl_resource_texture2d (float,float,float,float) t3',
    'dcl_resource_texture2d (float,float,float,float) t4',
    'sample_l_indexable(texture2d)'
)) {
    if (-not $temporalAssembly.Contains($required)) { throw "Temporal-resolve evidence lacks: $required" }
}

$modsOutput = Join-Path $output 'Mods'
$compileOutput = Join-Path $output 'compile-verification'
[void][IO.Directory]::CreateDirectory($modsOutput)
[void][IO.Directory]::CreateDirectory($compileOutput)
foreach ($file in @(Get-ChildItem -LiteralPath $sourceMods -File)) {
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $modsOutput $file.Name)
}

# c473's view constant buffer has 140 float4 rows. All SSGI reads are below row 140.
$rebasedCount = 0
foreach ($shader in @(Get-ChildItem -LiteralPath $modsOutput -Filter '*.hlsl' -File)) {
    $text = [IO.File]::ReadAllText($shader.FullName)
    if ($text.Contains('float4 RemakeViewData[154];')) {
        $text = $text.Replace('float4 RemakeViewData[154];', 'float4 RemakeViewData[140];')
        [IO.File]::WriteAllText($shader.FullName, $text, [Text.UTF8Encoding]::new($false))
        $rebasedCount++
    }
}
if ($rebasedCount -ne 6) { throw "Expected six HLSL shaders to adopt c473 CB1[140]; found $rebasedCount." }

$compositePath = Join-Path $modsOutput 'Agent2R3DSSGICompositeE2AA_ps.hlsl'
$composite = [IO.File]::ReadAllText($compositePath).Replace("`r`n", "`n")
$textureNeedle = 'Texture2D<float4> Agent2CompositeAlbedo : register(t114);'
if ([regex]::Matches($composite, [regex]::Escape($textureNeedle)).Count -ne 1) { throw 'Composite albedo declaration is not unique.' }
$composite = $composite.Replace($textureNeedle, $textureNeedle + "`nTexture2D<float4> Agent2TemporalScene : register(t115);")
$mainNeedle = @'
    float2 centerUV = input.uvAndRay.xy;
    float centerDepth = Agent2CompositeLoadDepth(centerUV);
    if (centerDepth <= AGENT2_DEPTH_CLEAR_EPSILON)
        return 0.0;
'@.Replace("`r`n", "`n").TrimEnd("`r", "`n")
$mainReplacement = @'
    float2 centerUV = input.uvAndRay.xy;
    uint sceneWidth;
    uint sceneHeight;
    Agent2TemporalScene.GetDimensions(sceneWidth, sceneHeight);
    float4 nativeScene = Agent2TemporalScene.Load(int3(Agent2CompositeCoord(centerUV, sceneWidth, sceneHeight), 0));
    float centerDepth = Agent2CompositeLoadDepth(centerUV);
    if (centerDepth <= AGENT2_DEPTH_CLEAR_EPSILON)
        return nativeScene;
'@.Replace("`r`n", "`n").TrimEnd("`r", "`n")
if ([regex]::Matches($composite, [regex]::Escape($mainNeedle)).Count -ne 1) { throw 'Composite depth-clear return is not uniquely patchable.' }
$composite = $composite.Replace($mainNeedle, $mainReplacement)
if ([regex]::Matches($composite, [regex]::Escape('if (shadingModel == 0u)' + "`n" + '        return 0.0;')).Count -ne 1) {
    throw 'Composite unlit return is not uniquely patchable.'
}
$composite = $composite.Replace('if (shadingModel == 0u)' + "`n" + '        return 0.0;', 'if (shadingModel == 0u)' + "`n" + '        return nativeScene;')
$returnNeedle = 'return float4(indirectRadiance, 0.0);'
if ([regex]::Matches($composite, [regex]::Escape($returnNeedle)).Count -ne 1) { throw 'Composite indirect return is not unique.' }
$composite = $composite.Replace($returnNeedle, 'return float4(nativeScene.rgb + indirectRadiance, nativeScene.a);')
$composite = $composite.Replace('Depth-aware additive composite for the offline Agent 2 R3D SSGI candidate.', 'Depth-aware pre-temporal scene composite for the offline Agent 2 R3D SSGI candidate.')
[IO.File]::WriteAllText($compositePath, $composite.Replace("`n", "`r`n"), [Text.UTF8Encoding]::new($false))

$iniPath = Join-Path $modsOutput 'Agent2R3DSSGITest.ini'
$ini = [IO.File]::ReadAllText($iniPath).Replace("`r`n", "`n")
$resourceNeedle = '[ResourceAgent2SSGIOriginalT110]'
if ([regex]::Matches($ini, [regex]::Escape($resourceNeedle)).Count -ne 1) { throw 'Original t110 resource declaration is not unique.' }
$ini = $ini.Replace($resourceNeedle, '[ResourceAgent2SSGIOriginalT2]' + "`n" + $resourceNeedle)
$ini = $ini.Replace('ps-t114 = ResourceAgent2SSGIAlbedo' + "`n" + 'draw = 3, 0', 'ps-t114 = ResourceAgent2SSGIAlbedo' + "`n" + 'ps-t115 = ResourceAgent2SSGIScene' + "`n" + 'draw = 3, 0')
$ini = $ini.Replace('post ps-t114 = null', 'post ps-t114 = null' + "`n" + 'post ps-t115 = null')
$overridePattern = '(?ms)^\[ShaderOverrideAgent2R3DSSGICaptureGBuffer\]\n.*\z'
if ([regex]::Matches($ini, $overridePattern).Count -ne 1) { throw 'Could not isolate the late-scene override block.' }
$replacementOverrides = @'
[ShaderOverrideAgent2R3DSSGICaptureGBuffer]
hash = e2aa1c8cb39e0a55
allow_duplicate_hash = true
; Capture current-frame geometry only. Never read or write e2aa o0 here.
if $agent2_ssgi_test == 1
    ResourceAgent2SSGINormal = reference ps-t0
    ResourceAgent2SSGIDepth = reference ps-t5
    ResourceAgent2SSGIMaterial = reference ps-t1
    ResourceAgent2SSGIAlbedo = reference ps-t2
endif

[ShaderOverrideAgent2R3DSSGIPreTemporal]
hash = c473ab75b7519f7e
allow_duplicate_hash = true
; c473 t2 is native current-frame scene color; t3 is history and t4 is motion.
; Build scene+GI in a private t2-compatible target, then let native c473 perform
; temporal accumulation and its existing motion/disocclusion rejection.
ResourceAgent2SSGIOriginalT2 = reference ps-t2
if $agent2_ssgi_test == 1
    ResourceAgent2SSGITarget = reference ps-t2
    ResourceAgent2SSGIScene = reference ps-t2
    run = CustomShaderAgent2R3DSSGITrace
    run = CustomShaderAgent2R3DSSGIDenoise16
    run = CustomShaderAgent2R3DSSGIDenoise8
    run = CustomShaderAgent2R3DSSGIDenoise4
    run = CustomShaderAgent2R3DSSGIDenoise2
    run = CustomShaderAgent2R3DSSGIComposite
    ps-t2 = ResourceAgent2SSGICompositeScratch
endif
post ps-t2 = reference ResourceAgent2SSGIOriginalT2
'@.Replace("`r`n", "`n").TrimEnd("`r", "`n")
$ini = [regex]::Replace($ini, $overridePattern, $replacementOverrides)
$ini = $ini.Replace('; Agent 2 late-scene R3D SSGI integration candidate. Offline only.', '; Agent 2 pre-temporal R3D SSGI integration candidate. Offline only.')
foreach ($forbidden in @(
    'hash = af6cd28a0108a18a',
    'ResourceAgent2SSGITarget = reference o0',
    'ResourceAgent2SSGIScene = copy o0',
    'ps-t110 = ResourceAgent2SSGICompositeScratch'
)) {
    if ($ini.Contains($forbidden)) { throw "Unsafe or obsolete binding survived: $forbidden" }
}
foreach ($required in @(
    'hash = c473ab75b7519f7e',
    'ResourceAgent2SSGITarget = reference ps-t2',
    'ResourceAgent2SSGIScene = reference ps-t2',
    'ps-t115 = ResourceAgent2SSGIScene',
    'ps-t2 = ResourceAgent2SSGICompositeScratch',
    'post ps-t2 = reference ResourceAgent2SSGIOriginalT2',
    'key = no_modifiers F2'
)) {
    if (-not $ini.Contains($required)) { throw "Pre-temporal INI lacks: $required" }
}
if ($ini -match '(?im)^\s*key\s*=.*(?:F10|VK_PRIOR|VK_NEXT).*$') { throw 'Reserved key binding leaked into the pre-temporal pack.' }
[IO.File]::WriteAllText($iniPath, $ini.Replace("`n", "`r`n") + "`r`n", [Text.UTF8Encoding]::new($false))

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
if ($compiled.Count -ne 7) { throw "Expected seven compiled HLSL shaders; found $($compiled.Count)." }

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
    variant = 'pre-temporal-native-c473-input'
    purpose = 'Feed current-frame scene plus private SSGI into Remake native temporal resolve so its motion/history rejection can stabilize screen-space lighting without previous-frame render-target feedback.'
    source = [ordered]@{
        workingLateSceneManifest = $sourceManifestPath
        workingLateSceneManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceManifestPath).Hash
        liveVisualAcceptance = $acceptancePath
        liveVisualAcceptanceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $acceptancePath).Hash
    }
    hooks = [ordered]@{
        geometryCapture = 'e2aa1c8cb39e0a55-ps'
        temporalResolve = 'c473ab75b7519f7e-ps'
        currentScene = 'c473 ps-t2 by reference'
        history = 'native c473 ps-t3, untouched'
        motion = 'native c473 ps-t4, untouched'
        pairedVertexShader = '1bf99472af1427ba-vs'
    }
    controls = [ordered]@{
        F2 = 'off/on for this SSGI candidate only'
        F10 = 'native reload, unchanged'
        PageUp = 'unchanged'
        PageDown = 'unchanged'
    }
    architecture = [ordered]@{
        sourceRadiance = 'native current-frame scene c473 t2'
        privateOutput = 'scene plus indirect RGB, descriptor-compatible with c473 t2'
        temporalWriteback = 'bind private output as c473 t2 and execute native c473 unchanged'
        offPath = 'F2 zero runs no private draw and leaves native c473 t2 untouched'
        forbiddenFeedbackSource = 'no render-target o0 copy or reference is used as SSGI input'
        expectedBenefit = 'native temporal accumulation should reduce immediate angle/noise popping; it cannot recover emitters absent from screen space'
        risk = 'native history can ghost newly injected GI if c473 rejection is insufficient; live camera cuts and fast pans remain mandatory'
    }
    validation = [ordered]@{
        temporalAssemblyPath = (Resolve-Path -LiteralPath $TemporalAssemblyPath).Path
        temporalAssemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $TemporalAssemblyPath).Hash
        temporalContract = 't2 current scene, t3 history, t4 motion, native history sampling'
        viewBufferRows = 140
        rebasedHlslCount = $rebasedCount
        compiledShaderCount = $compiled.Count
        feedbackSourceAbsent = $true
        nativeTemporalReplacementIncluded = $false
        nativeLateSceneReplacementIncluded = $false
    }
    compile = @($compiled)
    files = $files
    prerequisite = 'Preserve the working late-scene build. Live test only as a separate F2 candidate with fixed-camera OFF parity first, then motion, camera cuts, character materials, UI, and GPU timing.'
    runtimeEligible = $false
    installed = $false
    liveTestsPerformed = $false
    generatedUtc = [DateTime]::UtcNow.ToString('o')
}
$manifestPath = Join-Path $output 'manifest.json'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 12) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    OutputRoot = $output
    Manifest = $manifestPath
    PayloadFiles = $files.Count
    CompiledShaders = $compiled.Count
    FeedbackSourceAbsent = $true
    RuntimeEligible = $false
}
