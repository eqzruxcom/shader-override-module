[CmdletBinding()]
param(
    [string]$RebirthCatalogPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\rebirth-shader-injector-v2.2.1-family-catalog.json'),
    [string]$RemakeCatalogPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\ff7-remake-intergrade-verified-family-catalog.json'),
    [string]$RegionalAuditPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\lighting-family-audit-summary.json'),
    [string]$SampleGIScanPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\ff7-remake-intergrade-sample-gi-family-scan.json'),
    [string]$DirectLightTopologyPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\ff7-remake-intergrade-direct-light-topology.json'),
    [string]$SSGIPackPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\agent2-r3d-ssgi-f2-radiance-stable-pack\manifest.json'),
    [string]$SSGIReloadStatusPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\agent2-r3d-ssgi-radiance-stable-live-reload-status.json'),
    [string]$OutputPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\intergrade-rebirth-lighting-coverage-gap.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$artifacts = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts'))
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
if (-not $resolvedOutput.StartsWith($artifacts + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must remain beneath $artifacts"
}

function Read-Json([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label not found: $Path" }
    return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Get-RelativeEvidence([string]$Path, [string]$Label) {
    $full = [IO.Path]::GetFullPath($Path)
    return [ordered]@{
        label = $Label
        path = [IO.Path]::GetRelativePath($workspace, $full).Replace('\', '/')
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $full).Hash.ToUpperInvariant()
    }
}

function Require-Family($Catalog, [string]$Id) {
    $matches = @($Catalog.families | Where-Object id -eq $Id)
    if ($matches.Count -ne 1) { throw "Expected exactly one family '$Id'; found $($matches.Count)" }
    return $matches[0]
}

$rebirth = Read-Json $RebirthCatalogPath 'Rebirth family catalog'
$remake = Read-Json $RemakeCatalogPath 'Remake family catalog'
$regional = Read-Json $RegionalAuditPath 'Regional lighting audit'
$sampleGiScan = Read-Json $SampleGIScanPath 'SampleGI structural scan'
$directLightTopology = Read-Json $DirectLightTopologyPath 'Direct-light topology analysis'
$ssgiPack = Read-Json $SSGIPackPath 'Material-aware SSGI pack'
$ssgiStatus = Read-Json $SSGIReloadStatusPath 'Material-aware SSGI reload status'

if ($rebirth.schemaVersion -ne 1 -or $rebirth.kind -ne 'shader-family-catalog') { throw 'Unsupported Rebirth catalog' }
if ($remake.schemaVersion -ne 1 -or $remake.kind -ne 'shader-family-catalog') { throw 'Unsupported Remake catalog' }
if ($rebirth.families.Count -ne 11) { throw "Expected 11 Rebirth families; found $($rebirth.families.Count)" }
if ($remake.families.Count -ne 10) { throw "Expected 10 verified Remake families; found $($remake.families.Count)" }
if ($regional.audit -ne 'ff7-remake-regional-lighting-family-audit-v1') { throw 'Unsupported regional audit' }
if ($regional.scannedShaderCount -ne 184 -or $regional.compatibleLocalLightCount -ne 5) { throw 'Regional capture no longer matches the verified 184-shader/5-local-light baseline' }
if ($regional.structuralExceptionCount -ne 0) { throw 'Regional local-light scan now has structural exceptions' }
if ($sampleGiScan.detector -ne 'ff7-remake-dxbc-sample-gi-binding-v1' -or $sampleGiScan.capture.computeShaderCount -ne 18) { throw 'Unsupported or incomplete SampleGI scan' }
if ($sampleGiScan.exactCompatibleCount -ne 0) { throw 'A SampleGI-compatible shader appeared and requires manual review before regenerating this report' }
if ($directLightTopology.detector -ne 'ff7-remake-dxbc-direct-light-topology-v1') { throw 'Unsupported direct-light topology report' }
if ($directLightTopology.remakeCapture.verifiedSharedTiledLightVariantCount -ne 5 -or $directLightTopology.remakeCapture.localAndInfiniteBranchVariantCount -ne 5) { throw 'Direct-light topology no longer matches the verified five-variant shared evaluator' }
if ($directLightTopology.remakeCapture.ambiguousCompositionVariantCount -ne 0) { throw 'Direct-light output-composition evidence became ambiguous' }
if ($ssgiPack.result -ne 'pass' -or $ssgiPack.target.shader -ne 'e2aa1c8cb39e0a55') { throw 'Material-aware SSGI pack is not the verified e2aa candidate' }

$expectedDonorIds = @(
    'directional-light','local-light','local-light-ies','ocean-a','post-process-final','post-process-fog',
    'reflection-environment','sample-gi','ssr','water-a','water-b'
)
$actualDonorIds = @($rebirth.families.id | Sort-Object)
if (@(Compare-Object ($expectedDonorIds | Sort-Object) $actualDonorIds).Count -ne 0) {
    throw "Unexpected Rebirth family set: $($actualDonorIds -join ', ')"
}

$tiledLight = Require-Family $remake 'tiled-surface-light-evaluation'
$directionalShadow = Require-Family $remake 'directional-cascade-shadow-projection-filter'
$materialGBuffer = Require-Family $remake 'material-gbuffer-producers'
$tiledHashes = @($tiledLight.implementations[0].variants.targets.shaderHash | Sort-Object -Unique)
if ($tiledHashes.Count -ne 5) { throw "Expected five verified tiled surface-light variants; found $($tiledHashes.Count)" }

function Donor-Stage([string]$Id) {
    return [string](Require-Family $rebirth $Id).implementations[0].stage
}

$matrix = @(
    [ordered]@{
        donorFamily = 'DirectionalLight'; donorId = 'directional-light'; donorStage = Donor-Stage 'directional-light'
        remakeEvidence = @($directionalShadow.id,'ff7-remake-dxbc-direct-light-topology-v1:infinite-or-non-radial-bypass')
        classification = 'shared-evaluator-branch-present-directional-ownership-not-yet-proven'
        implication = 'The cascade projection family is separate. The shared tiled evaluator has a proven attenuation-bypass branch for infinite/non-radial lights, but current DXBC cannot name that branch directional without runtime ownership evidence.'
        nextGate = 'Runtime-own a representative directional light and prove its branch discriminator before a type-specific transformation.'
    },
    [ordered]@{
        donorFamily = 'LocalLight'; donorId = 'local-light'; donorStage = Donor-Stage 'local-light'
        remakeEvidence = @($tiledLight.id)
        classification = 'verified-shared-tiled-evaluator-five-regional-variants'
        implication = 'Remake evaluates local lights inside a D3D11 tiled compute family: all five variants reconstruct light position and execute inverse-radius attenuation plus spot-cone shaping.'
        nextGate = 'Apply only transformations valid across the complete shared evaluator, or prove a per-light discriminator and fail closed.'
    },
    [ordered]@{
        donorFamily = 'LocalLightIES'; donorId = 'local-light-ies'; donorStage = Donor-Stage 'local-light-ies'
        remakeEvidence = @($tiledLight.id)
        classification = 'ies-not-separately-proven-inside-shared-tiled-family'
        implication = 'The optional Remake t9 texture is a prior-lighting buffer in three output-composition permutations, not an IES profile. IES may be data-driven within shared light records or absent from this region.'
        nextGate = 'Runtime-own an IES fixture or capture a permutation with a proven profile lookup; do not infer IES from shifted registers.'
    },
    [ordered]@{
        donorFamily = 'ReflectionEnvironment'; donorId = 'reflection-environment'; donorStage = Donor-Stage 'reflection-environment'
        remakeEvidence = @('e2aa1c8cb39e0a55-ps')
        classification = 'verified-adapter-hook-material-aware-runtime-reload-pending'
        implication = 'The architecture differs, but e2aa is a verified ambient/reflection composite hook with native GBuffer, AO, SSR, and material data.'
        nextGate = 'F10 parser/compile verification, then matched F2 still, motion/disocclusion, and performance tests.'
    },
    [ordered]@{
        donorFamily = 'SampleGI'; donorId = 'sample-gi'; donorStage = Donor-Stage 'sample-gi'
        remakeEvidence = @($materialGBuffer.id,'ff7-remake-dxbc-sample-gi-binding-v1:no-exact-current-region-match')
        classification = 'no-strict-sample-gi-match-in-current-regional-capture'
        implication = 'Rebirth uses this family for character dominant-direction ambient shaping. All 18 current-region Remake compute shaders were scanned; none has its four GBuffer/depth textures, paired float4 irradiance UAVs, 8x8 dispatch, and shading-model branch.'
        nextGate = 'Capture later regions, rescan automatically, and manually validate any exact structural match before a character-indirect test.'
    },
    [ordered]@{
        donorFamily = 'SSR'; donorId = 'ssr'; donorStage = Donor-Stage 'ssr'
        remakeEvidence = @('b2bc6059f9a39c7f-ps','e2aa1c8cb39e0a55-ps')
        classification = 'verified-producer-consumer-dataflow-preserve-currently'
        implication = 'The Remake SSR producer and downstream composite are identified; the current SSGI candidate deliberately preserves SSR radiance and confidence.'
        nextGate = 'Do not alter SSR while validating SSGI; revisit only as an independent feature.'
    },
    [ordered]@{
        donorFamily = 'PostProcessFinal'; donorId = 'post-process-final'; donorStage = Donor-Stage 'post-process-final'
        remakeEvidence = @('af6cd28a0108a18a-ps')
        classification = 'verified-ui-safe-scene-color-hook-not-an-indirect-light-producer'
        implication = 'This can control final presentation such as exposure but cannot repair missing local or indirect lighting.'
        nextGate = 'Keep separate from lighting-family work and preserve the native endpoint during SSGI tests.'
    },
    [ordered]@{
        donorFamily = 'PostProcessFog'; donorId = 'post-process-fog'; donorStage = Donor-Stage 'post-process-fog'
        remakeEvidence = @()
        classification = 'deferred-no-verified-remake-family-in-current-capture'
        implication = 'Fog is presentation/participating media, not evidence of missing direct or indirect surface-light coverage.'
        nextGate = 'Handle only after the Page Down native-path cleanup and a dedicated fog capture.'
    }
)

$excluded = @(
    [ordered]@{ donorId='ocean-a'; reason='Rebirth ocean-specific rendering is not a universal Remake lighting requirement.' },
    [ordered]@{ donorId='water-a'; reason='Rebirth water material/rendering is game-specific and outside the current surface-lighting goal.' },
    [ordered]@{ donorId='water-b'; reason='Rebirth water material/rendering is game-specific and outside the current surface-lighting goal.' }
)

$report = [ordered]@{
    schemaVersion = 1
    scope = 'Offline, evidence-backed comparison of pinned Rebirth donor families against the verified shader families captured in one FF7 Remake Intergrade region. No live game file is read or modified.'
    inputs = @(
        Get-RelativeEvidence $RebirthCatalogPath 'Pinned Rebirth family catalog'
        Get-RelativeEvidence $RemakeCatalogPath 'Verified Remake family catalog'
        Get-RelativeEvidence $RegionalAuditPath '184-shader regional lighting audit'
        Get-RelativeEvidence $SampleGIScanPath 'Strict SampleGI binding/dataflow scan'
        Get-RelativeEvidence $DirectLightTopologyPath 'Shared direct-light topology analysis'
        Get-RelativeEvidence $SSGIPackPath 'Material-aware F2 SSGI candidate'
        Get-RelativeEvidence $SSGIReloadStatusPath 'Current SSGI reload status'
    )
    inventory = [ordered]@{
        rebirthDonorFamilyCount = $rebirth.families.Count
        rebirthTargetCount = @($rebirth.families.implementations.variants.targets).Count
        remakeVerifiedFamilyCount = $remake.families.Count
        remakeVerifiedTargetCount = @($remake.families.implementations.variants.targets).Count
        regionalShaderCount = [int]$regional.scannedShaderCount
        regionalCompatibleLocalLightCount = [int]$regional.compatibleLocalLightCount
        regionalStructuralExceptionCount = [int]$regional.structuralExceptionCount
        sampleGIComputeShaderCount = [int]$sampleGiScan.capture.computeShaderCount
        sampleGIExactCompatibleCount = [int]$sampleGiScan.exactCompatibleCount
        sampleGINearMatchCount = [int]$sampleGiScan.nearMatchCount
        directLightSharedVariantCount = [int]$directLightTopology.remakeCapture.verifiedSharedTiledLightVariantCount
        directLightLocalAndInfiniteBranchCount = [int]$directLightTopology.remakeCapture.localAndInfiniteBranchVariantCount
        directLightReadModifyWriteVariantCount = [int]$directLightTopology.remakeCapture.readModifyWriteVariantCount
        directLightDirectWriteVariantCount = [int]$directLightTopology.remakeCapture.directWriteVariantCount
    }
    acceptedLiveCoverage = [ordered]@{
        contactAndFrustum = [ordered]@{
            status = 'accepted-protected-checkpoint'
            family = $tiledLight.id
            shaderHashes = $tiledHashes
            note = 'Accepted contact-shadow/frustum behavior is protected and is not changed by this audit.'
        }
        materialAwareSSGI = [ordered]@{
            packageClassification = [string]$ssgiPack.classification
            variant = [string]$ssgiPack.variant
            targetShader = [string]$ssgiPack.target.shader
            diagnosticStrength = [double]$ssgiPack.effect.diagnosticStrength
            reloadClassification = [string]$ssgiStatus.classification
            runtimeEligible = [bool]$ssgiStatus.runtimeEligible
            visualResult = [string]$ssgiStatus.visualResult
        }
    }
    coreLightingMatrix = $matrix
    excludedDonorFamilies = $excluded
    orderedNextGates = @(
        'Complete the material-aware e2aa SSGI reload and matched F2 visual/performance gate.',
        'Capture a later region and rerun the strict SampleGI scanner; the current 18-compute-shader set has no compatible family.',
        'Runtime-own directional and IES examples to identify their per-light branch/data contract inside or outside the shared tiled evaluator.',
        'Repeat the regional shader-capture audit in later areas; new hashes extend the family catalog and exceptions remain fail-closed.'
    )
    conclusions = @(
        'The current capture proves one five-variant shared tiled-light evaluator with both local radial and infinite/non-radial branches; it does not yet prove which branch owns directional lights or where IES profiles enter, and its 18 compute shaders contain no strict SampleGI match.',
        'Rebirth and Remake use different stages and scheduling for several logical effects, so donor family names are architectural guides rather than directly interchangeable shaders.',
        'The next live action remains the already-staged material-aware SSGI reload; the next offline discovery target is SampleGI/character-indirect lighting.',
        'Water and ocean families are intentionally excluded from the current universal surface-lighting scope.'
    )
}

[void](New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput -Parent))
[IO.File]::WriteAllText($resolvedOutput, (($report | ConvertTo-Json -Depth 14) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Host "PASS: wrote evidence-backed lighting coverage gap report to $resolvedOutput"
