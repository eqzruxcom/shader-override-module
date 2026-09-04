[CmdletBinding()]
param(
    [string]$OutputPath = '',
    [string]$CompiledDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if (-not $OutputPath) {
    $OutputPath = Join-Path $root 'artifacts\analysis\agent2-r3d-ssgi-sampling-semantics.json'
}
if (-not $CompiledDirectory) {
    $CompiledDirectory = Join-Path $root 'artifacts\agent2-r3d-ssgi-f2-owner-integration-pack\compiled'
}
$compiledFull = [IO.Path]::GetFullPath($CompiledDirectory)

$paths = [ordered]@{
    trace = Join-Path $root 'src\Adapters\FF7RemakeIntergrade\R3DSSGITraceE2AA_ps.hlsl'
    denoise = Join-Path $root 'src\Effects\Lighting\R3DSSGIDenoise_SM5.hlsl'
    composite = Join-Path $root 'src\Adapters\FF7RemakeIntergrade\R3DSSGICompositeE2AA_ps.hlsl'
    donorTrace = Join-Path $root 'reference\external\r3d\shaders\prepare\ssgi.frag'
    donorDenoise = Join-Path $root 'reference\external\r3d\shaders\prepare\denoiser_atrous.frag'
    donorSampling = Join-Path $root 'reference\external\r3d\shaders\include\lib\sampling.glsl'
    donorAmbient = Join-Path $root 'reference\external\r3d\shaders\deferred\ambient.frag'
    nativeE2aa = Join-Path $root 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\assembly\e2aa1c8cb39e0a55-ps.asm'
}
foreach ($path in $paths.Values) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required sampling evidence is missing: $path" }
}

$trace = Get-Content -Raw -LiteralPath $paths.trace
$denoise = Get-Content -Raw -LiteralPath $paths.denoise
$composite = Get-Content -Raw -LiteralPath $paths.composite
$donorTrace = Get-Content -Raw -LiteralPath $paths.donorTrace
$donorDenoise = Get-Content -Raw -LiteralPath $paths.donorDenoise
$donorSampling = Get-Content -Raw -LiteralPath $paths.donorSampling
$donorAmbient = Get-Content -Raw -LiteralPath $paths.donorAmbient
$nativeE2aa = Get-Content -Raw -LiteralPath $paths.nativeE2aa
$compiledPaths = [ordered]@{
    trace = Join-Path $compiledFull 'Agent2R3DSSGITraceE2AA_ps.asm'
    denoise = Join-Path $compiledFull 'Agent2R3DSSGIDenoise16_ps.asm'
    composite = Join-Path $compiledFull 'Agent2R3DSSGICompositeE2AA_ps.asm'
}
foreach ($path in $compiledPaths.Values) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required compiled sampling evidence is missing: $path" }
}
$compiledTrace = Get-Content -Raw -LiteralPath $compiledPaths.trace
$compiledDenoise = Get-Content -Raw -LiteralPath $compiledPaths.denoise
$compiledComposite = Get-Content -Raw -LiteralPath $compiledPaths.composite

function Assert-Pattern([string]$Text, [string]$Pattern, [string]$Label) {
    if ($Text -notmatch $Pattern) { throw "Sampling assertion failed: $Label" }
}

Assert-Pattern $nativeE2aa '(?s)sample_l_indexable\(texture2d\).*?t0\.xyzw.*?mad r2\.xyz, r2\.xyzx, l\(2\.000000, 2\.000000, 2\.000000.*?dp3 r5\.x, r2\.xyzx, r2\.xyzx.*?rsq r5\.x, r5\.x.*?mul r6\.xyz, r2\.xyzx, r5\.xxxx' 'native e2aa decodes t0 as normalize(encoded.xyz * 2 - 1)'
Assert-Pattern $nativeE2aa '(?s)sample_l_indexable\(texture2d\).*?r0\.xyzw.*?t1\.xyzw.*?sample_l_indexable\(texture2d\).*?r3\.xyzw.*?t2\.xyzw.*?add r5\.y, -r0\.x, l\(1\.000000\).*?mul r7\.xyz, r3\.xyzx, r5\.yyyy' 'native e2aa computes receiver diffuse as t2.rgb * (1 - t1.x metallic)'

Assert-Pattern $donorTrace 'texelFetch\(uDepthTex, ivec2\(gl_FragCoord\.xy\), 0\)' 'R3D receiver depth is a point texel fetch'
Assert-Pattern $donorTrace 'V_GetViewPosition\(uDepthTex, sampleUV\)' 'R3D neighbor trace depth uses the UV sampling path'
Assert-Pattern $donorDenoise 'texelFetch\(uSourceTex, pixCoord, 0\)' 'R3D A-trous center color is a point texel fetch'
Assert-Pattern $donorDenoise 'texelFetch\(uSourceTex, sampleCoord, 0\)' 'R3D A-trous neighbor color is a point texel fetch'
Assert-Pattern $donorDenoise 'V_GetViewPosition\(uDepthTex, sampleCoord\)' 'R3D A-trous neighbor depth is a point texel fetch'
Assert-Pattern $donorDenoise 'V_GetViewNormal\(uNormalTex, sampleCoord\)' 'R3D A-trous neighbor normal is a point texel fetch'
Assert-Pattern $donorSampling 'w \*= exp\(-abs\(d - vec4\(refDepth\)\) \* depthSharpness\)' 'R3D half-resolution upsample is depth-aware'
Assert-Pattern $donorAmbient 'gi = S_Upsample\(uSsgiTex, uw\)\.rgb' 'R3D ambient uses the depth-aware SSGI upsample'
Assert-Pattern $donorAmbient 'gi = C_UnTonemap\(gi\) \* uSsgi\.intensity' 'R3D ambient inverse-tonemaps filtered SSGI'
Assert-Pattern $donorAmbient 'io\.rgb \*= kD' 'R3D ambient modulates indirect light by receiver diffuse color'

