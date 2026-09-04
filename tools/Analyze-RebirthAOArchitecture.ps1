[CmdletBinding()]
param(
    [string]$PresetAuditPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\rebirth-shader-injector-v2.2.1-preset-audit.json'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\rebirth-v2.2.1-ao-architecture.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')

function Project-Path([string]$Relative) { Join-Path $repoRoot ($Relative -replace '/', '\') }
function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Require-Pattern([string]$Text, [string]$Pattern, [string]$Meaning) {
    Require ([regex]::IsMatch($Text, $Pattern)) "Missing Rebirth AO evidence: $Meaning"
}
function Relative-Path([string]$Path) { ([IO.Path]::GetFullPath($Path)).Substring($repoRoot.Length + 1).Replace('\','/') }

$auditFull = [IO.Path]::GetFullPath($PresetAuditPath)
$outputFull = [IO.Path]::GetFullPath($OutputPath)
Require ($auditFull.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) 'Preset audit must be inside the workspace.'
Require ($outputFull.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) 'Output must remain inside the workspace.'

$audit = Get-Content -Raw -LiteralPath $auditFull | ConvertFrom-Json
$expectedArchiveHashes = [ordered]@{
    Performance = '21C8715F311B1B25CE8C19489F97729F7CBD0846B1A18AF5C976349C74EDE4BA'
    MaximumQuality = 'CED1790992265E203E0DB418203881D5570A58C5AF0663E5F50C05A7996CD119'
}
Require ($audit.Archives.Performance.Sha256 -eq $expectedArchiveHashes.Performance) 'Performance archive provenance changed.'
Require ($audit.Archives.MaximumQuality.Sha256 -eq $expectedArchiveHashes.MaximumQuality) 'Maximum Quality archive provenance changed.'
Require ($audit.Archives.Performance.FileCount -eq 158 -and $audit.Archives.MaximumQuality.FileCount -eq 158) 'Archive file counts changed.'
Require ($audit.Comparison.IdenticalFileCount -eq 143 -and $audit.Comparison.DifferentFileCount -eq 15) 'Preset comparison counts changed.'

$presetRoots = [ordered]@{
    Performance = Project-Path 'reference/external/shader-injector-v2.2.1/performance/shader-injector-2-2-1-performance/ShaderInjector/ModifiedShaders'
    MaximumQuality = Project-Path 'reference/external/shader-injector-v2.2.1/maximum-quality/shader-injector-2-2-1-maximum-dood/ShaderInjector/ModifiedShaders'
}
$sourceRelative = 'Includes\ComputeShaderPass_ReflectionEnvironment.hlsl'
$sources = [ordered]@{}
$sourceHashes = [ordered]@{
    Performance = 'CAC5ED975F537238011B6913126299EEE1F415B4DC4DEE254CCABC597C841BDE'
    MaximumQuality = 'CEBA077018F2ACBD48A86AEF82CD603B8F219C71E501947AE3E88129A715164B'
}
foreach ($preset in $presetRoots.Keys) {
    $path = Join-Path $presetRoots[$preset] $sourceRelative
    Require (Test-Path -LiteralPath $path -PathType Leaf) "$preset ReflectionEnvironment source is missing."
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    Require ($actualHash -eq $sourceHashes[$preset]) "$preset ReflectionEnvironment source hash changed: $actualHash"
    $sources[$preset] = [IO.File]::ReadAllText($path)
}

$featureSpecs = @(
    [pscustomobject]@{ Name='SSGI_AMBIENT_OCCLUSION'; Performance=$false; MaximumQuality=$true },
    [pscustomobject]@{ Name='SSGI_BOUNCE_LIGHT'; Performance=$false; MaximumQuality=$true }
)
foreach ($feature in $featureSpecs) {
    foreach ($preset in $presetRoots.Keys) {
        $enabled = [regex]::IsMatch($sources[$preset], "(?m)^\s*#define\s+$([regex]::Escape($feature.Name))\b")
        Require ($enabled -eq $feature.$preset) "$($feature.Name) state changed in $preset."
    }
}

# The shared ReflectionEnvironment source must differ only by enabling these two
# features. Normalizing those exact lines must make the files byte-for-byte equal.
$normalizedPerformance = $sources.Performance
$normalizedMaximumQuality = $sources.MaximumQuality
foreach ($name in @('SSGI_AMBIENT_OCCLUSION','SSGI_BOUNCE_LIGHT')) {
    $normalizationPattern = "(?m)^\s*(?://\s*)?#define\s+$name\s*$"
    $normalizedPerformance = [regex]::Replace($normalizedPerformance, $normalizationPattern, "#define $name")
    $normalizedMaximumQuality = [regex]::Replace($normalizedMaximumQuality, $normalizationPattern, "#define $name")
}
Require ($normalizedPerformance -ceq $normalizedMaximumQuality) 'ReflectionEnvironment presets differ beyond the two SSGI feature defines.'

$commonPatterns = [ordered]@{
    Stage='(?m)^\[numthreads\(8,\s*8,\s*1\)\]'
    Entry='(?m)^void\s+main\s*\('
    NativeAO='Texture2D<float4>\s+AmbientOcclusionTexture\s*:\s*register\(t10\)'
    Output='RWTexture2D<float4>\s+OutTextureColor\s*:\s*register\(u0\)'
    SSAOPower='#define\s+SSAO_POWER\s+1\.0'
    SSAOBrightness='#define\s+SSAO_BRIGHTNESS\s+1\.0'
    RayCount='#define\s+SSGI_RAY_COUNT\s+1\b'
    StepCount='#define\s+SSGI_RAYMARCHING_STEP_COUNT\s+16\b'
    Width='#define\s+SSGI_RAYMARCHING_WIDTH\s+512\.0'
    Thickness='#define\s+SSGI_THICKNESS\s+75\.0'
    NormalBias='#define\s+SSGI_NORMAL_BIAS\s+0\.0005'
    HairBias='#define\s+SSGI_NORMAL_BIAS_HAIR\s+0\.1'
    HairAO='#define\s+AO_HAIR\s+1\.0'
    GTVB='float4\s+ComputeGTVBGI\s*\('
    NativeFallback='ambientOcclusion\s*\*=\s*saturate\(pow\(gbufferData\.ScreenAO,\s*SSAO_POWER\)\s*\*\s*SSAO_BRIGHTNESS\)'
    SSGIAO='ambientOcclusion\s*\*=\s*saturate\(pow\(ssgi\.a,\s*SSAO_POWER\)\s*\*\s*SSAO_BRIGHTNESS\)'
    MultiBounce='diffuse\s*\*=\s*GTAOMultiBounce\(ambientOcclusion,\s*gbufferData\.BaseColor\)'
}
foreach ($entry in $commonPatterns.GetEnumerator()) { Require-Pattern $sources.MaximumQuality $entry.Value $entry.Key }
Require (-not [regex]::IsMatch($sources.MaximumQuality, '(?m)^\s*#define\s+SSGI_CHECKERBOARD\b')) 'Maximum Quality unexpectedly enables checkerboard SSGI.'
Require (-not [regex]::IsMatch($sources.MaximumQuality, '(?m)^\s*#define\s+SSGI_BASIC_QUAD_DENOISE\b')) 'Maximum Quality unexpectedly enables basic quad denoise.'
Require ([regex]::IsMatch($sources.MaximumQuality, '(?m)^\s*#define\s+RANDOM_ANIMATE_NOISE\b')) 'Maximum Quality no longer animates the SSGI noise.'

$compiledExpected = [ordered]@{
    Performance = [ordered]@{ Length=47140; Sha256='45DEEBA955778BC31C162C2BC78190470E68CCBF76F2506C14E667E98587A0E1' }
    MaximumQuality = [ordered]@{ Length=52528; Sha256='B43F9EA7E8CB7A8D67631D3781C7064C47E97B00911F09B1CA6208E28C2BFAFA' }
}
$compiled = [ordered]@{}
foreach ($preset in $presetRoots.Keys) {
    $blobs = @(Get-ChildItem -LiteralPath $presetRoots[$preset] -Recurse -File -Filter '*ReflectionEnvironment_Compiled.blob' | Sort-Object FullName)
    Require ($blobs.Count -eq 4) "Expected four $preset ReflectionEnvironment blobs."
    $records = foreach ($blob in $blobs) {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $blob.FullName).Hash
        Require ($blob.Length -eq $compiledExpected[$preset].Length) "$preset compiled blob length changed."
        Require ($hash -eq $compiledExpected[$preset].Sha256) "$preset compiled blob hash changed."
        [ordered]@{ path=Relative-Path $blob.FullName; length=$blob.Length; sha256=$hash }
    }
    $compiled[$preset] = @($records)
}

$targets = @($audit.FingerprintInventory.Targets | Where-Object Family -eq 'ReflectionEnvironment' | Sort-Object VersionGroup)
Require ($targets.Count -eq 4) 'ReflectionEnvironment fingerprint target count changed.'
$expectedTargetHashes = @('8EE4A2ED727B9354','B0118AE85F2A8841','E1B12859DD745E06','F6B2E1B7C2560BAB') | Sort-Object
Require (@(Compare-Object $expectedTargetHashes @($targets.TargetHash | Sort-Object)).Count -eq 0) 'ReflectionEnvironment target hashes changed.'
foreach ($target in $targets) {
    Require ($target.ShaderProfile -eq 'cs_6_6' -and $target.Stage -eq 'ComputeShader') "Unexpected target stage/profile: $($target.Name)"
    Require ($target.EntryFunction -eq 'ReflectionEnvironmentCS') "Unexpected reflected entry point: $($target.Name)"
    Require ($target.InterfaceSignatureHash -eq 'CBF29CE484222325') "Interface signature changed: $($target.Name)"
    Require ($target.ResourceSignatureHash -eq 'CFF7B84CE42A6E6B') "Resource signature changed: $($target.Name)"
    Require ($target.ConstantBufferSignatureHash -eq '8399783A452673AE') "Constant-buffer signature changed: $($target.Name)"
    Require ($target.ExecutionSignatureHash -eq '06622E263FC3631E') "Execution signature changed: $($target.Name)"
}

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    scope = 'AO-only, fail-closed comparison of the pinned Rebirth Shader Injector v2.2.1 Performance and Maximum Quality ReflectionEnvironment families.'
    archiveProvenance = [ordered]@{
        Performance = [ordered]@{ path=$audit.Archives.Performance.Path; sha256=$audit.Archives.Performance.Sha256; fileCount=$audit.Archives.Performance.FileCount }
        MaximumQuality = [ordered]@{ path=$audit.Archives.MaximumQuality.Path; sha256=$audit.Archives.MaximumQuality.Sha256; fileCount=$audit.Archives.MaximumQuality.FileCount }
        comparison = [ordered]@{ identicalFiles=143; differentFiles=15; reflectionSourceDiff='exactly SSGI_AMBIENT_OCCLUSION and SSGI_BOUNCE_LIGHT enablement' }
    }
    family = [ordered]@{
        logicalName = 'ReflectionEnvironment'
        hlslEntryPoint = 'main'
        reflectedOriginalEntryPoint = 'ReflectionEnvironmentCS'
        stage = 'cs_6_6'
        threadGroup = @(8,8,1)
        source = [ordered]@{
            Performance = [ordered]@{ path=Relative-Path (Join-Path $presetRoots.Performance $sourceRelative); sha256=$sourceHashes.Performance; features=[ordered]@{ nativeScreenAO=$true; gtvbAO=$false; ssgiBounce=$false } }
            MaximumQuality = [ordered]@{ path=Relative-Path (Join-Path $presetRoots.MaximumQuality $sourceRelative); sha256=$sourceHashes.MaximumQuality; features=[ordered]@{ nativeScreenAO=$true; gtvbAO=$true; ssgiBounce=$true } }
        }
        compiledBlobs = $compiled
        targetFingerprints = @($targets | ForEach-Object { [ordered]@{
            version=$_.VersionGroup; targetHash=$_.TargetHash; originalBytecodeLength=$_.OriginalBytecodeLength;
            crossVersionIdentityHash=$_.CrossVersionIdentityHash; semanticInstructionSetHash=$_.SemanticInstructionSetHash;
            interfaceSignatureHash=$_.InterfaceSignatureHash; resourceSignatureHash=$_.ResourceSignatureHash;
            constantBufferSignatureHash=$_.ConstantBufferSignatureHash; executionSignatureHash=$_.ExecutionSignatureHash;
            portableReflectionIdentityHash=$_.PortableReflectionIdentityHash
        }})
        resources = [ordered]@{ fallbackCubemap='t0'; preintegratedGF='t1'; thinFilm='t2'; gbuffer='t3-t7'; sceneDepth='t8'; ssr='t9'; nativeScreenAO='t10'; ambiguousLight='t11-t12'; environmentIrradiance='t13-t14'; output='u0'; constantBuffers='b0 globals, b1 view'; samplers='s0-s4' }
        maximumQualityGTVB = [ordered]@{ raysPerPixel=1; raymarchSteps=16; maxPixelReach=512.0; worldThickness=75.0; normalBias=0.0005; hairNormalBias=0.1; hairAO=1.0; animatedNoise=$true; checkerboard=$false; quadDenoise=$false; dedicatedHistoryResource=$false; temporalAccumulation='relies on the game TAA blending animated per-frame noise' }
        shadingOrder = @('load GBuffer/depth/native ScreenAO','optionally compute GTVB visibility and bounce','select GTVB AO or native ScreenAO','apply SSAO power/brightness','apply material/character AO rules','derive specular occlusion','apply GTAOMultiBounce to ambient diffuse/specular','add optional SSGI bounce','accumulate into ReflectionEnvironment output')
    }
    remakePortability = [ordered]@{
        portableNow = @('visibility-domain power/brightness semantics','producer-local single application before Remake temporal history selection')
        notPortableByShaderReplacement = @('Rebirth cs_6_6 kernel','Rebirth t3-t14/u0 binding layout','GTVB ray marching','scene-color bounce sampling','material and shading-model branches','specular occlusion/GTAO multibounce composite')
        reason = 'Remake a77b589dce5822d6 is a ps_5_0 temporal SSAO producer with t0-t5 and packed SV_Target output. A replacement cannot invent Rebirth SRV/UAV bindings, dispatch scheduling, or a new temporal/filter chain.'
        currentDecision = 'Keep the offline a77 producer-local power candidates as conservative native-SSAO contrast tuning, not as an SSGI or algorithm-quality port.'
        trueQualityUpgradeGate = @('capture complete Remake GBuffer/depth/scene-color formats and dimensions','identify an injection point before reflection/indirect consumption','provide explicit SRV/UAV bindings and dispatch dimensions','design temporal accumulation/filtering and disocclusion handling','measure GPU cost','cover later-region shader permutations')
    }
    sources = @((Relative-Path $auditFull), (Relative-Path (Join-Path $presetRoots.Performance $sourceRelative)), (Relative-Path (Join-Path $presetRoots.MaximumQuality $sourceRelative)))
}

[void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFull))
[IO.File]::WriteAllText($outputFull, (($report | ConvertTo-Json -Depth 20) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Host "PASS: wrote deterministic Rebirth AO architecture map to $outputFull"
