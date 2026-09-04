[CmdletBinding()]
param(
    [string]$ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Adapters\FF7RemakeIntergrade\verified-shader-classifications.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Classification manifest does not exist: $ManifestPath"
}
$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) { throw 'Unsupported classification schema.' }
if ($manifest.adapterId -ne 'FF7RemakeIntergrade') { throw 'Unexpected adapter id.' }

$inventoryPath = Join-Path $projectRoot ([string]$manifest.inventory)
if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
    throw "Inventory does not exist: $inventoryPath"
}
$inventory = Get-Content -Raw -LiteralPath $inventoryPath | ConvertFrom-Json
if ($inventory.capture.captureId -ne $manifest.captureId) {
    throw 'Classification capture id does not match the inventory.'
}
$captureManifestPath = [string]$inventory.capture.manifest
if (-not [IO.Path]::IsPathRooted($captureManifestPath)) {
    $captureManifestPath = Join-Path $projectRoot $captureManifestPath
}
if (-not (Test-Path -LiteralPath $captureManifestPath -PathType Leaf)) {
    throw "Retained capture manifest does not exist: $captureManifestPath"
}
$captureManifest = Get-Content -Raw -LiteralPath $captureManifestPath | ConvertFrom-Json
$captureManifestRoot = Split-Path -Parent $captureManifestPath
$captureManifestByKey = @{}
foreach ($shader in @($captureManifest.shaders)) {
    $captureManifestByKey[[string]$shader.shader] = $shader
}
$inventoryByKey = @{}
foreach ($shader in @($inventory.capture.shaders)) {
    $inventoryByKey[[string]$shader.shader] = $shader
}

$familyIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$classifiedKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($family in @($manifest.families)) {
    if (-not $familyIds.Add([string]$family.familyId)) {
        throw "Duplicate family id: $($family.familyId)"
    }
    if ([string]$family.stage -notin @('vs','ps','cs','gs','hs','ds')) {
        throw "Invalid stage for family $($family.familyId)."
    }
    if (-not @($family.hashes).Count) { throw "Family $($family.familyId) has no hashes." }
    foreach ($entry in @($family.hashes)) {
        $hash = ([string]$entry.hash).ToLowerInvariant()
        if ($hash -notmatch '^[0-9a-f]{16}$') { throw "Invalid hash '$hash'." }
        $key = "$hash-$($family.stage)"
        if (-not $classifiedKeys.Add($key)) { throw "Shader $key is classified more than once." }
        if (-not $inventoryByKey.ContainsKey($key)) { throw "Classified shader $key is absent from the capture." }
        if (-not [bool]$inventoryByKey[$key].originalDisassemblerHeaderRetained) {
            throw "Classified shader $key lacks its original header."
        }
    }
    foreach ($evidence in @($family.evidence)) {
        $evidencePath = Join-Path $projectRoot ([string]$evidence)
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            throw "Evidence for $($family.familyId) is missing: $evidence"
        }
    }
}

$contact = @($manifest.families | Where-Object familyId -eq 'tiled-surface-light-evaluation')
if ($contact.Count -ne 1) { throw 'Expected one tiled surface-light family.' }
$expectedContact = @(
    '08bb8764f1840179','0e97888f9a8767da','5a9fbefe0ab6f815',
    '62b33a2d1e505241','c30cdc8365df9840'
) | Sort-Object
$actualContact = @($contact[0].hashes.hash | Sort-Object)
if (Compare-Object $expectedContact $actualContact) {
    throw 'The verified five-variant contact family changed unexpectedly.'
}
if ($contact[0].insertionEligibility -ne 'eligible-only-as-complete-five-variant-remake-adapter') {
    throw 'Contact family lost its complete-five-variant safety gate.'
}

$softwarePath = Join-Path $projectRoot 'artifacts\contact-candidate-validation-20260831-v5\manifest.json'
$software = Get-Content -Raw -LiteralPath $softwarePath | ConvertFrom-Json
if ($software.result -ne 'passed') { throw 'Contact software-validation manifest is not passing.' }
$softwareHashes = @($software.variants.shaderHash | Sort-Object)
if (Compare-Object $expectedContact $softwareHashes) {
    throw 'Contact software-validation variants do not match the classification.'
}

