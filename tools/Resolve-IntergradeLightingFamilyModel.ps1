[CmdletBinding()]
param(
    [string]$DispatchReportPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-tiled-light-dispatch-sequence-20260904.json'),
    [string]$ProfileReportPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-tiled-light-profile-branch-20260904.json'),
    [string]$LocalLightReportPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-tiled-local-light-dataflow-20260904.json'),
    [string]$CoverageReportPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-lighting-coverage-resolution-20260904.json'),
    [string]$VelocityReportPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-native-velocity-sequence-20260904.json'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-lighting-family-model-20260904.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "OutputPath must remain under artifacts: $output" }

$inputs = [ordered]@{
    dispatch = [IO.Path]::GetFullPath($DispatchReportPath)
    profile = [IO.Path]::GetFullPath($ProfileReportPath)
    localLight = [IO.Path]::GetFullPath($LocalLightReportPath)
    coverage = [IO.Path]::GetFullPath($CoverageReportPath)
    velocity = [IO.Path]::GetFullPath($VelocityReportPath)
}
foreach ($path in $inputs.Values) {
    if (-not $path.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "Input must remain under artifacts: $path" }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required report is missing: $path" }
}

$dispatch = Get-Content -Raw -LiteralPath $inputs.dispatch | ConvertFrom-Json
$profile = Get-Content -Raw -LiteralPath $inputs.profile | ConvertFrom-Json
$local = Get-Content -Raw -LiteralPath $inputs.localLight | ConvertFrom-Json
$coverage = Get-Content -Raw -LiteralPath $inputs.coverage | ConvertFrom-Json
$velocity = Get-Content -Raw -LiteralPath $inputs.velocity | ConvertFrom-Json
if ($dispatch.detector -ne 'ff7-remake-tiled-light-dispatch-sequence-v1') { throw 'Unexpected dispatch report' }
if ($profile.detector -ne 'ff7-remake-tiled-light-angular-profile-branch-v1') { throw 'Unexpected profile report' }
if ($local.detector -ne 'ff7-remake-tiled-local-light-dataflow-v1') { throw 'Unexpected local-light report' }
if ($coverage.detector -ne 'ff7-remake-lighting-coverage-resolution-v1') { throw 'Unexpected coverage report' }
if ($velocity.detector -ne 'ff7-remake-native-velocity-sequence-v1') { throw 'Unexpected velocity report' }

$canonicalHashes = @($dispatch.canonicalSequence.hash)
$canonicalKey = (($canonicalHashes | Sort-Object) -join ',')
foreach ($set in @(@($profile.variants.hash),@($local.variants.hash),@($coverage.acceptedTiledSurfaceLightFamily.hashes))) {
    $candidateKey = (($set | Sort-Object) -join ',')
    if ($canonicalKey -ne $candidateKey) { throw 'The five-hash family differs between source reports' }
}

$variants = foreach ($entry in $dispatch.canonicalSequence) {
    $p = @($profile.variants | Where-Object hash -eq $entry.hash)
    $l = @($local.variants | Where-Object hash -eq $entry.hash)
    if ($p.Count -ne 1 -or $l.Count -ne 1) { throw "Expected one profile and local-light record for $($entry.hash)" }
    [ordered]@{
        hash = $entry.hash
        indirectArgumentOffset = $entry.offset
        materialBucket = $entry.materialBucket
        role = 'tiled-local-light-surface-evaluator'
        localPointOrSpotDataflow = $true
        angularProfileBranch = $true
        profileTextureSlot = $p[0].profileTextureSlot
        priorLightingTextureSlot = $p[0].priorLightingTextureSlot
        outputComposition = $p[0].outputComposition
        attenuationModeField = $l[0].attenuationModeField
        attenuationModeIsDirectionalClassifier = $false
        assemblyPath = $l[0].assemblyPath
        assemblySha256 = $l[0].assemblySha256
    }
}

$report = [ordered]@{
    schemaVersion = 3
    detector = 'ff7-remake-lighting-family-model-v3'
    scope = 'Resolved offline model of the currently proven FF7 Remake DX11 direct-light, indirect-light boundary, and native velocity families.'
    sourceReports = [ordered]@{}
    provenLocalLightFamily = [ordered]@{
        classifier = 'f97a821dddaa328a'
        captureCount = $dispatch.captureCount
        variantCount = $variants.Count
        dispatchContract = 'one classifier followed by five DispatchIndirect calls sharing one argument buffer at byte offsets 0/12/24/36/48'
        specialization = 'material/tile buckets; not object-exclusive face, skin, clothing, or individual-light shaders'
        variants = @($variants)
        supportedNativeBranches = @('point/local position and radius','optional spot cone','optional angular/IES-style profile atlas','prior-lighting read/modify/write')
        contactShadowInsertionRule = 'multiply only the current local-light contribution after its native attenuation/profile terms and before it is combined with prior lighting'
    }
    correctedFindings = @(
        'All five variants read/modify/write prior lighting; the old three-plus-two split came from a hard-coded t9 detector.',
        'All five variants contain the same integrated conditional angular profile-atlas branch; there is no evidence for a separate IES shader hash in this path.',
        'The cb4[index+512].w bypass is a local-light distance-attenuation-mode flag, not a directional-light classifier.',
        'All three SampleGI near matches are disqualified; a26b3473289dba2d and 58101bdcc044cd88 are native velocity reduction/dilation.'
    )
    unresolvedCoverage = [ordered]@{
        directionalLightOwner = 'not captured or structurally owned'
        profileRuntimeActivation = 'native branch proven; live activation on a representative patterned light not yet captured'
        unshadowedDirectDiffuseCandidate = 'adb544f9a11d6c7e remains runtime-unowned'
        exactSampleGIShader = 'absent from current census'
    }
    indirectLighting = [ordered]@{
        currentStableBoundary = 'late-scene composite already visually confirmed without feedback'
        preparedNextBoundary = $coverage.indirectLightingBoundary.shader
        placement = $coverage.indirectLightingBoundary.placement
        nativeVelocityReduction = $velocity.velocityTileReduction.hash
        nativeVelocityDilation = $velocity.velocityTileDilation.hash
        liveGate = 'when user is present: F2=0 native parity, then F2=1 camera rotation around a local light and receiving wall'
    }
    safeNextOrder = @(
        'Live-test the already compiled c473 pre-temporal indirect-light pack with F2 only.',
        'Capture the outdoor directional-light owner before attempting sun/directional modification.',
        'Instrument native profile flag/index data on a visibly patterned local light.',
        'Runtime-own adb544f9a11d6c7e before deciding whether its unshadowed direct diffuse needs modification.',
        'Only after those gates, generalize the contact/falloff transform template across the full five-bucket family.'
    )
    immutableKeyContract = [ordered]@{
        F10 = '3Dmigoto shader reload only'
        F2 = 'indirect-light experiment toggle only'
        PageUp = 'current foreground shader-test cycle when explicitly configured'
        PageDown = 'graduated master effect toggle when explicitly configured'
    }
    sleepPolicy = 'offline analysis/build/test only; no live game-directory installation while the user is asleep'
}
foreach ($name in $inputs.Keys) {
    $report.sourceReports[$name] = [ordered]@{
        path = [IO.Path]::GetRelativePath($root,$inputs[$name]).Replace('\','/')
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $inputs[$name]).Hash
    }
}

[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,(($report | ConvertTo-Json -Depth 14)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Version=$report.schemaVersion; Variants=$variants.Count; DirectionalOwned=$false; SampleGIExact=0; Output=$output }

