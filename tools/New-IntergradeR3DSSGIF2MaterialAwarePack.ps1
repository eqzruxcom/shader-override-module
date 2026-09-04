[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-material-aware-pack')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if (-not $output.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "Output escaped project: $output" }

$baseRoot = Join-Path $root 'artifacts\agent2-r3d-ssgi-f2-standalone-pack'
$baseManifestPath = Join-Path $baseRoot 'manifest.json'
$reviewRoot = Join-Path $root 'artifacts\agent2-r3d-ssgi-material-response-review'
$reviewManifestPath = Join-Path $reviewRoot 'manifest.json'
$reviewHlslPath = Join-Path $reviewRoot 'Agent2R3DSSGICompositeMaterialAware_ps.hlsl'
foreach ($path in @($baseManifestPath,$reviewManifestPath,$reviewHlslPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required input is missing: $path" }
}

$base = Get-Content -Raw -LiteralPath $baseManifestPath | ConvertFrom-Json
$review = Get-Content -Raw -LiteralPath $reviewManifestPath | ConvertFrom-Json
if ($base.classification -ne 'offline-f2-standalone-live-topology-candidate' -or
    $base.target.shader -ne 'e2aa1c8cb39e0a55' -or @($base.files).Count -ne 7 -or
    $base.policy.runtimeEligible -or $base.policy.installed -or $base.policy.gameFilesTouched) {
    throw 'Base standalone package contract changed.'
}
if ($review.classification -ne 'offline-material-aware-ssgi-response-review-not-installed' -or
    $review.shaderHash -ne 'e2aa1c8cb39e0a55' -or
    $review.compile.hlslSha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $reviewHlslPath).Hash -or
    $review.policy.liveFilesTouched -or $review.policy.runtimeEligible -or $review.policy.installed) {
    throw 'Material-response review contract changed.'
}

$modsOut = Join-Path $output 'Mods'
[IO.Directory]::CreateDirectory($modsOut) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$compositeName = 'Agent2R3DSSGICompositeE2AA_ps.hlsl'
foreach ($entry in @($base.files)) {
    $name = [IO.Path]::GetFileName(([string]$entry.path).Replace('/','\'))
    $destination = Join-Path $modsOut $name
    if ($name -eq $compositeName) {
        [IO.File]::Copy($reviewHlslPath,$destination,$true)
    } else {
        $source = Join-Path $baseRoot ([string]$entry.path)
        if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash -ne [string]$entry.sha256) {
            throw "Base payload drifted: $source"
        }
        [IO.File]::Copy($source,$destination,$true)
    }
}

$manifest = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    classification = 'offline-f2-standalone-live-topology-candidate'
    variant = 'material-aware-unlit-mask-and-rebirth-character-response'
    target = $base.target
    source = [ordered]@{
        baseStandaloneManifest = 'artifacts\agent2-r3d-ssgi-f2-standalone-pack\manifest.json'
        baseStandaloneManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $baseManifestPath).Hash
        materialResponseManifest = 'artifacts\agent2-r3d-ssgi-material-response-review\manifest.json'
        materialResponseManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $reviewManifestPath).Hash
    }
    baseline = $base.baseline
    effect = [ordered]@{
        algorithm = [string]$base.effect.algorithm
        resolution = [string]$base.effect.resolution
        unrealUnitsToMeters = [double]$base.effect.unrealUnitsToMeters
        depthClear = [double]$base.effect.depthClear
        depthConvention = [string]$base.effect.depthConvention
        sampling = [string]$base.effect.sampling
        denoiseSteps = @($base.effect.denoiseSteps)
        upsample = [string]$base.effect.upsample
        receiverDiffuse = 'unlit 0 excluded; skin 3, hair 7, eye 9 use quarter-scale response after 1/pi; other lit uses Rebirth pi boost'
        composite = [string]$base.effect.composite
        diagnosticStrength = [double]$base.effect.diagnosticStrength
        highSrvSlotsRestored = @($base.effect.highSrvSlotsRestored)
    }
    controls = $base.controls
    compile = @($base.compile | ForEach-Object {
        if ($_.name -eq 'Agent2R3DSSGICompositeE2AA_ps') {
            [ordered]@{
                name = 'Agent2R3DSSGICompositeE2AA_ps'
                profile = 'ps_5_0'
                objectSha256 = [string]$review.compile.objectSha256
                assemblySha256 = [string]$review.compile.assemblySha256
            }
        } else {
            [ordered]@{name=[string]$_.name;profile=[string]$_.profile;objectSha256=[string]$_.objectSha256;assemblySha256=[string]$_.assemblySha256}
        }
    })
    files = @(Get-ChildItem -LiteralPath $modsOut -File | Sort-Object Name | ForEach-Object {
        [ordered]@{path=('Mods\' + $_.Name);sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash}
    })
    policy = [ordered]@{
        exactLiveBaselineRequired = $true
        activatesDisabledOwner = $false
        runtimeEligible = $false
        installed = $false
        gameFilesTouched = $false
        liveCaptureRequired = $true
    }
}
$manifestPath = Join-Path $output 'manifest.json'
[IO.File]::WriteAllText($manifestPath,(($manifest | ConvertTo-Json -Depth 16)+[Environment]::NewLine),$utf8)

[pscustomobject]@{
    Result = 'pass'
    Variant = $manifest.variant
    PayloadFiles = $manifest.files.Count
    F2Bound = $true
    LiveFilesTouched = $false
    RuntimeEligible = $false
    Output = $manifestPath
}
