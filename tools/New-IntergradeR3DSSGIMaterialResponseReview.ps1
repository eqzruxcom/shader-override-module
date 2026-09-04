[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-material-response-review'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if (-not $output.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase)) {
    throw "Material-response output escaped the project: $output"
}

$sourcePath = Join-Path $root 'src\Adapters\FF7RemakeIntergrade\R3DSSGICompositeE2AA_ps.hlsl'
$decompilePath = Join-Path $root 'artifacts\captured-shaders\e2aa1c8cb39e0a55-ps\e2aa1c8cb39e0a55-ps_decompiled.txt'
$rebirthPath = Join-Path $root 'reference\external\shader-injector-v2.2.1\maximum-quality\shader-injector-2-2-1-maximum-dood\ShaderInjector\ModifiedShaders\Includes\ComputeShaderPass_ReflectionEnvironment.hlsl'
$expected = [ordered]@{
    $sourcePath = '6FA6F547AED1E490FD8D85DB465B7C70E9FEBD00B2319AF1B86AB9767199AA95'
    $decompilePath = 'E82E8D7A5EF91FD954B50A95CBC250B08F43B28C91450B9EC2106A82478A6716'
    $rebirthPath = 'CEBA077018F2ACBD48A86AEF82CD603B8F219C71E501947AE3E88129A715164B'
}
foreach ($entry in $expected.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Key -PathType Leaf)) { throw "Missing review input: $($entry.Key)" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Key).Hash
    if ($actual -ne $entry.Value) { throw "Review input drifted: $($entry.Key) expected $($entry.Value), found $actual" }
}
if (-not (Test-Path -LiteralPath $FxcPath -PathType Leaf)) { throw "FXC is missing: $FxcPath" }

$decompile = Get-Content -Raw -LiteralPath $decompilePath
foreach ($pattern in @(
    'r0\.xyzw\s*=\s*t1\.SampleLevel',
    'r0\.w\s*=\s*r0\.w \* 255 \+ 0\.5',
    'r1\.x\s*=\s*\(int\)r0\.w & 15',
    'if \(r1\.x != 0\)'
)) {
    if ($decompile -notmatch $pattern) { throw "Remake shading-model evidence changed: $pattern" }
}
$rebirth = Get-Content -Raw -LiteralPath $rebirthPath
foreach ($pattern in @(
    'float\s+ssgiBoost\s*=\s*MATH_PI',
    'SHADINGMODELID_HAIR',
    'SHADINGMODELID_EYE',
    'SHADINGMODELID_PREINTEGRATED_SKIN',
    'ssgiBoost\s*=\s*1\.0f'
)) {
    if ($rebirth -notmatch $pattern) { throw "Rebirth material-response evidence changed: $pattern" }
}

$source = Get-Content -Raw -LiteralPath $sourcePath
$constantNeedle = 'static const float AGENT2_INV_PI = 0.31830988618;'
$metalNeedle = '    float metallic = saturate(Agent2CompositeMaterial.Load(int3(Agent2CompositeCoord(centerUV, materialWidth, materialHeight), 0)).x);'
$diffuseNeedle = '    float3 receiverDiffuse = albedo * (1.0 - metallic) * AGENT2_INV_PI;'
foreach ($needle in @($constantNeedle,$metalNeedle,$diffuseNeedle)) {
    if ([regex]::Matches($source,[regex]::Escape($needle)).Count -ne 1) { throw "Canonical replacement anchor changed: $needle" }
}

