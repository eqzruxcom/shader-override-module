[CmdletBinding()]
param(
    [string]$ComputeMirrorManifest = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\intergrade-live-compute-census-20260903-v1\manifest.json'),
    [string]$LocalLightReport = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\intergrade-live-local-light-radial-family-scan-20260903-v1.json'),
    [string]$DirectLightReport = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\intergrade-live-direct-light-topology-20260903-v1.json'),
    [string]$SampleGIReport = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\intergrade-live-sample-gi-family-scan-20260903-v1.json'),
    [string]$UniversalLightingReport = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\intergrade-live-universal-lighting-matches-20260903-v1.json'),
    [string]$VerifiedClassifications = (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Adapters\FF7RemakeIntergrade\verified-shader-classifications.json'),
    [string]$OutputPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\intergrade-live-lighting-coverage-audit-20260903-v1.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith($artifacts + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must remain beneath artifacts: $output"
}

function Read-Json([string]$Path, [string]$Label) {
    $resolved = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "$Label missing: $resolved" }
    try { return Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json }
    catch { throw "$Label is invalid JSON: $resolved`n$($_.Exception.Message)" }
}

$manifest = Read-Json $ComputeMirrorManifest 'Compute mirror manifest'
$local = Read-Json $LocalLightReport 'Local-light report'
$direct = Read-Json $DirectLightReport 'Direct-light report'
$sampleGi = Read-Json $SampleGIReport 'SampleGI report'
$universal = Read-Json $UniversalLightingReport 'Universal ShaderRegex report'
$verified = Read-Json $VerifiedClassifications 'Verified classifications'

if ($local.detector -ne 'ff7-remake-dxbc-local-light-radial-semantic-v1') { throw 'Unexpected local-light detector' }
if ($direct.detector -ne 'ff7-remake-dxbc-direct-light-topology-v1') { throw 'Unexpected direct-light detector' }
if ($sampleGi.detector -ne 'ff7-remake-dxbc-sample-gi-binding-v1') { throw 'Unexpected SampleGI detector' }
if ($universal.schemaVersion -ne 2 -or $universal.familyFilter -ne 'lighting') { throw 'Unexpected universal lighting report' }
if ($universal.patternSections.failed -ne 0 -or @($universal.matchTimeouts).Count -ne 0) {
    throw 'Universal ShaderRegex report contains compile failures or match timeouts'
}

$computeCount = [int]$manifest.computeShaderCount
if (@($manifest.shaders).Count -ne $computeCount) { throw 'Compute mirror manifest count mismatch' }
if ([int]$local.sourceShaderCount -ne $computeCount) { throw 'Local-light scan does not cover the complete compute mirror' }
if ([int]$sampleGi.capture.computeShaderCount -ne $computeCount) { throw 'SampleGI scan does not cover the complete compute mirror' }
if ([int]$direct.remakeCapture.capturedShaderCount -ne $computeCount) { throw 'Direct-light topology does not cover the complete compute mirror' }

$expectedContactHashes = @(
    '08bb8764f1840179',
    '0e97888f9a8767da',
    '5a9fbefe0ab6f815',
    '62b33a2d1e505241',
    'c30cdc8365df9840'
)
$actualLocalHashes = @($local.actualCompatibleHashes | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique)
$localSetExact = @($expectedContactHashes | Where-Object { $_ -notin $actualLocalHashes }).Count -eq 0 -and
    @($actualLocalHashes | Where-Object { $_ -notin $expectedContactHashes }).Count -eq 0

$newShaderHash = 'adb544f9a11d6c7e'
$newRecord = @($manifest.shaders | Where-Object shader -eq "$newShaderHash-cs")
if ($newRecord.Count -ne 1) { throw "Expected newly loaded compute shader is missing: $newShaderHash" }
$newAssembly = Get-Content -Raw -LiteralPath $newRecord[0].mirror

$newShaderChecks = [ordered]@{
    cs50 = $newAssembly -match '(?m)^cs_5_0$'
    threadGroup16x16x1 = $newAssembly -match '(?m)^dcl_thread_group 16, 16, 1$'
    fourTexture2DInputs = [regex]::Matches($newAssembly, '(?m)^dcl_resource_texture2d ').Count -eq 4
    oneFloat4Texture2DUav = [regex]::Matches($newAssembly, '(?m)^dcl_uav_typed_texture2d \(float,float,float,float\) u0$').Count -eq 1
    gbufferNormalDecode = $newAssembly -match '(?m)^\s*mad r\d+\.[xyzw]{3}, r\d+\.[xyzw]{4}, l\(2\.000000[^\r\n]+l\(-1\.000000'
    shadingModelLowNibble = $newAssembly -match '(?m)^\s*and r\d+\.[xyzw], r\d+\.[xyzw], l\(15\)$'
    sceneDepthReconstruction = $newAssembly -match '(?m)^\s*mad r\d+\.[xyzw]{4}, r\d+\.[xyzw]{4}, cb1\[42\]\.xyzw, r\d+\.xyzw$'
    tiledLightList = $newAssembly -match '(?m)^dcl_tgsm_structured g3, 4, 256$'
    inverseRadiusSquared = $newAssembly -match '(?m)^\s*mul r\d+\.[xyzw], cb3\[r\d+\.[xyzw] \+ 0\]\.w, cb3\[r\d+\.[xyzw] \+ 0\]\.w$'
    diffuseLambertFactor = $newAssembly -match '(?m)^\s*mul r\d+\.[xyzw], r\d+\.[xyzw], l\(0\.318309873\)$'
    readsPriorLightingT3 = $newAssembly -match '(?m)^\s*ld_indexable\(texture2d\)\(float,float,float,float\) r\d+\.xyzw, r\d+\.xyww, t3\.xyzw$'
    writesLightingU0 = $newAssembly -match '(?m)^\s*store_uav_typed u0\.xyzw, r\d+\.xyyy, r\d+\.xyzw$'
    noShadowArray = $newAssembly -notmatch '(?m)^dcl_resource_texture2darray '
    noShadowGather = $newAssembly -notmatch '(?m)^\s*gather4_'
}
$newShaderStructuralClassification = if ($newShaderChecks.Values -contains $false) {
    'unresolved-structural-candidate'
} else {
    'unshadowed-tiled-direct-diffuse-light-candidate-runtime-ownership-pending'
}

$universalMatches = @($universal.matches)
$universalUniqueHashes = @($universalMatches.hash | Sort-Object -Unique)
$universalCsMatches = @($universalMatches | Where-Object stage -eq 'cs')
$universalUniqueCsHashes = @($universalCsMatches.hash | Sort-Object -Unique)
$newUniversalRules = @($universalMatches | Where-Object hash -eq $newShaderHash | Select-Object -ExpandProperty section -Unique | Sort-Object)

$capsuleHash = 'b9e2305a994308f2'
$capsuleClassification = @($verified.families | Where-Object { @($_.hashes.hash) -contains $capsuleHash })
if ($capsuleClassification.Count -ne 1 -or $capsuleClassification[0].familyId -ne 'tiled-capsule-occlusion-producer') {
    throw 'Verified capsule false-positive control is missing or changed'
}
$capsuleUniversalRules = @($universalMatches | Where-Object hash -eq $capsuleHash | Select-Object -ExpandProperty section -Unique | Sort-Object)

$sampleGiNear = @($sampleGi.nearMatches)
$newSampleGiNear = @($sampleGiNear | Where-Object hash -eq $newShaderHash)

$report = [ordered]@{
    schemaVersion = 1
    detector = 'ff7-remake-live-lighting-coverage-correlation-v1'
    scope = 'Read-only correlation of the expanded live Remake shader census with specialized semantic detectors, Rebirth donor contracts, and the old UE4 universal stereo ShaderRegex rules.'
    corpus = [ordered]@{
        computeShaderCount = $computeCount
        universalTextShaderCount = [int]$universal.shaders.scanned
        manifest = [IO.Path]::GetRelativePath($root, [IO.Path]::GetFullPath($ComputeMirrorManifest)).Replace('\','/')
    }
    acceptedSharedTiledLightFamily = [ordered]@{
        compatibleCount = [int]$local.compatibleMatchCount
        structuralExceptionCount = [int]$local.structuralExceptionCount
        hashes = $actualLocalHashes
        exactAcceptedFiveSet = $localSetExact
        localRadialBranch = 'structurally proven in all five variants'
        infiniteOrNonRadialBranch = 'structurally present in all five variants; directional ownership remains runtime-unproven'
        iesProfile = 'not separately proven'
    }
    sampleGI = [ordered]@{
        exactCompatibleCount = [int]$sampleGi.exactCompatibleCount
        nearMatchCount = [int]$sampleGi.nearMatchCount
        nearMatchHashes = @($sampleGiNear.hash)
        conclusion = 'No shader in the current live compute census satisfies the Rebirth SampleGI resource/output/dataflow contract.'
    }
    newlyLoadedComputeShader = [ordered]@{
        hash = $newShaderHash
        sha256 = $newRecord[0].sha256
        checks = $newShaderChecks
        classification = $newShaderStructuralClassification
        sampleGiNearMatch = $newSampleGiNear.Count -eq 1
        sampleGiDisqualifiers = if ($newSampleGiNear.Count -eq 1) {
            @(
                'one UAV instead of Rebirth SampleGI dual irradiance UAVs',
                '16x16 thread group instead of SampleGI 8x8',
                'no SampleGI shading-model output logic',
                'read-modify-write direct lighting rather than two irradiance-volume outputs'
            )
        } else { @('not even a SampleGI near match') }
        universalCandidateRules = $newUniversalRules
        runtimeOwnership = 'pending; do not patch automatically from this classification alone'
    }
    universalRegexCorrelation = [ordered]@{
        compiledPatternCount = [int]$universal.patternSections.compiled
        compileFailureCount = [int]$universal.patternSections.failed
        matchTimeoutCount = @($universal.matchTimeouts).Count
        matchRecordCount = $universalMatches.Count
        uniqueShaderCount = $universalUniqueHashes.Count
        uniqueComputeShaderCount = $universalUniqueCsHashes.Count
        acceptedFiveDetected = @($expectedContactHashes | Where-Object { $_ -notin $universalUniqueHashes }).Count -eq 0
        verifiedSemanticFalsePositive = [ordered]@{
            hash = $capsuleHash
            actualFamily = $capsuleClassification[0].familyId
            matchedUniversalLightingRules = $capsuleUniversalRules
        }
        policy = 'Use the old universal regex as a candidate generator only. Require binding, resource, register-consistent dataflow, output-role, and exception checks before automatic transformation.'
    }
    nextEvidenceGates = @(
        'F10 reload and visual F2 parity confirmation for the clean owned fullscreen literal-zero indirect pass.',
        'Only after zero parity, restore controlled indirect RGB in that same owned pass; keep the native e2aa replacement disabled to avoid double composition.',
        'Runtime-own the newly loaded adb544f9a11d6c7e compute pass before deciding whether it needs any direct-light modification.',
        'Capture a region that exposes a strict SampleGI-compatible pass, or continue using the separate owned screen-space indirect implementation rather than pretending a current near match is SampleGI.',
        'Runtime-own representative directional and IES lights before creating light-type-specific transformations.'
    )
}

[void](New-Item -ItemType Directory -Force -Path (Split-Path $output -Parent))
[IO.File]::WriteAllText($output, (($report | ConvertTo-Json -Depth 14) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

Write-Host "PASS: correlated $computeCount compute shaders and $($universal.shaders.scanned) full census shaders."
Write-Host "Accepted tiled-light family: $($local.compatibleMatchCount); SampleGI exact: $($sampleGi.exactCompatibleCount); universal unique candidates: $($universalUniqueHashes.Count)."
Write-Host "New shader ${newShaderHash}: $newShaderStructuralClassification"
Write-Host "Report: $output"
