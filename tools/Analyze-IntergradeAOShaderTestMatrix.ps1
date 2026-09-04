[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\agent2-ao-shader-test-matrix.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
function Project-Path([string]$Relative) { Join-Path $repoRoot ($Relative -replace '/', '\') }

$snapshotPath = Project-Path 'artifacts/analysis/intergrade-shader-cache-before-next-region-20260901.json'
$packManifestPath = Project-Path 'artifacts/ao-rebirth-fallback-consumer-f2-owner-integration-pack/manifest.json'
$runtimeIniPath = Project-Path 'runtime/Intergrade/Mods/RebirthEffectsDX11.ini'
$snapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
$identities = @($snapshot.shaders | ForEach-Object identity)

$groups = [ordered]@{
    changed = @(
        [ordered]@{ hash='e2aa1c8cb39e0a55'; stage='ps'; role='reflection/indirect ScreenAO consumer'; test='fixed-camera F2 off/on'; expected='only ambient/reflection AO shaping changes' }
    )
    nativeAOChainMustRemainUnchanged = @(
        [ordered]@{ hash='a77b589dce5822d6'; stage='ps'; role='temporal SSAO producer/history' },
        [ordered]@{ hash='40c795101bdaad50'; stage='ps'; role='depth-aware AO reduction/filter' },
        [ordered]@{ hash='c9dfe2b46edf3ece'; stage='ps'; role='3x3 AO filter' },
        [ordered]@{ hash='d41207d5d61df5b5'; stage='ps'; role='wide AO filter/variance' },
        [ordered]@{ hash='a8845c7ad73425a9'; stage='ps'; role='final ScreenAO compositor' }
    )
    directLightConsumersMustRemainUnchanged = @(
        [ordered]@{ hash='c30cdc8365df9840'; stage='cs'; role='tiled local-light ScreenAO consumer' },
        [ordered]@{ hash='62b33a2d1e505241'; stage='cs'; role='tiled local-light ScreenAO consumer' },
        [ordered]@{ hash='5a9fbefe0ab6f815'; stage='cs'; role='tiled local-light ScreenAO consumer' },
        [ordered]@{ hash='0e97888f9a8767da'; stage='cs'; role='tiled local-light ScreenAO consumer' },
        [ordered]@{ hash='08bb8764f1840179'; stage='cs'; role='tiled local-light ScreenAO consumer' }
    )
    reflectionAndOcclusionInvariants = @(
        [ordered]@{ hash='b2bc6059f9a39c7f'; stage='ps'; role='SSR trace/resolve producer'; expected='RGB radiance and hit/confidence alpha unchanged' },
        [ordered]@{ hash='b9e2305a994308f2'; stage='cs'; role='capsule-occlusion producer'; expected='capsule/contact topology unchanged' }
    )
    captureRequiredDoNotPatch = @(
        [ordered]@{ hash='c62607f2631cf47e'; stage='ps'; role='reflection/indirect composition variant'; expected='capture exact bindings and live coverage before replacement' }
    )
}

$all = @($groups.changed + $groups.nativeAOChainMustRemainUnchanged + $groups.directLightConsumersMustRemainUnchanged + $groups.reflectionAndOcclusionInvariants + $groups.captureRequiredDoNotPatch)
$missing = [Collections.Generic.List[string]]::new()
foreach ($shader in $all) {
    $identity = "$($shader.hash)-$($shader.stage)"
    if ($identities -notcontains $identity) { $missing.Add($identity) }
}
if ($missing.Count -ne 0) { throw "Test-matrix shaders missing from authoritative snapshot: $($missing -join ', ')" }

$pack = Get-Content -Raw -LiteralPath $packManifestPath | ConvertFrom-Json
$packIni = Get-Content -Raw -LiteralPath (Project-Path $pack.patchedIni)
$packHashes = @([regex]::Matches($packIni, '(?im)^\s*hash\s*=\s*(?<hash>[0-9a-f]{16})\s*$') | ForEach-Object { $_.Groups['hash'].Value.ToLowerInvariant() })
if ($packHashes.Count -ne 1 -or $packHashes[0] -ne 'e2aa1c8cb39e0a55') { throw 'F2 integration pack does not target exactly and only e2aa.' }
foreach ($invariant in @($all | Where-Object hash -ne 'e2aa1c8cb39e0a55')) {
    if ($packIni -match "(?im)^\s*hash\s*=\s*$($invariant.hash)\s*$") { throw "Invariant shader leaked into F2 pack: $($invariant.hash)" }
}
$runtimeIni = Get-Content -Raw -LiteralPath $runtimeIniPath
$runtimeF2 = [regex]::Matches($runtimeIni, '(?im)^(?!\s*;)\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F2(?![A-Z0-9_]).*$').Count
if ($runtimeF2 -ne 0) { throw 'Current runtime unexpectedly claims F2 before staging.' }

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    scope = 'FF7 Remake current 184-shader regional capture; exact-hash F2 test'
    currentLiveState = 'native Remake temporal SSAO; Agent 2 AO candidate not installed'
    candidate = [ordered]@{
        architecture = 'Rebirth Performance native-ScreenAO fallback shaping'
        algorithm = 'consumer-local AO power and character shaping; not new AO rays'
        notImplemented = @('Rebirth Maximum Quality GTVB visibility','SSGI bounce light','checkerboard reconstruction','new AO producer')
    }
    testGroups = $groups
    requiredShaderCount = $all.Count
    snapshotShaderCount = $snapshot.shaderCount
    allRequiredShadersPresent = $true
    packOverrideHashes = $packHashes
    packChangesOnlyE2aa = $true
    currentRuntimeF2ClaimCount = $runtimeF2
    visualCoverage = @('wall/floor corners','Cloud and another character: hair, skin, eyes','cloth and foliage','thin rails/geometry','wet and metallic reflections','indoor and outdoor lighting','motion and camera cuts')
    rejectionCriteria = @('crushed indirect detail','eye/socket or hair-card over-darkening','halos or outlines','flicker or temporal pumping','SSR radiance/hit change','direct-light AO change','capsule/contact-shadow change','unmatched later-region permutation')
}
$outputFull = [IO.Path]::GetFullPath($OutputPath)
if (-not $outputFull.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Output must remain inside the workspace: $outputFull" }
New-Item -ItemType Directory -Path (Split-Path -Parent $outputFull) -Force | Out-Null
[IO.File]::WriteAllText($outputFull, (($report | ConvertTo-Json -Depth 14) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Output "Intergrade Agent 2 AO shader test-matrix audit passed: $outputFull"