$livePath = Join-Path $projectRoot 'artifacts\checkpoints\rebirth-contact-first-working-20260831-v1\receipts\contact-live-status.json'
$live = Get-Content -Raw -LiteralPath $livePath | ConvertFrom-Json
$liveHashes = @($live.shaders.hash | Sort-Object)
if (Compare-Object $expectedContact $liveHashes) {
    throw 'Contact live-checkpoint variants do not match the classification.'
}
foreach ($shader in @($live.shaders)) {
    if (-not $shader.assemblyLoadSeen -or -not $shader.creationSeen -or -not $shader.overrideParsed) {
        throw "Contact live checkpoint is incomplete for $($shader.hash)."
    }
}

$b9e = @($manifest.families | Where-Object familyId -eq 'tiled-capsule-occlusion-producer')
if ($b9e.Count -ne 1 -or $b9e[0].insertionEligibility -ne 'excluded-upstream-producer') {
    throw 'b9e upstream capsule-occlusion exclusion is missing.'
}
$capsuleDiagnosticPath = Join-Path $projectRoot 'artifacts\capsule-occlusion-ownership-diagnostic-20260831-v1\diagnostic-manifest.json'
$capsuleDiagnostic = Get-Content -Raw -LiteralPath $capsuleDiagnosticPath | ConvertFrom-Json
if ([string]$capsuleDiagnostic.diagnosticId -ne 'ff7r-capsule-occlusion-ownership-v1' -or
    [string]$capsuleDiagnostic.shader -ne 'b9e2305a994308f2-cs' -or
    [string]$capsuleDiagnostic.family -ne 'tiled-capsule-occlusion-producer') {
    throw 'Capsule ownership diagnostic identity disagrees with the classification.'
}
if ([bool]$capsuleDiagnostic.runtimeEligible -or [bool]$capsuleDiagnostic.installed -or
    -not [bool]$capsuleDiagnostic.neutralRoundTripIdentical) {
    throw 'Capsule ownership diagnostic lost its offline-only safety state.'
}
$capsuleKey = 'b9e2305a994308f2-cs'
if (-not $captureManifestByKey.ContainsKey($capsuleKey)) {
    throw 'Capsule ownership shader is absent from the retained capture manifest.'
}
$capsuleCapture = $captureManifestByKey[$capsuleKey]
$capsuleOriginalPath = Join-Path $captureManifestRoot ([string]$capsuleCapture.binary)
if (-not (Test-Path -LiteralPath $capsuleOriginalPath -PathType Leaf)) {
    throw "Captured capsule shader binary does not exist: $capsuleOriginalPath"
}
$capsuleActualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $capsuleOriginalPath).Hash
if ($capsuleActualSha256 -ne [string]$capsuleCapture.sourceSha256) {
    throw 'Captured capsule shader bytes disagree with the retained capture manifest.'
}
if ([string]$capsuleDiagnostic.originalSha256 -ne [string]$capsuleCapture.sourceSha256) {
    throw 'Capsule ownership diagnostic was not built from the classified original shader.'
}
if ([string]$capsuleDiagnostic.change.modifiedOutput -ne 'u0.xy capsule visibility forced to neutral 1.0' -or
    [string]$capsuleDiagnostic.control.experimentDefault -ne 'off') {
    throw 'Capsule ownership diagnostic no longer has the approved narrow output contract.'
}
$materials = @($manifest.families | Where-Object familyId -eq 'material-gbuffer-producers')
if ($materials.Count -ne 1 -or $materials[0].insertionEligibility -ne 'excluded-not-light-evaluation') {
    throw 'Material/GBuffer exclusion is missing.'
}
$clothingVertex = @($manifest.families | Where-Object familyId -eq 'skinned-material-gbuffer-vertex-producer')
if ($clothingVertex.Count -ne 1 -or
    [string]$clothingVertex[0].stage -ne 'vs' -or
    [string]$clothingVertex[0].insertionEligibility -ne 'excluded-not-light-or-shadow-depth-evaluation' -or
    @($clothingVertex[0].hashes).Count -ne 1 -or
    [string]$clothingVertex[0].hashes[0].hash -ne '0fcd2a51d59b6599') {
    throw 'Confirmed Cloud clothing skinned-material vertex family is missing or broadened.'
}
$clothingVertexAssemblyPath = Join-Path $captureManifestRoot 'assembly\0fcd2a51d59b6599-vs.asm'
$clothingVertexAssembly = Get-Content -Raw -LiteralPath $clothingVertexAssemblyPath
foreach ($motif in @(
    'dcl_resource_buffer (float,float,float,float) t0',
    'dcl_input v3.xyzw',
    'dcl_input v4.xyzw',
    'dcl_input v5.xyzw',
    'dcl_input v6.xyzw',
    'ld_indexable(buffer)(float,float,float,float)',
    'mad r0.xyzw, v6.wwww',
    'dcl_output_siv o6.xyzw, position'
)) {
    if (-not $clothingVertexAssembly.Contains($motif)) {
        throw "Confirmed clothing vertex shader lost structural motif: $motif"
    }
}
$peerEvidencePath = Join-Path $projectRoot 'artifacts\clothing-shader-ownership-diagnostic-20260831-v1\evidence\0fcd2a51d59b6599-peer-pairing-log.txt'
$peerEvidence = Get-Content -Raw -LiteralPath $peerEvidencePath
if (-not $peerEvidence.Contains('vertex shader hash = 0fcd2a51d59b6599') -or
    -not $peerEvidence.Contains('visited peer shader hash = 8b1f6ebe443b5615')) {
    throw 'Clothing VS/PS live peer-pairing evidence is incomplete.'
}

