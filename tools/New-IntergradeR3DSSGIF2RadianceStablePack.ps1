[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-radiance-stable-pack'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if (-not $output.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Output escaped project: $output" }
if (-not (Test-Path -LiteralPath $FxcPath -PathType Leaf)) { throw "FXC is missing: $FxcPath" }

$baseRoot = Join-Path $root 'artifacts\agent2-r3d-ssgi-f2-material-aware-pack'
$baseManifestPath = Join-Path $baseRoot 'manifest.json'
$traceRelative = 'Mods\Agent2R3DSSGITraceE2AA_ps.hlsl'
$compositeRelative = 'Mods\Agent2R3DSSGICompositeE2AA_ps.hlsl'
$tracePath = Join-Path $baseRoot $traceRelative
$compositePath = Join-Path $baseRoot $compositeRelative
$expected = [ordered]@{
    $baseManifestPath = '50338F67E240BE3A19CBB9E62D8C6EBE3BDD7956252CA063B2CEDEA9DCF6ECCF'
    $tracePath = '862581B946E182EE5C3511D2B163717ADE70B6D6286562A90160EE354F4CD12C'
    $compositePath = '16AA0488061C1BA5BDA5F1E4961C7052B335426DB13A43381D320DF43223D1A7'
}
foreach ($entry in $expected.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Key -PathType Leaf)) { throw "Required input is missing: $($entry.Key)" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Key).Hash
    if ($actual -ne $entry.Value) { throw "Pinned input drifted: $($entry.Key) expected $($entry.Value), found $actual" }
}

$base = Get-Content -Raw -LiteralPath $baseManifestPath | ConvertFrom-Json
if ($base.classification -ne 'offline-f2-standalone-live-topology-candidate' -or
    $base.variant -ne 'material-aware-unlit-mask-and-rebirth-character-response' -or
    $base.target.shader -ne 'e2aa1c8cb39e0a55' -or @($base.files).Count -ne 7 -or
    $base.policy.runtimeEligible -or $base.policy.installed -or $base.policy.gameFilesTouched) {
    throw 'Material-aware base package contract changed.'
}

$trace = Get-Content -Raw -LiteralPath $tracePath
$traceConstant = 'static const float AGENT2_UNREAL_UNITS_TO_METERS = 0.01;'
$traceRadiance = '            float3 radiance = max(0.0, Agent2SceneRadiance.SampleLevel(Agent2LinearClamp, sampleUV, 0).rgb);'
foreach ($needle in @($traceConstant, $traceRadiance)) {
    if ([regex]::Matches($trace, [regex]::Escape($needle)).Count -ne 1) { throw "Trace anchor changed: $needle" }
}
$trace = $trace.Replace($traceConstant, $traceConstant + [Environment]::NewLine + @'
// The copied UE scene color is HDR and includes very bright emissive fixtures.
// Cap a sample while preserving hue so one source cannot dominate every ray.
static const float AGENT2_SOURCE_RADIANCE_CAP = 4.0;
'@.TrimEnd("`r","`n"))
$trace = $trace.Replace($traceRadiance, $traceRadiance + [Environment]::NewLine + @'
            float sourcePeak = max(radiance.x, max(radiance.y, radiance.z));
            radiance *= min(1.0, AGENT2_SOURCE_RADIANCE_CAP / max(sourcePeak, 1e-4));
'@.TrimEnd("`r","`n"))

$composite = Get-Content -Raw -LiteralPath $compositePath
$compositeConstant = 'static const float AGENT2_PI = 3.14159265359;'
$uncompressPattern = 'float3\s+Agent2UncompressRadiance\(float3\s+color\)\s*\{\s*float\s+maximum\s*=\s*max\(color\.x,\s*max\(color\.y,\s*color\.z\)\);\s*return\s+color\s*/\s*max\(1\.0\s*-\s*maximum,\s*1e-4\);\s*\}'
if ([regex]::Matches($composite, [regex]::Escape($compositeConstant)).Count -ne 1) { throw 'Composite constant anchor changed.' }
if ([regex]::Matches($composite, $uncompressPattern).Count -ne 1) { throw 'Composite uncompress anchor changed.' }
$composite = $composite.Replace($compositeConstant, $compositeConstant + [Environment]::NewLine + @'
// Bound reconstructed indirect irradiance after filtering compressed HDR data.
// This prevents near-one compressed values from expanding into white fireflies.
static const float AGENT2_INDIRECT_IRRADIANCE_CAP = 1.0;
'@.TrimEnd("`r","`n"))
$newUncompress = @'
float3 Agent2UncompressRadiance(float3 color)
{
    float maximum = max(color.x, max(color.y, color.z));
    float3 irradiance = color / max(1.0 - maximum, 1e-2);
    float peak = max(irradiance.x, max(irradiance.y, irradiance.z));
    return irradiance * min(1.0, AGENT2_INDIRECT_IRRADIANCE_CAP / max(peak, 1e-4));
}
'@.TrimEnd("`r","`n")
$composite = [regex]::Replace($composite, $uncompressPattern, $newUncompress)

$modsOut = Join-Path $output 'Mods'
$compileOut = Join-Path $output 'compile'
[IO.Directory]::CreateDirectory($modsOut) | Out-Null
[IO.Directory]::CreateDirectory($compileOut) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)

foreach ($entry in @($base.files)) {
    $relative = ([string]$entry.path).Replace('/', '\')
    $source = Join-Path $baseRoot $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash -ne [string]$entry.sha256) {
        throw "Base payload drifted: $relative"
    }
    $destination = Join-Path $output $relative
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    if ($relative -eq $traceRelative) {
        [IO.File]::WriteAllText($destination, $trace, $utf8)
    } elseif ($relative -eq $compositeRelative) {
        [IO.File]::WriteAllText($destination, $composite, $utf8)
    } else {
        [IO.File]::Copy($source, $destination, $true)
    }
}

function Compile-Hlsl([string]$Name, [string]$Path) {
    $object = Join-Path $compileOut ($Name + '.obj')
    $assembly = Join-Path $compileOut ($Name + '.asm')
    $temporary = Join-Path $compileOut ('.' + $Name + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $messages = & $FxcPath /nologo /T ps_5_0 /E main /Ges /WX /O3 /Fo $temporary /Fc $assembly $Path 2>&1
        if ($LASTEXITCODE -ne 0) { throw "FXC failed for ${Name}: $($messages -join ' ')" }
        $bytes = [IO.File]::ReadAllBytes($temporary)
        if ($bytes.Length -lt 4 -or [Text.Encoding]::ASCII.GetString($bytes,0,4) -ne 'DXBC') { throw "$Name did not compile to DXBC." }
        [IO.File]::Copy($temporary,$object,$true)
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
    }
    return [ordered]@{
        name = $Name
        profile = 'ps_5_0'
        objectSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $object).Hash
        assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assembly).Hash
    }
}

