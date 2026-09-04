[CmdletBinding()]
param(
    [string]$CensusRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-live-compute-census-20260903-v3'),
    [string]$RuntimeProof = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\live-light-f2-runtime-proof-20260903.json'),
    [string]$HelixShader = (Join-Path (Split-Path -Parent $PSScriptRoot) 'reference\HelixMod-FF7R\FixFiles\ShaderFixes\adb544f9a11d6c7e-cs.txt'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-unshadowed-local-light-coverage-20260904.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$census = [IO.Path]::GetFullPath($CensusRoot).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $census.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'CensusRoot must remain under artifacts' }
if (-not $output.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'OutputPath must remain under artifacts' }

$shaderPath = Join-Path $census 'adb544f9a11d6c7e-cs.asm'
foreach ($path in @($shaderPath,$RuntimeProof,$HelixShader)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required evidence missing: $path" }
}
$asm = Get-Content -Raw -LiteralPath $shaderPath
$helix = Get-Content -Raw -LiteralPath $HelixShader
$runtime = Get-Content -Raw -LiteralPath $RuntimeProof | ConvertFrom-Json

$checks = [ordered]@{
    computeSM5 = $asm -match '(?m)^cs_5_0\s*$'
    tiled16x16 = $asm -match '(?m)^dcl_thread_group 16, 16, 1\s*$'
    sharedLightIndexList = $asm -match '(?m)^dcl_tgsm_structured g3, 4, 256\s*$' -and $asm -match 'store_structured g3\.x'
    dynamicLightArrays = $asm -match 'dcl_constantbuffer CB2\[768\], dynamicIndexed' -and $asm -match 'dcl_constantbuffer CB3\[768\], dynamicIndexed'
    tiledLightCullPositionRadius = $asm -match 'cb3\[r\d+\.x \+ 256\]\.xyzx' -and $asm -match 'cb3\[r\d+\.x \+ 256\]\.w'
    receiverDepthReconstruction = $asm -match 'cb1\[57\]' -and $asm -match 'cb1\[40\]\.xyzw' -and $asm -match 'cb1\[43\]\.xyzw'
    normalAndShadingModel = $asm -match 't0\.xwyz' -and $asm -match 'and r\d+\.x, r\d+\.x, l\(15\)'
    localPositionRadius = $asm -match 'cb3\[r\d+\.w \+ 0\]\.xyzx' -and $asm -match 'cb3\[r\d+\.w \+ 0\]\.w'
    lightColor = $asm -match 'cb3\[r\d+\.w \+ 512\]\.xyzx'
    distanceAttenuationMode = $asm -match 'cb2\[r\d+\.w \+ 512\]\.w' -and $asm -match 'cb2\[r\d+\.w \+ 512\]\.z'
    lambertDiffuse = $asm -match 'l\(0\.318309873\)'
    priorLightingRead = $asm -match 'ld_indexable\(texture2d\).*t3\.xyzw'
    lightingWrite = $asm -match 'store_uav_typed u0\.xyzw'
    noShadowArrayInput = $asm -notmatch 'dcl_resource_texture2darray'
    fourTextureInputsOnly = ([regex]::Matches($asm,'(?m)^dcl_resource_texture2d \(float,float,float,float\) t\d+\s*$').Count -eq 4)
    helixLights2Classification = $helix -match '(?m)^// MANUALLY DUMPED .*_09_Lights2.*Clipping CS 3\.'
}
$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count -ne 0) { throw "Unshadowed-light structural contract failed: $($failed -join ', ')" }

$cohort = @()
Get-ChildItem -LiteralPath $census -Filter '*-cs.asm' -File | ForEach-Object {
    $text = Get-Content -Raw -LiteralPath $_.FullName
    if ($text -match 'dcl_tgsm_structured g\d+, 4, 256' -and
        $text -match 'dcl_thread_group 16, 16, 1' -and
        $text -match 'dcl_constantbuffer (?:CB|cb)\d+\[768\], dynamicIndexed' -and
        [regex]::Matches($text,'(?im)^dcl_resource_texture2d \(float,float,float,float\) t\d+\s*$').Count -eq 4) {
        $cohort += $_.BaseName
    }
}
$cohort = @($cohort | Sort-Object -Unique)
if (($cohort -join ',') -ne 'adb544f9a11d6c7e-cs') { throw "Unshadowed-light structural cohort changed: $($cohort -join ',')" }

$runtimeEntry = $runtime.otherRuntimeEvidence.speculativeUnshadowedDirectDiffuse
if ($runtimeEntry.hash -ne 'adb544f9a11d6c7e' -or $runtimeEntry.present -ne $false) {
    throw 'Retained runtime proof no longer records adb544 as absent in that scene'
}

$report = [ordered]@{
    schemaVersion = 1
    detector = 'ff7-remake-unshadowed-local-light-coverage-v1'
    scope = 'Structural ownership boundary for adb544f9a11d6c7e and its relationship to the five shadow/contact-enabled tiled-light variants.'
    shader = [ordered]@{
        hash = 'adb544f9a11d6c7e'
        stage = 'cs_5_0'
        assembly = [IO.Path]::GetRelativePath($root,$shaderPath).Replace('\','/')
        assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $shaderPath).Hash
        helixReference = [IO.Path]::GetRelativePath($root,[IO.Path]::GetFullPath($HelixShader)).Replace('\','/')
        helixReferenceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $HelixShader).Hash
    }
    structuralChecks = $checks
    retainedCensusCohort = [ordered]@{
        count = $cohort.Count
        shaders = $cohort
        meaning = 'It is the only retained compute shader with this exact four-input, 16x16, 256-entry tiled-light culling skeleton.'
    }
    classification = [ordered]@{
        role = 'unshadowed tiled local-light diffuse evaluator candidate'
        confidence = 'high structural; runtime ownership pending'
        evidence = @(
            'builds a per-tile light index list from position and radius data',
            'reconstructs receiver position and normal/shading model',
            'evaluates per-light distance attenuation and Lambert diffuse',
            'reads prior lighting from t3 and writes the accumulated lighting UAV',
            'declares no shadow-map array or contact-shadow input',
            'the original Helix package classified the same hash under its Lights2 clipping family'
        )
        relationToAcceptedFive = 'parallel no-shadow local-light path, not a sixth material bucket in the shadow/contact-enabled five-dispatch sequence'
    }
    runtimeBoundary = [ordered]@{
        capturedScenePresent = $false
        retainedScene = $runtime.captureContext
        implication = 'Its absence proves only that the parked red-beacon scene did not dispatch this path; it does not prove the shader is unused elsewhere.'
        automaticPatchEligible = $false
    }
    nextLiveEvidenceGate = @(
        'Use an area containing visibly unshadowed movable/local lights and record whether adb544 dispatches.',
        'If it executes, capture its indirect-dispatch argument source, target resource, and position relative to the five shadow/contact evaluators.',
        'Use an isolated diagnostic that changes only adb544 contribution; verify character, wall, and ground ownership before porting any falloff/contact transform.',
        'Keep it outside the accepted five-shader automatic family unless a formal shared transform contract is proven.'
    )
    safetyPolicy = [ordered]@{
        liveInstall = 'deferred while the user sleeps'
        action = 'classification only; no replacement or key binding generated'
        keys = 'F10 reload only; F2 indirect-light test only; Page Up/Page Down unchanged'
    }
}

[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,(($report | ConvertTo-Json -Depth 12)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Result='pass'; Hash=$report.shader.hash; Cohort=$report.retainedCensusCohort.count; RuntimeOwned=$report.runtimeBoundary.capturedScenePresent; Output=$output }
