[CmdletBinding()]
param(
    [string]$LegacyTopologyReport = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-live-direct-light-topology-20260903-v3.json'),
    [string]$ProfileBranchReport = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-tiled-light-profile-branch-20260904.json'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-direct-light-topology-resolved-20260904.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "OutputPath must remain under artifacts: $output" }
foreach ($path in @($LegacyTopologyReport,$ProfileBranchReport)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required input is missing: $path" }
}

$legacy = Get-Content -Raw -LiteralPath $LegacyTopologyReport | ConvertFrom-Json
$profile = Get-Content -Raw -LiteralPath $ProfileBranchReport | ConvertFrom-Json
if ($legacy.detector -ne 'ff7-remake-dxbc-direct-light-topology-v1') { throw 'Unexpected legacy topology detector' }
if ($profile.detector -ne 'ff7-remake-tiled-light-angular-profile-branch-v1') { throw 'Unexpected profile-branch detector' }
if ($legacy.remakeCapture.verifiedSharedTiledLightVariantCount -ne 5 -or $profile.variantCount -ne 5) { throw 'Five-variant family invariant changed' }

$legacyHashes = @($legacy.remakeCapture.variants.hash | Sort-Object)
$profileHashes = @($profile.variants.hash | Sort-Object)
if (($legacyHashes -join ',') -ne ($profileHashes -join ',')) { throw 'Legacy and corrected reports describe different shader families' }
if ($legacy.remakeCapture.readModifyWriteVariantCount -ne 3 -or $legacy.remakeCapture.directWriteVariantCount -ne 2) {
    throw 'The pinned legacy report no longer exposes the known hard-coded-register classification error'
}
if (@($profile.variants | Where-Object outputComposition -ne 'read-modify-write-existing-lighting').Count -ne 0) {
    throw 'Corrected profile report does not prove all-five read/modify/write composition'
}

$variants = foreach ($entry in $profile.variants) {
    $legacyVariant = @($legacy.remakeCapture.variants | Where-Object hash -eq $entry.hash)
    if ($legacyVariant.Count -ne 1) { throw "Missing legacy variant: $($entry.hash)" }
    [ordered]@{
        hash = $entry.hash
        materialBucket = @($profileHashes).IndexOf($entry.hash)
        localInverseRadiusPath = [bool]$legacyVariant[0].localInverseRadiusPath
        infiniteOrNonRadialAttenuationBypass = [bool]$legacyVariant[0].infiniteOrNonRadialAttenuationBypass
        angularProfileAtlas = [ordered]@{
            textureSlot = [int]$entry.profileTextureSlot
            samplerSlot = [int]$entry.profileSamplerSlot
            priorLightingTextureSlot = [int]$entry.priorLightingTextureSlot
            conditionalPerLight = $true
        }
        outputComposition = $entry.outputComposition
        assemblyPath = $entry.assemblyPath
        assemblySha256 = $entry.assemblySha256
    }
}

$report = [ordered]@{
    schemaVersion = 2
    detector = 'ff7-remake-dxbc-direct-light-topology-v2-resolved'
    scope = 'Corrected correlation of the five shared tiled surface-light variants, their local/non-radial branches, angular profile atlas, and prior-lighting composition.'
    sourceReports = [ordered]@{
        legacyTopology = [IO.Path]::GetRelativePath($root,[IO.Path]::GetFullPath($LegacyTopologyReport)).Replace('\','/')
        angularProfile = [IO.Path]::GetRelativePath($root,[IO.Path]::GetFullPath($ProfileBranchReport)).Replace('\','/')
    }
    correction = [ordered]@{
        legacyFinding = 'three read/modify/write plus two direct-write variants; no dedicated IES profile texture proven'
        rootCause = 'legacy detector hard-coded the prior-lighting read to t9 and did not follow register-shifted equivalents'
        correctedFinding = 'all five variants read/modify/write prior lighting; all five contain the same conditional angular profile-atlas branch'
        registerPairs = @('profile t7 + prior lighting t8 in two variants','profile t8 + prior lighting t9 in three variants')
    }
    sharedTiledSurfaceLightFamily = [ordered]@{
        variantCount = $variants.Count
        variants = @($variants)
        localLight = 'structurally proven by position reconstruction, inverse-radius-squared attenuation, cutoff polynomial, and spot-cone path'
        profiledLocalLight = 'structurally proven as a data-driven conditional angular profile-atlas branch integrated into every variant'
        profiledLocalLightRuntimeActivation = 'not proven for the current red beacon; per-light profile flags and index values were not captured'
        directionalLight = 'not separately proven; every variant retains an infinite/non-radial attenuation bypass, but runtime light-type ownership is still required'
        outputComposition = 'read-modify-write-existing-lighting in all five variants'
    }
    implementationConsequences = @(
        'There is no separate IES shader family to port for this Remake path; preserve and, if needed, instrument the integrated per-light profile branch.',
        'A family transform must locate profile and prior-lighting bindings semantically because their absolute slots shift together.',
        'The contact-shadow insertion remains per-light and must multiply only the current light contribution before it is combined with prior lighting.',
        'Do not infer directional ownership from the non-radial bypass without a directional-light runtime capture.'
    )
    nextEvidenceGates = @(
        'Capture a visibly patterned IES/profile light and record cb3[index+768].x/.z or the sampled profile atlas contribution.',
        'Capture an outdoor dominant directional light and prove which per-light discriminator enters the infinite/non-radial branch.',
        'Preserve both register layouts and all five material/tile specializations in automatic family matching.'
    )
}

[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,(($report | ConvertTo-Json -Depth 14)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Variants=$variants.Count; ReadModifyWrite=$variants.Count; Profiled=$variants.Count; DirectionalOwned=$false; Output=$output }