$traceOut = Join-Path $output $traceRelative
$compositeOut = Join-Path $output $compositeRelative
$traceCompile = Compile-Hlsl 'Agent2R3DSSGITraceE2AA_ps' $traceOut
$compositeCompile = Compile-Hlsl 'Agent2R3DSSGICompositeE2AA_ps' $compositeOut

$compile = @($base.compile | ForEach-Object {
    if ($_.name -eq 'Agent2R3DSSGITraceE2AA_ps') { $traceCompile }
    elseif ($_.name -eq 'Agent2R3DSSGICompositeE2AA_ps') { $compositeCompile }
    else { [ordered]@{name=[string]$_.name;profile=[string]$_.profile;objectSha256=[string]$_.objectSha256;assemblySha256=[string]$_.assemblySha256} }
})

$manifest = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    classification = 'offline-f2-standalone-live-topology-candidate'
    variant = 'material-aware-bounded-hdr-radiance-v1'
    target = $base.target
    source = [ordered]@{
        materialAwareManifest = 'artifacts\agent2-r3d-ssgi-f2-material-aware-pack\manifest.json'
        materialAwareManifestSha256 = $expected[$baseManifestPath]
        observation = 'Live F2 result changed Cloud and bright fixtures after clean reload; unbounded compressed-HDR expansion was identified in the adapter.'
    }
    baseline = $base.baseline
    effect = [ordered]@{
        algorithm = [string]$base.effect.algorithm
        resolution = [string]$base.effect.resolution
        unrealUnitsToMeters = [double]$base.effect.unrealUnitsToMeters
        depthClear = [double]$base.effect.depthClear
        depthConvention = [string]$base.effect.depthConvention
        sampling = [string]$base.effect.sampling
        denoiseSteps = @($base.effect.denoiseSteps)
        upsample = [string]$base.effect.upsample
        receiverDiffuse = [string]$base.effect.receiverDiffuse
        sourceRadianceCap = 4.0
        reconstructedIrradianceCap = 1.0
        capBehavior = 'peak-preserving hue scale, never per-channel clipping'
        composite = [string]$base.effect.composite
        diagnosticStrength = [double]$base.effect.diagnosticStrength
        highSrvSlotsRestored = @($base.effect.highSrvSlotsRestored)
    }
    controls = $base.controls
    compile = $compile
    files = @(Get-ChildItem -LiteralPath $modsOut -File | Sort-Object Name | ForEach-Object {
        [ordered]@{path=('Mods\' + $_.Name);sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash}
    })
    policy = [ordered]@{
        exactLiveBaselineRequired = $true
        activatesDisabledOwner = $false
        runtimeEligible = $false
        installed = $false
        gameFilesTouched = $false
        liveCaptureRequired = $true
    }
}
$manifestPath = Join-Path $output 'manifest.json'
[IO.File]::WriteAllText($manifestPath,(($manifest | ConvertTo-Json -Depth 16)+[Environment]::NewLine),$utf8)

[pscustomobject]@{
    Result = 'pass'
    Variant = $manifest.variant
    SourceRadianceCap = $manifest.effect.sourceRadianceCap
    ReconstructedIrradianceCap = $manifest.effect.reconstructedIrradianceCap
    PayloadFiles = $manifest.files.Count
    CompiledShaders = 2
    LiveFilesTouched = $false
    RuntimeEligible = $false
    Output = $manifestPath
}
