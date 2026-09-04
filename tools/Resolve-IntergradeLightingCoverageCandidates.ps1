[CmdletBinding()]
param(
    [string]$CoverageReport = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-live-lighting-coverage-audit-20260903-v3.json'),
    [string]$VelocityReport = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-native-velocity-sequence-20260904.json'),
    [string]$TiledLightReport = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-tiled-light-dispatch-sequence-20260904.json'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-lighting-coverage-resolution-20260904.json')
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

$coverage = Read-Json $CoverageReport 'Coverage report'
$velocity = Read-Json $VelocityReport 'Velocity report'
$tiled = Read-Json $TiledLightReport 'Tiled-light report'
if ($coverage.detector -ne 'ff7-remake-live-lighting-coverage-correlation-v1') { throw 'Unexpected coverage detector' }
if ($velocity.detector -ne 'ff7-remake-native-velocity-sequence-v1') { throw 'Unexpected velocity detector' }
if ($tiled.detector -ne 'ff7-remake-tiled-light-dispatch-sequence-v1') { throw 'Unexpected tiled-light detector' }

$nearHashes = @($coverage.sampleGI.nearMatchHashes | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique)
$expectedNearHashes = @('a26b3473289dba2d','adb544f9a11d6c7e','b9e2305a994308f2')
if (($nearHashes -join ',') -ne (($expectedNearHashes | Sort-Object) -join ',')) {
    throw "SampleGI near-match set changed: $($nearHashes -join ',')"
}
if ($velocity.sampleGIExclusion.excludedHash -ne 'a26b3473289dba2d' -or $velocity.sampleGIExclusion.verdict -notmatch '^proven') {
    throw 'Velocity report does not prove the a26b SampleGI exclusion'
}
if ($coverage.newlyLoadedComputeShader.hash -ne 'adb544f9a11d6c7e' -or $coverage.newlyLoadedComputeShader.classification -notmatch '^unshadowed-tiled-direct-diffuse-light') {
    throw 'Coverage report does not structurally classify adb5 as direct diffuse lighting'
}
if ($coverage.universalRegexCorrelation.verifiedSemanticFalsePositive.hash -ne 'b9e2305a994308f2' -or $coverage.universalRegexCorrelation.verifiedSemanticFalsePositive.actualFamily -ne 'tiled-capsule-occlusion-producer') {
    throw 'Coverage report does not retain the verified b9e2 capsule-occlusion classification'
}
if ([int]$tiled.captureCount -lt 1 -or @($tiled.canonicalSequence).Count -ne 5) {
    throw 'Tiled-light report has no retained capture proof'
}

$resolutions = @(
    [ordered]@{
        hash = 'a26b3473289dba2d'
        status = 'disqualified-from-sample-gi'
        provenRole = 'full-resolution motion/depth evaluation and 16x16 tile reduction'
        evidence = @(
            'exact 2560x1440 coverage from 160x90 groups of 16x16',
            'vector-like XY plus depth inputs',
            'full-resolution and per-tile outputs',
            'immediately followed by 58101bdcc044cd88 neighborhood vector dilation'
        )
        automaticAction = 'negative-control-only'
    },
    [ordered]@{
        hash = 'adb544f9a11d6c7e'
        status = 'disqualified-from-sample-gi'
        provenRole = 'structural unshadowed tiled direct-diffuse lighting candidate; runtime light ownership pending'
        evidence = @(
            'one lighting UAV rather than paired irradiance UAVs',
            'normal and shading-model decode',
            'scene-depth reconstruction and tiled light list',
            'inverse-radius-squared and Lambert diffuse math',
            'reads prior lighting and writes the lighting UAV without shadow-array sampling'
        )
        automaticAction = 'do-not-transform-until-runtime-owned'
    },
    [ordered]@{
        hash = 'b9e2305a994308f2'
        status = 'disqualified-from-sample-gi'
        provenRole = 'tiled capsule-occlusion producer'
        evidence = @(
            'verified semantic classification retained in the project catalog',
            'only one float4 output rather than paired irradiance outputs',
            'universal stereo regex matches are candidate hits, not role proof'
        )
        automaticAction = 'negative-control-only'
    }
)

