[CmdletBinding()]
param(
    [string]$VerifiedCatalog = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\ff7-remake-intergrade-verified-family-catalog.json'),
    [string]$SemanticMatches = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-live-281-semantic-family-matches-20260903-v3.json'),
    [string]$LightingModel = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-lighting-family-model-20260904.json'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-directional-light-coverage-20260904.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must remain under artifacts: $output"
}

function Read-Json([string]$Path,[string]$Label) {
    $resolved = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "$Label missing: $resolved" }
    try { return Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json }
    catch { throw "$Label is invalid JSON: $resolved`n$($_.Exception.Message)" }
}

$catalog = Read-Json $VerifiedCatalog 'Verified family catalog'
$semantic = Read-Json $SemanticMatches 'Semantic match report'
$lighting = Read-Json $LightingModel 'Lighting family model'

$descriptor = 'ue4-directional-cascade-shadow-projection-filter-ps-sm5'
$verifiedMatches = @($semantic.matches | Where-Object { $_.descriptor -eq $descriptor })
if ($verifiedMatches.Count -ne 1) { throw "Expected exactly one verified cascade projection/filter match, found $($verifiedMatches.Count)" }
$verified = $verifiedMatches[0]
if ($verified.hash -ne 'aadc1c2374853914' -or [int]$verified.semanticChecksPassed -ne 10) {
    throw 'Verified cascade projection/filter identity or evidence count changed'
}

$family = @($catalog.families | Where-Object { $_.id -eq 'directional-cascade-shadow-projection-filter' })
if ($family.Count -ne 1) { throw 'Verified catalog must contain exactly one directional cascade projection/filter family' }
$implementation = @($family[0].implementations | Where-Object { $_.adapter -eq 'FF7RemakeIntergrade' -and $_.api -eq 'D3D11' })
if ($implementation.Count -ne 1) { throw 'Verified catalog must contain exactly one FF7 Remake D3D11 cascade implementation' }
if ($implementation[0].insertionEligibility -ne 'excluded-not-directional-light-evaluator') {
    throw 'Cascade projection/filter is no longer explicitly excluded as the directional evaluator'
}

$nearMatches = @($semantic.nearMatches | Where-Object { $_.descriptor -eq $descriptor } | Sort-Object hash)
$expectedNear = @('07a10abbef52a0f2','18305e60b4378edb','1d94a570a9cc970e','5202602be9051c62','7faf10d13b4e23ec')
if ((@($nearMatches.hash) -join ',') -ne ($expectedNear -join ',')) {
    throw "Directional cascade near-match set changed: $(@($nearMatches.hash) -join ',')"
}

$acceptedLocal = @($lighting.provenLocalLightFamily.variants)
if ($acceptedLocal.Count -ne 5) { throw 'Expected five accepted tiled local-light variants' }
if (@($acceptedLocal | Where-Object { $_.attenuationModeIsDirectionalClassifier -ne $false }).Count -ne 0) {
    throw 'A local-light attenuation flag is incorrectly being treated as a directional classifier'
}
if ($lighting.unresolvedCoverage.directionalLightOwner -ne 'not captured or structurally owned') {
    throw 'Directional owner boundary changed in the resolved lighting model'
}

$failedNear = @($nearMatches | ForEach-Object {
    [ordered]@{
        hash = $_.hash
        failedChecks = @($_.evidence | Where-Object { -not $_.satisfied } | ForEach-Object { $_.id })
        status = 'rejected-near-match'
    }
})

$report = [ordered]@{
    schemaVersion = 1
    detector = 'ff7-remake-directional-light-coverage-boundary-v1'
    scope = 'Fail-closed separation of directional cascade shadow production from the still-unresolved directional surface-light evaluator.'
    sourceReports = [ordered]@{
        verifiedCatalog = [IO.Path]::GetRelativePath($root,[IO.Path]::GetFullPath($VerifiedCatalog)).Replace('\','/')
        semanticMatches = [IO.Path]::GetRelativePath($root,[IO.Path]::GetFullPath($SemanticMatches)).Replace('\','/')
        lightingModel = [IO.Path]::GetRelativePath($root,[IO.Path]::GetFullPath($LightingModel)).Replace('\','/')
    }
    verifiedCascadeShadowProjection = [ordered]@{
        hash = $verified.hash
        stage = $verified.stage
        shaderModel = $verified.shaderModel
        semanticChecksPassed = [int]$verified.semanticChecksPassed
        role = 'receiver reconstruction plus four offset gathers from a Texture2DArray cascade shadow map, producing packed shadow factors'
        classification = 'directional-shadow-mask-producer-filter'
        directionalLightEvaluator = $false
        insertionEligibility = $implementation[0].insertionEligibility
    }
    rejectedCascadeNearMatches = [ordered]@{
        count = $failedNear.Count
        records = $failedNear
        policy = 'Near matches remain rejected unless every semantic check passes; none may be promoted by filename or partial resource similarity.'
    }
    acceptedFiveShaderLightingFamily = [ordered]@{
        hashes = @($acceptedLocal.hash)
        provenRole = 'five stable tiled local-light/material specialization buckets with distance attenuation, spot-cone, profile-atlas, shadow/contact, and read-modify-write lighting paths'
        directionalOwnership = 'not proven'
        reason = 'cb4[index+512].w is a local-light distance-attenuation-mode flag, not a directional-light classifier'
    }
    coverageBoundary = [ordered]@{
        cascadeShadowProducer = 'verified'
        directionalSurfaceLightingEvaluator = 'unresolved'
        implication = 'A directional shadow mask can be produced in one pass and consumed later by a separate lighting evaluator; modifying the mask producer is not equivalent to modifying sunlight falloff or indirect lighting.'
        prohibitedInference = 'Do not identify the directional evaluator from cascade naming, a non-radial attenuation bypass, or partial semantic similarity.'
    }
    nextLiveEvidenceGate = [ordered]@{
        prerequisite = 'user awake and explicitly available for a live capture'
        scene = 'outdoor area with a dominant sun/directional light, visible cascade shadows, and a receiving wall or ground plane'
        capture = @(
            'Record the verified aadc1c2374853914 projection/filter execution and its packed shadow output.',
            'Trace the packed shadow resource forward to the later pass that combines it with normals, material data, directional color, and the scene-lighting target.',
            'Runtime-own that consumer before binding any transformation or test key.',
            'Verify native parity first, then isolate only the directional contribution under the agreed test key contract.'
        )
    }
    safetyPolicy = [ordered]@{
        liveInstall = 'deferred while the user sleeps'
        keys = 'F10 remains shader reload; F2 remains indirect-light test toggle; Page Up and Page Down remain reserved under the established contract'
        currentAction = 'documentation and offline validation only'
    }
}

[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,(($report | ConvertTo-Json -Depth 14)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{ VerifiedCascade=$report.verifiedCascadeShadowProjection.hash; RejectedNearMatches=$report.rejectedCascadeNearMatches.count; DirectionalEvaluator=$report.coverageBoundary.directionalSurfaceLightingEvaluator; Output=$output }
