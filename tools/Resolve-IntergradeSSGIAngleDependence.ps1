[CmdletBinding()]
param(
    [string]$PackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-pre-temporal-pack'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-ssgi-angle-dependence-20260904.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$pack = [IO.Path]::GetFullPath($PackRoot).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $pack.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'PackRoot must remain under artifacts' }
if (-not $output.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'OutputPath must remain under artifacts' }

$tracePath = Join-Path $pack 'Mods\Agent2R3DSSGITraceE2AA_ps.hlsl'
$iniPath = Join-Path $pack 'Mods\Agent2R3DSSGITest.ini'
$manifestPath = Join-Path $pack 'manifest.json'
foreach ($path in @($tracePath,$iniPath,$manifestPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required pack file missing: $path" }
}
$trace = Get-Content -Raw -LiteralPath $tracePath
$ini = Get-Content -Raw -LiteralPath $iniPath
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json

$checks = [ordered]@{
    fourSliceTrace = $trace -match 'static const uint AGENT2_SLICE_COUNT\s*=\s*4\s*;'
    sixteenMaxSteps = $trace -match 'static const uint AGENT2_MAX_STEPS\s*=\s*16\s*;'
    screenPixelHashJitter = $trace -match 'Agent2HashIGN\(input\.position\.xy\)'
    jitterRotatesSlices = $trace -match 'angleOffset\s*=\s*AGENT2_TAU\s*\*\s*jitter'
    sourceIsCurrentScene = $trace -match 'Agent2SceneRadiance\.SampleLevel'
    traceStopsAtScreenEdge = $trace -match 'any\(sampleUV\s*<=\s*0\.0\)\s*\|\|\s*any\(sampleUV\s*>=\s*1\.0\)'
    noPreviousSceneOutputInput = $ini -notmatch '(?im)ResourceAgent2SSGIScene\s*=\s*(?:copy|reference)\s+o0'
    currentSceneIsC473T2 = $ini -match '(?im)ResourceAgent2SSGIScene\s*=\s*reference\s+ps-t2'
    nativeTemporalBoundary = $ini -match '(?im)^hash\s*=\s*c473ab75b7519f7e\s*$'
    nativeHistoryUntouched = $manifest.hooks.history -eq 'native c473 ps-t3, untouched'
    nativeMotionUntouched = $manifest.hooks.motion -eq 'native c473 ps-t4, untouched'
}
$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count -ne 0) { throw "SSGI angle-dependence contract failed: $($failed -join ', ')" }

$report = [ordered]@{
    schemaVersion = 1
    detector = 'ff7-remake-ssgi-angle-dependence-v1'
    scope = 'Static proof of the two distinct causes of camera-angle-dependent indirect light in the prepared pre-temporal SSGI candidate.'
    source = [ordered]@{
        pack = [IO.Path]::GetRelativePath($root,$pack).Replace('\','/')
        trace = [IO.Path]::GetRelativePath($root,$tracePath).Replace('\','/')
        ini = [IO.Path]::GetRelativePath($root,$iniPath).Replace('\','/')
        manifest = [IO.Path]::GetRelativePath($root,$manifestPath).Replace('\','/')
    }
    verifiedContract = $checks
    failureModes = @(
        [ordered]@{
            id = 'visible-small-source-sampling-phase'
            mechanism = 'The receiver traces four pixel-hash-rotated screen-space slices. Camera motion changes receiver pixel coordinates and therefore ray rotation; a small emissive source can remain on screen but fall between sampled rays.'
            symptom = 'bounce toggles at particular camera angles while the source is still visible'
            preTemporalExpectedEffect = 'reduce one-frame noise and abruptness through native c473 history'
            preTemporalLimitation = 'cannot guarantee a hit when the current four-slice trace repeatedly misses the source'
        },
        [ordered]@{
            id = 'offscreen-or-occluded-source-loss'
            mechanism = 'The trace samples only current c473 scene color inside 0..1 UV and stops at the screen boundary.'
            symptom = 'bounce disappears when the emitting surface leaves the screen or is hidden, even if its game light still exists'
            preTemporalExpectedEffect = 'briefly retain valid prior indirect light if native motion/disocclusion acceptance permits'
            preTemporalLimitation = 'cannot reconstruct durable radiance from a source absent from all current screen-space inputs'
        }
    )
    ruledOut = @(
        'previous-frame scene-color self-feedback; the prepared pack never reads o0 as source radiance',
        'a stronger composite multiplier as a stability solution; it amplifies hits and misses equally',
        'bloom injection; the trace consumes HDR scene radiance and adds diffuse indirect RGB before native temporal resolution'
    )
    decisionTree = @(
        'First live-test the existing c473 pre-temporal pack with fixed-camera F2=0 native parity, then slow rotation with F2=1.',
        'If a visible beacon still toggles, prepare a controlled source-footprint candidate (depth-aware radiance dilation or increased stratified slice coverage) rather than raising strength.',
        'If only off-screen sources fail, evaluate a separate GI-only reprojection cache or native light-list/probe source. Never feed composed scene+GI back as the next source.',
        'Promote nothing until character materials, camera cuts, disocclusion, FOV/resolution, UI, and GPU timing pass.'
    )
    safetyPolicy = [ordered]@{
        installed = $false
        liveFilesModified = $false
        keys = 'F10 reload only; F2 indirect-light test only; Page Up/Page Down unchanged'
        userState = 'offline analysis only while the user sleeps'
    }
}

[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,(($report | ConvertTo-Json -Depth 12)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Result='pass'; FailureModes=$report.failureModes.Count; Output=$output; LiveFilesModified=$false }
