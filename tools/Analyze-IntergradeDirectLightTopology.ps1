[CmdletBinding()]
param(
    [string]$AssemblyDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\assembly'),
    [string]$RadialReportPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-local-light-radial-family-scan.json'),
    [string]$RebirthLocalLightPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'reference\external\shader-injector-v2.2.1\maximum-quality\shader-injector-2-2-1-maximum-dood\ShaderInjector\ModifiedShaders\Includes\PixelShaderPass_LocalLight.hlsl'),
    [string]$RebirthDirectionalLightPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'reference\external\shader-injector-v2.2.1\maximum-quality\shader-injector-2-2-1-maximum-dood\ShaderInjector\ModifiedShaders\Includes\PixelShaderPass_DirectionalLight.hlsl'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\ff7-remake-intergrade-direct-light-topology.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$assembly = [IO.Path]::GetFullPath($AssemblyDirectory).TrimEnd('\')
$radialReport = [IO.Path]::GetFullPath($RadialReportPath)
$localDonor = [IO.Path]::GetFullPath($RebirthLocalLightPath)
$directionalDonor = [IO.Path]::GetFullPath($RebirthDirectionalLightPath)
$output = [IO.Path]::GetFullPath($OutputPath)

if (-not $assembly.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "AssemblyDirectory must remain under artifacts: $assembly" }
if (-not $output.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "OutputPath must remain under artifacts: $output" }
foreach ($required in @($assembly,$radialReport,$localDonor,$directionalDonor)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required input is missing: $required" }
}

function Assert-Pattern([string]$Text,[string]$Pattern,[string]$Label) {
    if ($Text -notmatch $Pattern) { throw "Pinned direct-light evidence changed: $Label" }
}

$localSource = Get-Content -Raw -LiteralPath $localDonor
$directionalSource = Get-Content -Raw -LiteralPath $directionalDonor
Assert-Pattern $localSource 'Texture2D<float4>\s+LightAttenuationTexture\s*:\s*register\(t9' 'Rebirth local attenuation t9'
Assert-Pattern $localSource 'Texture2D<float4>\s+ClosestHZBTexture\s*:\s*register\(t10' 'Rebirth local HZB t10'
Assert-Pattern $localSource 'SHADER_VARIANT_LOCAL_LIGHT_IES' 'Rebirth IES variant define'
Assert-Pattern $localSource 'DeferredLightUniforms_SourceTexture\s*:\s*register\(t9' 'Rebirth IES profile t9'
Assert-Pattern $localSource 'DeferredLightUniforms_SourceTexture\.Sample' 'Rebirth IES profile sample'
Assert-Pattern $directionalSource 'Texture2D<float4>\s+LightAttenuationTexture\s*:\s*register\(t9' 'Rebirth directional attenuation t9'
Assert-Pattern $directionalSource 'fadedTextureAttenuation' 'Rebirth directional shadow fade'

$radial = Get-Content -Raw -LiteralPath $radialReport | ConvertFrom-Json
if ($radial.detector -ne 'ff7-remake-dxbc-local-light-radial-semantic-v1') { throw 'Unexpected radial detector input' }

$variants = foreach ($match in @($radial.compatibleMatches | Sort-Object hash)) {
    $file = Join-Path $assembly ($match.hash + '-cs.asm')
    if (-not (Test-Path -LiteralPath $file)) { throw "Captured shader missing: $file" }
    $text = Get-Content -Raw -LiteralPath $file
    $texture2DCount = [regex]::Matches($text,'(?m)^dcl_resource_texture2d\s').Count
    $texture2DArrayCount = [regex]::Matches($text,'(?m)^dcl_resource_texture2darray\s').Count
    $structured80 = $text -match '(?m)^dcl_resource_structured t\d+, 80$'
    $shadowArrayGather = $text -match '(?m)^gather4_[^\r\n]+\(texture2darray\)'
    $infiniteAttenuationBypass = @($match.radialBlocks | Where-Object lightTypeBypassParameter).Count -eq 1
    $spotConeTerm = $text -match '(?m)^add r\d+\.[xyzw], r\d+\.[xyzw], -cb3\[r\d+\.[xyzw] \+ 512\]\.x\r?\n\s*mul_sat r\d+\.[xyzw], r\d+\.[xyzw], cb3\[r\d+\.[xyzw] \+ 512\]\.y'
    $priorOutputRead = $text -match '(?m)^\s*ld_indexable\(texture2d\)\(float,float,float,float\) r0\.xyzw, r1\.xyzz, t9\.xyzw\r?\n\s*add r2\.xyz'
    $priorOutputBlend = $text -match '(?m)^\s*mad r0\.xyzw, r0\.xyzw, cb1\[128\]\.yyyy, r2\.xyzw'
    $composition = if ($priorOutputRead -and $priorOutputBlend) { 'read-modify-write-existing-lighting' } elseif (-not $priorOutputRead) { 'direct-write-lighting' } else { 'ambiguous-output-composition' }

    [ordered]@{
        hash = $match.hash
        stage = 'cs_5_0'
        threadGroup = @(16,16,1)
        resourceTexture2DCount = $texture2DCount
        resourceTexture2DArrayCount = $texture2DArrayCount
        structuredLightRecordStride = if ($structured80) { 80 } else { 0 }
        shadowArrayGather = $shadowArrayGather
        localInverseRadiusPath = $match.compatibleRadialBlockCount -eq 1
        infiniteOrNonRadialAttenuationBypass = $infiniteAttenuationBypass
        spotConeTerm = $spotConeTerm
        outputComposition = $composition
        dedicatedIesProfileTextureProven = $false
        assemblyPath = [IO.Path]::GetRelativePath($root,$file).Replace('\','/')
        assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash
    }
}

$readModifyWrite = @($variants | Where-Object outputComposition -eq 'read-modify-write-existing-lighting')
$directWrite = @($variants | Where-Object outputComposition -eq 'direct-write-lighting')
$ambiguous = @($variants | Where-Object outputComposition -eq 'ambiguous-output-composition')
$sharedBranchCount = @($variants | Where-Object { $_.localInverseRadiusPath -and $_.infiniteOrNonRadialAttenuationBypass }).Count

$report = [ordered]@{
    schemaVersion = 1
    detector = 'ff7-remake-dxbc-direct-light-topology-v1'
    scope = 'Read-only comparison of the pinned Rebirth direct-light pixel-shader families with one verified 184-shader Remake regional DX11 capture.'
    rebirthDonor = [ordered]@{
        topology = 'separate directional, local, and local-IES pixel-shader source families'
        localLight = [ordered]@{
            sourcePath = [IO.Path]::GetRelativePath($root,$localDonor).Replace('\','/')
            sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $localDonor).Hash
            normalBindings = @('t9 LightAttenuation','t10 ClosestHZB')
            iesBindings = @('t9 IES/source profile','t10 LightAttenuation','t11 ClosestHZB')
        }
        directionalLight = [ordered]@{
            sourcePath = [IO.Path]::GetRelativePath($root,$directionalDonor).Replace('\','/')
            sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $directionalDonor).Hash
            bindings = @('t9 LightAttenuation')
        }
    }
    remakeCapture = [ordered]@{
        assemblyDirectory = [IO.Path]::GetRelativePath($root,$assembly).Replace('\','/')
        capturedShaderCount = $radial.sourceShaderCount
        verifiedSharedTiledLightVariantCount = $variants.Count
        localAndInfiniteBranchVariantCount = $sharedBranchCount
        readModifyWriteVariantCount = $readModifyWrite.Count
        directWriteVariantCount = $directWrite.Count
        ambiguousCompositionVariantCount = $ambiguous.Count
        variants = $variants
    }
    classification = [ordered]@{
        verifiedFamily = 'shared tiled surface-light compute evaluator'
        localLight = 'verified inside the shared family by position reconstruction, inverse-radius-squared attenuation, cutoff polynomial, and spot-cone term'
        directionalLight = 'not separately proven; every verified variant has an infinite/non-radial attenuation bypass, but the current DXBC cannot name that branch directional without runtime ownership evidence'
        localLightIES = 'not separately proven; no dedicated IES profile texture can be identified in the captured shared family, and IES may be data-driven or absent from this region'
        outputPermutations = @('read-modify-write-existing-lighting','direct-write-lighting')
    }
    conclusions = @(
        'Do not transplant Rebirth register numbers or assume one Remake shader per Rebirth family.',
        'Do not label the optional Remake t9 texture as IES: in three verified variants it is read only at final output composition as the prior lighting buffer.',
        'The five verified Remake shaders are compatible permutations of one shared light-list evaluator, not five independent light types.',
        'A directional or IES transformation must be guarded by per-light branch/data evidence or a runtime ownership capture, not filename/hash proximity.'
    )
    policy = [ordered]@{
        automaticPatch = 'Apply only transformations proven valid for the complete shared evaluator and all compatible variants.'
        lightTypeSpecificPatch = 'Fail closed unless the exact per-light branch discriminator and bindings are proven.'
        missingFamily = 'Capture later regions and runtime-own a representative directional/IES light before concluding absence.'
    }
}

[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,(($report | ConvertTo-Json -Depth 14)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{
    SharedVariants = $variants.Count
    LocalAndInfiniteBranchVariants = $sharedBranchCount
    ReadModifyWrite = $readModifyWrite.Count
    DirectWrite = $directWrite.Count
    Ambiguous = $ambiguous.Count
    Output = $output
}
