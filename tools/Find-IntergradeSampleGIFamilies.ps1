[CmdletBinding()]
param(
    [string]$AssemblyDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\assembly'),
    [string]$RebirthSampleGIPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'reference\external\shader-injector-v2.2.1\maximum-quality\shader-injector-2-2-1-maximum-dood\ShaderInjector\ModifiedShaders\Includes\ComputeShaderPass_SampleGI.hlsl'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\ff7-remake-intergrade-sample-gi-family-scan.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$assembly = [IO.Path]::GetFullPath($AssemblyDirectory).TrimEnd('\')
$donorPath = [IO.Path]::GetFullPath($RebirthSampleGIPath)
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $assembly.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "AssemblyDirectory must remain under artifacts: $assembly" }
if (-not $output.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "OutputPath must remain under artifacts: $output" }
foreach ($required in @($assembly,$donorPath)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required input is missing: $required" }
}

$donor = Get-Content -Raw -LiteralPath $donorPath
$donorPatterns = [ordered]@{
    GBufferA = 'Texture2D<float4>\s+GBufferATexture\s*:\s*register\(t0'
    GBufferB = 'Texture2D<float4>\s+GBufferBTexture\s*:\s*register\(t1'
    GBufferD = 'Texture2D<float4>\s+GBufferDTexture\s*:\s*register\(t2'
    SceneDepth = 'Texture2D<float4>\s+SceneDepthTexture\s*:\s*register\(t3'
    IrradianceA = 'RWTexture2D<float4>\s+RWEnvironmentIrradianceATexture\s*:\s*register\(u0'
    IrradianceB = 'RWTexture2D<float4>\s+RWEnvironmentIrradianceBTexture\s*:\s*register\(u1'
    ThreadGroup = '\[numthreads\(8,\s*8,\s*1\)\]'
    ShadingModelDecode = 'packedShadingModel\s*=\s*\(uint\)round\(gBufferB\.a\s*\*\s*255\.0f\)'
    CharacterBranch = 'SHADINGMODELID_HAIR[\s\S]+SHADINGMODELID_EYE[\s\S]+SHADINGMODELID_PREINTEGRATED_SKIN'
}
foreach ($entry in $donorPatterns.GetEnumerator()) {
    if ($donor -notmatch $entry.Value) { throw "Pinned Rebirth SampleGI evidence changed: $($entry.Key)" }
}

function Count-Matches([string]$Text,[string]$Pattern) { return [regex]::Matches($Text,$Pattern).Count }

$candidates = foreach ($file in @(Get-ChildItem -LiteralPath $assembly -File -Filter '*-cs.asm' | Sort-Object Name)) {
    $text = Get-Content -Raw -LiteralPath $file.FullName
    $texture2D = Count-Matches $text '(?m)^dcl_resource_texture2d\s'
    $resourceBuffer = Count-Matches $text '(?m)^dcl_resource_(?:buffer|structured|raw)\s'
    $resourceTotal = Count-Matches $text '(?m)^dcl_resource_'
    $float4TextureUav = Count-Matches $text '(?m)^dcl_uav_typed_texture2d \(float,float,float,float\) u\d+'
    $uavTotal = Count-Matches $text '(?m)^dcl_uav_'
    $threadMatch = [regex]::Match($text,'(?m)^dcl_thread_group\s+(\d+),\s*(\d+),\s*(\d+)')
    $threadGroup = if ($threadMatch.Success) { @([int]$threadMatch.Groups[1].Value,[int]$threadMatch.Groups[2].Value,[int]$threadMatch.Groups[3].Value) } else { @() }
    $threadExact = $threadGroup.Count -eq 3 -and $threadGroup[0] -eq 8 -and $threadGroup[1] -eq 8 -and $threadGroup[2] -eq 1
    $shadingDecode = $text -match 'l\(255\.000000\)' -and $text -match '(?m)^and\s+[^\r\n]+l\(15\)'
    $storesU0 = $text -match '(?m)^store_uav_typed\s+u0\.'
    $storesU1 = $text -match '(?m)^store_uav_typed\s+u1\.'
    $exact = $texture2D -eq 4 -and $resourceBuffer -eq 0 -and $float4TextureUav -eq 2 -and $uavTotal -eq 2 -and $threadExact -and $shadingDecode -and $storesU0 -and $storesU1
    $score = 0
    if ($resourceTotal -eq 4) { $score += 1 }
    if ($texture2D -eq 4) { $score += 4 }
    if ($uavTotal -eq 2) { $score += 1 }
    if ($float4TextureUav -eq 2) { $score += 4 }
    if ($threadExact) { $score += 2 }
    if ($shadingDecode) { $score += 2 }
    if ($storesU0 -and $storesU1) { $score += 2 }
    [ordered]@{
        hash = ($file.BaseName -replace '-cs$','').ToLowerInvariant()
        stage = 'cs_5_0'
        resourceTexture2DCount = $texture2D
        resourceBufferCount = $resourceBuffer
        resourceTotalCount = $resourceTotal
        float4TextureUavCount = $float4TextureUav
        uavTotalCount = $uavTotal
        threadGroup = $threadGroup
        shadingModelDecode = $shadingDecode
        storesU0 = $storesU0
        storesU1 = $storesU1
        compatibilityScore = $score
        exactStructuralMatch = $exact
        assemblyPath = [IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/')
        assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
    }
}

$exactMatches = @($candidates | Where-Object exactStructuralMatch)
$nearMatches = @($candidates | Where-Object { -not $_.exactStructuralMatch -and $_.compatibilityScore -ge 4 } | Sort-Object -Property @{Expression='compatibilityScore';Descending=$true},hash)
$report = [ordered]@{
    schemaVersion = 1
    detector = 'ff7-remake-dxbc-sample-gi-binding-v1'
    scope = 'Read-only structural scan of one verified 184-shader Remake regional capture against the pinned Rebirth SampleGI resource/dataflow contract.'
    donor = [ordered]@{
        family = 'SampleGI'
        api = 'D3D12'
        stage = 'cs_6_6'
        sourcePath = [IO.Path]::GetRelativePath($root,$donorPath).Replace('\','/')
        sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $donorPath).Hash
        contract = [ordered]@{
            resources = @('t0 GBufferA texture2D','t1 GBufferB texture2D','t2 GBufferD texture2D','t3 SceneDepth texture2D')
            outputs = @('u0 EnvironmentIrradianceA float4 texture2D','u1 EnvironmentIrradianceB float4 texture2D')
            threadGroup = @(8,8,1)
            semanticRequirements = @('packed shading-model decode','unlit early output','skin/hair/eye branch','paired radiance and irradiance writes')
        }
    }
    capture = [ordered]@{
        assemblyDirectory = [IO.Path]::GetRelativePath($root,$assembly).Replace('\','/')
        computeShaderCount = $candidates.Count
    }
    exactCompatibleCount = $exactMatches.Count
    exactCompatibleMatches = $exactMatches
    nearMatchCount = $nearMatches.Count
    nearMatches = $nearMatches
    allCandidates = $candidates
    conclusion = if ($exactMatches.Count) {
        'At least one current-region Remake compute shader satisfies the strict SampleGI structural contract; semantic/manual validation is still required before transformation.'
    } else {
        'No compute shader in the current 184-shader regional capture satisfies the strict SampleGI contract. This is missing regional evidence, not proof that Remake lacks the pass.'
    }
    policy = [ordered]@{
        exactMatch = 'Queue for manual binding/dataflow validation; do not patch from structure alone.'
        nearMatch = 'Retain as negative evidence. Resource-kind or output-kind mismatches disqualify automatic SampleGI transformation.'
        noMatch = 'Capture later regions and merge new shaders before concluding the family is absent.'
    }
}

[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,(($report | ConvertTo-Json -Depth 14)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{
    ComputeShaders = $candidates.Count
    ExactCompatible = $exactMatches.Count
    NearMatches = $nearMatches.Count
    TopNearMatch = if ($nearMatches.Count) {$nearMatches[0].hash} else {''}
    Output = $output
}