Assert-Pattern $trace 'Agent2SceneDepth\.Load\(int3\(coord, 0\)\)' 'adapter receiver depth uses Texture2D.Load'
Assert-Pattern $trace 'sampleDepth\s*=\s*Agent2SceneDepth\.SampleLevel' 'adapter neighbor trace preserves R3D linear UV sampling'
Assert-Pattern $trace 'return normalize\(Agent2WorldNormal\.SampleLevel\(.*?\.xyz \* 2\.0 - 1\.0\)' 'adapter matches the native t0 normal decoder'

foreach ($pattern in @(
    'Agent2DenoiseDepth\.Load\(',
    'Agent2DenoiseNormal\.Load\(',
    'Agent2DenoiseSource\.Load\(int3\(centerPixel, 0\)\)',
    'Agent2DenoiseSource\.Load\(int3\(samplePixel, 0\)\)'
)) { Assert-Pattern $denoise $pattern "adapter A-trous point fetch $pattern" }
if ($denoise -match 'Agent2Denoise(?:Source|Normal|Depth)\.SampleLevel') {
    throw 'A-trous source/normal/depth sampling regressed to filtered SampleLevel.'
}
foreach ($pattern in @(
    'Agent2AccumulateUpsampleTap\(p00', 'Agent2AccumulateUpsampleTap\(p10',
    'Agent2AccumulateUpsampleTap\(p01', 'Agent2AccumulateUpsampleTap\(p11',
    'exp\(-depthDifferenceMeters \* depthSharpness\)',
    'receiverDiffuse = albedo \* \(1\.0 - metallic\) \* AGENT2_INV_PI',
    'Agent2UncompressRadiance\(compressed\)'
)) { Assert-Pattern $composite $pattern "adapter composite parity $pattern" }

Assert-Pattern $compiledTrace 'ld_indexable\(texture2d\).*?t112' 'compiled trace point-fetches receiver depth'
foreach ($slot in 110, 111, 112) {
    Assert-Pattern $compiledTrace ("sample_l_indexable\(texture2d\).*?t{0}" -f $slot) "compiled trace retains filtered t$slot neighbor/radiance sampling"
    Assert-Pattern $compiledDenoise ("ld_indexable\(texture2d\).*?t{0}" -f $slot) "compiled A-trous point-fetches t$slot"
}
if ($compiledDenoise -match 'sample_l_indexable\(texture2d\).*?t11[012]') {
    throw 'Compiled A-trous DXBC contains a filtered source/normal/depth sample.'
}
if ([regex]::Matches($compiledComposite, 'ld_indexable\(texture2d\).*?t110').Count -lt 4) {
    throw 'Compiled composite does not contain four point-fetched SSGI upsample taps.'
}
foreach ($slot in 111, 112, 113, 114) {
    Assert-Pattern $compiledComposite ("ld_indexable\(texture2d\).*?t{0}" -f $slot) "compiled composite point-fetches t$slot"
}
Assert-Pattern $compiledComposite '(?m)^\s*exp\s' 'compiled composite contains reconstructed-depth exponential weights'

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    classification = 'native-normal-and-donor-sampling-semantics-verified-live-subviewport-pending'
    nativeNormalDecode = 'normalize(encoded.xyz * 2 - 1)'
    traceSampling = [ordered]@{
        receiverDepth = 'point Texture2D.Load'
        receiverNormal = 'linear UV sample matching donor'
        neighborDepth = 'linear UV sample matching donor'
        neighborNormal = 'linear UV sample matching donor'
        radiance = 'linear UV sample matching donor'
    }
    denoiseSampling = [ordered]@{
        source = 'integer Texture2D.Load'
        depth = 'integer Texture2D.Load'
        normal = 'integer Texture2D.Load'
        purpose = 'avoid fabricated cross-silhouette depth and color taps'
    }
    composite = [ordered]@{
        upsample = 'four point-fetched SSGI taps with reconstructed-depth bilateral weights'
        depthToleranceMeters = 0.05
        inverseTonemap = $true
        receiverDiffuse = 'e2aa t2.rgb * (1 - e2aa t1.x metallic) / pi'
    }
    compiled = [ordered]@{
        traceAssemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $compiledPaths.trace).Hash
        denoise16AssemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $compiledPaths.denoise).Hash
        compositeAssemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $compiledPaths.composite).Hash
    }
    gates = [ordered]@{ liveSubViewportCaptureRequired = $true; runtimeEligible = $false; installed = $false }
    evidence = @($paths.GetEnumerator() | ForEach-Object { [IO.Path]::GetRelativePath($root, $_.Value) })
}

$outputFull = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull)) | Out-Null
[IO.File]::WriteAllText($outputFull, ($report | ConvertTo-Json -Depth 10) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    result = 'pass'
    classification = $report.classification
    output = $outputFull
    runtimeEligible = $false
}