$shadowDepthSpecs = @(
    [pscustomobject]@{
        Family = 'shadow-depth-caster-skinned-vertex'
        Stage = 'vs'
        Hashes = @('40b611d369bc7b68','40e368977f88f118','54bb7b01b6bd5196','741aee753c201ee6','7d8b4ec350c811b6','804f4caa626c8a94','8942481559f2a938','8c6447577e2664d5','fe4c1e062a2a682f')
        Kind = 'skinned-vs'
    },
    [pscustomobject]@{
        Family = 'shadow-depth-caster-static-vertex'
        Stage = 'vs'
        Hashes = @('49b1908cb47c0d29','73012b97e989a07e')
        Kind = 'static-vs'
    },
    [pscustomobject]@{
        Family = 'shadow-depth-writer-sampled-material-pixel'
        Stage = 'ps'
        Hashes = @('07a10abbef52a0f2','7faf10d13b4e23ec','d20b75105323b71d')
        Kind = 'sampled-ps'
    },
    [pscustomobject]@{
        Family = 'shadow-depth-writer-direct-pixel'
        Stage = 'ps'
        Hashes = @('50218fe92282b9b2','859e9302e9dc9520','ac87aba3f1feac47','bae7ee67de90d1d4')
        Kind = 'direct-ps'
    }
)
$expectedShadowDepthKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($spec in $shadowDepthSpecs) {
    $family = @($manifest.families | Where-Object familyId -eq $spec.Family)
    if ($family.Count -ne 1) { throw "Expected one $($spec.Family) family." }
    if ([string]$family[0].stage -ne $spec.Stage -or
        [string]$family[0].insertionEligibility -ne 'excluded-shadow-map-caster-not-light-evaluation') {
        throw "Shadow-depth family $($spec.Family) lost its stage or caster-only exclusion."
    }
    $actualHashes = @($family[0].hashes.hash | Sort-Object)
    if (Compare-Object @($spec.Hashes | Sort-Object) $actualHashes) {
        throw "Shadow-depth family $($spec.Family) changed unexpectedly."
    }
    foreach ($hash in $spec.Hashes) {
        $key = "$hash-$($spec.Stage)"
        [void]$expectedShadowDepthKeys.Add($key)
        $assemblyPath = Join-Path $captureManifestRoot "assembly\$key.asm"
        if (-not (Test-Path -LiteralPath $assemblyPath -PathType Leaf)) {
            throw "Retained assembly for shadow-depth shader is missing: $key"
        }
        $assembly = Get-Content -Raw -LiteralPath $assemblyPath
        if ($assembly -notmatch 'ShadowDepth') { throw "$key lost its ShadowDepth semantic." }
        switch ($spec.Kind) {
            'skinned-vs' {
                if ($assembly -notmatch 'dcl_resource_buffer .* t0' -or
                    $assembly -notmatch 'dcl_input v4\.xyzw' -or
                    $assembly -notmatch 'ld_indexable\(buffer\)' -or
                    $assembly -notmatch '(mul|mad) .*v4\.[xyzw]') {
                    throw "$key no longer matches the buffered four-weight skinned-caster descriptor."
                }
            }
            'static-vs' {
                if ($assembly -match 'dcl_resource_buffer' -or $assembly -match 'dcl_input v4\.xyzw') {
                    throw "$key no longer matches the non-skinned static-caster descriptor."
                }
            }
            'sampled-ps' {
                if ($assembly -notmatch 'dcl_resource_texture2d' -or
                    $assembly -notmatch 'sample.*\(texture2d\)' -or
                    $assembly -notmatch 'dcl_output oDepth') {
                    throw "$key no longer matches the sampled material-coverage depth-writer descriptor."
                }
            }
            'direct-ps' {
                if ($assembly -match 'dcl_resource_texture2d' -or
                    $assembly -match 'sample.*\(texture2d\)' -or
                    $assembly -notmatch 'dcl_output oDepth') {
                    throw "$key no longer matches the direct depth-writer descriptor."
                }
            }
        }
    }
}
$capturedShadowDepthKeys = @(
    Get-ChildItem -LiteralPath (Join-Path $captureManifestRoot 'assembly') -File -Filter '*.asm' |
        Where-Object { (Get-Content -Raw -LiteralPath $_.FullName) -match 'ShadowDepth' } |
        ForEach-Object { $_.BaseName } |
        Sort-Object
)
if (Compare-Object @($expectedShadowDepthKeys | Sort-Object) $capturedShadowDepthKeys) {
    throw 'The classified shadow-depth families no longer cover every ShadowDepth shader in the retained regional capture.'
}

