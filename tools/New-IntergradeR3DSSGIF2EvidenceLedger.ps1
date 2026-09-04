[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\agent2-r3d-ssgi-live-evidence-ledger.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$outputFull = [IO.Path]::GetFullPath($OutputPath)
$analysisRoot = [IO.Path]::GetFullPath((Join-Path $root 'artifacts\analysis')).TrimEnd('\')
if (-not ($outputFull.Equals((Join-Path $analysisRoot 'agent2-r3d-ssgi-live-evidence-ledger.json'),[StringComparison]::OrdinalIgnoreCase) -or
    $outputFull.StartsWith($analysisRoot + '\',[StringComparison]::OrdinalIgnoreCase))) {
    throw "Evidence ledger output must remain under $analysisRoot"
}
$packManifest = Join-Path $root 'artifacts\agent2-r3d-ssgi-f2-standalone-pack\manifest.json'
$topologyReport = Join-Path $root 'artifacts\analysis\agent2-r3d-ssgi-live-topology.json'
$reloadCheckerTest = Join-Path $root 'artifacts\analysis\agent2-r3d-ssgi-live-reload-checker-test.json'
foreach ($required in @($packManifest,$topologyReport,$reloadCheckerTest)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required ledger source is missing: $required" }
}

function Get-Hash([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

$pack = Get-Content -Raw -LiteralPath $packManifest | ConvertFrom-Json
$topology = Get-Content -Raw -LiteralPath $topologyReport | ConvertFrom-Json
$reload = Get-Content -Raw -LiteralPath $reloadCheckerTest | ConvertFrom-Json
if ($pack.classification -ne 'offline-f2-standalone-live-topology-candidate' -or
    $topology.classification -ne 'live-topology-requires-standalone-f2-hook' -or
    $reload.result -ne 'pass' -or $pack.policy.runtimeEligible -ne $false -or
    $topology.gameFilesTouched -ne $false -or $reload.liveGameDirectoryTouched -ne $false) {
    throw 'Ledger sources are not the verified fail-closed standalone chain.'
}

function New-PendingGate([string]$Id,[string]$Label,[string[]]$RequiredEvidence,[string]$Acceptance) {
    [ordered]@{
        id = $Id
        label = $Label
        status = 'pending'
        requiredEvidence = $RequiredEvidence
        acceptance = $Acceptance
        evidence = $null
        evidenceSha256 = $null
        reviewedAtUtc = $null
        notes = $null
    }
}

$gates = @(
    New-PendingGate 'live-parser-custom-hlsl' 'Live parser and six custom HLSL passes' @(
        'post-F10 reload status JSON',
        'exact installed and protected hashes',
        'F2 key, e2aa override, six CustomShader sections, six ps= entries',
        'zero parser/compiler error lines'
    ) 'Status classification equals passed-parser-and-six-custom-HLSL-compile-clean.'
    New-PendingGate 'f2-off-neutral' 'F2 OFF native-path parity' @(
        'matched native-resolution F2 OFF screenshot',
        'same-scene pre-install or restored-baseline screenshot',
        'camera/exposure lock notes'
    ) 'F2 OFF shows no added indirect radiance and does not alter native AO, direct lights, reflections, UI, or exposure.'
    New-PendingGate 'strong-warm-bounce-still' 'Strong warm RGB bounce still' @(
        'matched native-resolution F2 OFF screenshot',
        'matched native-resolution F2 ON screenshot',
        'difference image or crop around warm fixture, wall, clothing, and face'
    ) 'F2 ON visibly adds warm indirect diffuse response resembling the bottom reference without merely darkening AO.'
    New-PendingGate 'motion-disocclusion' 'Motion and disocclusion stability' @(
        'F2 OFF motion clip',
        'F2 ON motion clip',
        'camera pan across characters, geometry edges, and newly revealed surfaces'
    ) 'No objectionable shimmer, trails, stale light, popping, or screen-space leakage relative to the diagnostic purpose.'
    New-PendingGate 'screen-edge-subviewport' 'Screen edges and viewport reconstruction' @(
        'native-resolution edge crops',
        'non-default resolution or viewport capture',
        'F2 OFF/ON comparison'
    ) 'No edge bands, half-resolution seams, inverted rays, or subviewport displacement.'
    New-PendingGate 'ao-ssr-invariants' 'Native AO and reflection invariants' @(
        'contact/crease AO closeups OFF/ON',
        'reflective material closeups OFF/ON',
        'notes confirming AO remains visibility and SSGI remains RGB radiance'
    ) 'F2 changes indirect diffuse radiance only; native temporal AO, SSR, material occlusion, and contact shadows remain behaviorally separate.'
    New-PendingGate 'camera-cuts' 'Camera-cut stability' @(
        'cutscene or rapid camera-cut capture with F2 ON',
        'first frames after each cut'
    ) 'No persistent previous-view contribution, invalid full-screen flash, or delayed recovery after cuts.'
    New-PendingGate 'gpu-timing' 'GPU timing' @(
        'same-scene F2 OFF frame-time samples',
        'same-scene F2 ON frame-time samples',
        'resolution, GPU, sample count, median and percentile data'
    ) 'Trace, four denoise passes, and composite have measured cost; no performance claim is inferred from offline compilation.'
    New-PendingGate 'balanced-strength-promotion' 'Balanced-strength selection' @(
        'accepted strong diagnostic evidence',
        'at least one lower-strength candidate capture',
        'recorded chosen strength and rationale'
    ) 'The current 1.25 strong value is not promoted as balanced; a lower production value is selected only from matched live evidence.'
)

$ledger = [ordered]@{
    schemaVersion = 1
    result = 'pending-live-evidence'
    packageId = 'agent2-r3d-ssgi-f2-standalone'
    visualTarget = 'bottom reference image: stronger warm RGB indirect diffuse bounce on fixtures, walls, clothing, and face; not darker AO'
    controls = [ordered]@{
        F1 = 'reserved and unbound'
        F2 = 'standalone strong diagnostic off/on'
        F3 = 'current live unbound state preserved'
    }
    diagnostic = [ordered]@{
        algorithm = 'altered R3D horizon SSGI'
        strength = 1.25
        classification = 'strong diagnostic, not balanced default'
        nativeTemporalAO = 'unchanged and separate'
    }
    sources = @(
        [ordered]@{path=[IO.Path]::GetRelativePath($root,$packManifest); sha256=Get-Hash $packManifest},
        [ordered]@{path=[IO.Path]::GetRelativePath($root,$topologyReport); sha256=Get-Hash $topologyReport},
        [ordered]@{path=[IO.Path]::GetRelativePath($root,$reloadCheckerTest); sha256=Get-Hash $reloadCheckerTest}
    )
    captureRules = @(
        'Use the same save, camera, exposure, resolution, and frame composition for F2 OFF and ON.',
        'Capture F2 OFF first, press F2 once, then capture ON without changing unrelated controls.',
        'Do not use F1 or F3; neither is bound by this standalone package.',
        'Record still and motion evidence separately; a still cannot satisfy motion, camera-cut, or GPU gates.',
        'Parser success cannot satisfy visual or performance gates.'
    )
    gates = $gates
    completedGates = 0
    requiredGates = $gates.Count
    installed = $false
    runtimeEligible = $false
}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull)) | Out-Null
[IO.File]::WriteAllText($outputFull,(($ledger|ConvertTo-Json -Depth 14)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Result = $ledger.result
    RequiredGates = $ledger.requiredGates
    CompletedGates = $ledger.completedGates
    Strength = $ledger.diagnostic.strength
    Installed = $false
    RuntimeEligible = $false
    Output = $outputFull
}