$acceptedHashes = @($coverage.acceptedSharedTiledLightFamily.hashes | Sort-Object)
$tiledHashes = @($tiled.canonicalSequence.hash | Sort-Object)
if (($acceptedHashes -join ',') -ne ($tiledHashes -join ',')) { throw 'Accepted tiled-light family and runtime dispatch family disagree' }

$report = [ordered]@{
    schemaVersion = 1
    detector = 'ff7-remake-lighting-coverage-resolution-v1'
    scope = 'Fail-closed resolution of every current SampleGI near match using independent structural, semantic, and runtime-order evidence.'
    sourceReports = [ordered]@{
        coverage = [IO.Path]::GetRelativePath($root,[IO.Path]::GetFullPath($CoverageReport)).Replace('\','/')
        velocity = [IO.Path]::GetRelativePath($root,[IO.Path]::GetFullPath($VelocityReport)).Replace('\','/')
        tiledLight = [IO.Path]::GetRelativePath($root,[IO.Path]::GetFullPath($TiledLightReport)).Replace('\','/')
    }
    sampleGI = [ordered]@{
        exactCompatibleCount = [int]$coverage.sampleGI.exactCompatibleCount
        nearMatchCount = $nearHashes.Count
        resolvedFalsePositiveCount = $resolutions.Count
        unresolvedNearMatchCount = $nearHashes.Count - $resolutions.Count
        resolutions = $resolutions
        conclusion = 'The current live census contains no strict SampleGI shader, and all three structural near matches are independently disqualified. Do not patch any of them as SampleGI.'
    }
    acceptedTiledSurfaceLightFamily = [ordered]@{
        hashes = @($tiled.canonicalSequence.hash)
        independentCaptureCount = [int]$tiled.captureCount
        specialization = 'stable classifier-driven material/tile buckets, not object-exclusive shaders'
        currentCoverage = 'local/radial branch structurally proven; non-radial branch present but directional ownership and IES behavior remain runtime-unproven'
    }
    indirectLightingBoundary = [ordered]@{
        shader = 'c473ab75b7519f7e-ps'
        placement = 'immediately before native velocity reduction/dilation and its following fullscreen pass'
        consequence = 'The prepared c473 pre-temporal candidate is the correct next stabilization experiment; the a26b/5810 compute pair must remain native.'
    }
    nextEvidenceGates = @(
        'When the user is present, install and test the already compiled c473 pre-temporal indirect-light candidate under the dedicated F2 toggle.',
        'Confirm F2=0 native parity first, then compare F2=1 while rotating the camera around the red beacon and nearby wall.',
        'Runtime-own adb544f9a11d6c7e in a scene where it executes before deciding whether unshadowed direct diffuse needs modification.',
        'Capture representative directional and IES lights before adding type-specific transformations.',
        'Keep all five accepted tiled-light buckets together unless a material-mask subset is formally proven.'
    )
    safetyPolicy = [ordered]@{
        liveInstall = 'deferred while the user sleeps'
        sampleGI = 'resource-count similarity is insufficient; all current near matches are negative controls'
        nativeVelocity = 'never replace a26b3473289dba2d or 58101bdcc044cd88 as indirect-light passes'
        keys = 'F10 remains shader reload; F2 remains the indirect-light test toggle; do not repurpose either key'
    }
}

[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,(($report | ConvertTo-Json -Depth 14)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{ ExactSampleGI=$report.sampleGI.exactCompatibleCount; NearMatches=$report.sampleGI.nearMatchCount; ResolvedFalsePositives=$report.sampleGI.resolvedFalsePositiveCount; Output=$output }