$ambientSpecs = @(
    [pscustomobject]@{ Family='temporal-screen-space-ambient-occlusion'; Stage='ps'; Hashes=@('a77b589dce5822d6'); Eligibility='eligible-for-native-ao-adapter-not-contact-shadow-or-ssgi' },
    [pscustomobject]@{ Family='screen-space-reflection-trace-resolve'; Stage='ps'; Hashes=@('8c9e92a0895efcdc','b2bc6059f9a39c7f'); Eligibility='eligible-only-as-complete-ssr-family-after-live-visual-gate' },
    [pscustomobject]@{ Family='reflection-indirect-composite'; Stage='ps'; Hashes=@('c62607f2631cf47e','e2aa1c8cb39e0a55'); Eligibility='eligible-consumer-boundary-after-material-ui-and-live-visual-gates' }
)
foreach ($spec in $ambientSpecs) {
    $family = @($manifest.families | Where-Object familyId -eq $spec.Family)
    if ($family.Count -ne 1 -or [string]$family[0].stage -ne $spec.Stage -or [string]$family[0].insertionEligibility -ne $spec.Eligibility) {
        throw "Ambient/reflection family contract changed: $($spec.Family)"
    }
    if (Compare-Object @($spec.Hashes | Sort-Object) @($family[0].hashes.hash | Sort-Object)) {
        throw "Ambient/reflection family identities changed: $($spec.Family)"
    }
}
$missingIds = @($manifest.missingFamilies.familyId)
foreach ($required in @('directional-light-evaluator','local-light-ies-evaluator','regional-tiled-surface-light-variants','capsule-occlusion-ownership','dynamic-shadow-receiver-lighting-permutations')) {
    if ($required -notin $missingIds) { throw "Missing target '$required' is not recorded." }
}

Write-Host "PASS: $($classifiedKeys.Count) shaders in $($familyIds.Count) verified families are captured, header-complete, evidence-backed, and safely classified."