$variant = $source.Replace($constantNeedle, $constantNeedle + [Environment]::NewLine + 'static const float AGENT2_PI = 3.14159265359;')
$variant = $variant.Replace($metalNeedle, @'
    float4 material = Agent2CompositeMaterial.Load(int3(Agent2CompositeCoord(centerUV, materialWidth, materialHeight), 0));
    float metallic = saturate(material.x);
    uint shadingModel = ((uint)round(saturate(material.w) * 255.0)) & 0xFu;
    // Match the native e2aa branch: unlit pixels do not receive this indirect pass.
    if (shadingModel == 0u)
        return 0.0;
'@.TrimEnd("`r","`n"))
$variant = $variant.Replace($diffuseNeedle, @'
    // Rebirth keeps ordinary lit surfaces at its visible environmental strength,
    // but reduces the response on character skin, hair, and eyes.
    float materialBoost = AGENT2_PI;
    if (shadingModel == 3u || shadingModel == 7u || shadingModel == 9u)
        materialBoost = 0.25;
    float3 receiverDiffuse = albedo * (1.0 - metallic) * AGENT2_INV_PI * materialBoost;
'@.TrimEnd("`r","`n"))

[IO.Directory]::CreateDirectory($output) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$hlslPath = Join-Path $output 'Agent2R3DSSGICompositeMaterialAware_ps.hlsl'
$objectPath = Join-Path $output 'Agent2R3DSSGICompositeMaterialAware_ps.obj'
$assemblyPath = Join-Path $output 'Agent2R3DSSGICompositeMaterialAware_ps.asm'
$temporaryObject = Join-Path $output ('.material-aware.' + [guid]::NewGuid().ToString('N') + '.tmp')
[IO.File]::WriteAllText($hlslPath,$variant,$utf8)
try {
    $messages = & $FxcPath /nologo /T ps_5_0 /E main /Ges /WX /O3 /Fo $temporaryObject /Fc $assemblyPath $hlslPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "FXC failed: $($messages -join ' ')" }
    $bytes = [IO.File]::ReadAllBytes($temporaryObject)
    if ($bytes.Length -lt 4 -or [Text.Encoding]::ASCII.GetString($bytes,0,4) -ne 'DXBC') { throw 'Material-aware output is not DXBC.' }
    [IO.File]::Copy($temporaryObject,$objectPath,$true)
}
finally {
    if (Test-Path -LiteralPath $temporaryObject -PathType Leaf) { Remove-Item -LiteralPath $temporaryObject -Force }
}

$assembly = Get-Content -Raw -LiteralPath $assemblyPath
foreach ($binding in @('Agent2FilteredSSGI','Agent2CompositeMaterial','Agent2CompositeAlbedo','RemakeView')) {
    if ($assembly -notmatch ('(?m)^//\s+' + [regex]::Escape($binding) + '\s+')) { throw "Compiled variant is missing $binding." }
}

$manifest = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    classification = 'offline-material-aware-ssgi-response-review-not-installed'
    shaderHash = 'e2aa1c8cb39e0a55'
    source = [ordered]@{
        canonicalSha256 = $expected[$sourcePath]
        remakeDecompileSha256 = $expected[$decompilePath]
        rebirthReferenceSha256 = $expected[$rebirthPath]
    }
    response = [ordered]@{
        shadingModelEncoding = 'round(saturate(t1.w) * 255) & 0xF'
        unlit0 = 'zero SSGI receiver contribution, matching native e2aa branch'
        preintegratedSkin3 = 'quarter-scale character response after 1/pi conversion'
        hair7 = 'quarter-scale character response after 1/pi conversion'
        eye9 = 'quarter-scale character response after 1/pi conversion'
        otherLit = 'pi boost after 1/pi Lambertian conversion'
        metallic = 't1.x'
        baseColor = 't2.rgb'
    }
    compile = [ordered]@{
        profile = 'ps_5_0'
        entryPoint = 'main'
        flags = @('/Ges','/WX','/O3')
        hlslSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hlslPath).Hash
        objectSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectPath).Hash
        assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assemblyPath).Hash
    }
    policy = [ordered]@{
        iniEmitted = $false
        keyBindingEmitted = $false
        liveFilesTouched = $false
        runtimeEligible = $false
        installed = $false
    }
}
$manifestPath = Join-Path $output 'manifest.json'
[IO.File]::WriteAllText($manifestPath,(($manifest | ConvertTo-Json -Depth 12)+[Environment]::NewLine),$utf8)

[pscustomobject]@{
    Result = 'pass'
    Classification = $manifest.classification
    ShaderCompiled = $true
    UnlitMasked = $true
    CharacterModelsReduced = '3,7,9 at 0.25 material boost'
    Installed = $false
    RuntimeEligible = $false
    Output = $manifestPath
}
