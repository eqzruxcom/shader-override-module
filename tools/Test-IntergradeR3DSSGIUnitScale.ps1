[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\agent2-r3d-ssgi-unit-scale.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$tracePath = Join-Path $root 'src\Adapters\FF7RemakeIntergrade\R3DSSGITraceE2AA_ps.hlsl'
$denoisePath = Join-Path $root 'src\Effects\Lighting\R3DSSGIDenoise_SM5.hlsl'
$trace = Get-Content -Raw -LiteralPath $tracePath
$denoise = Get-Content -Raw -LiteralPath $denoisePath

foreach ($assertion in @(
    [pscustomobject]@{ Text = $trace; Pattern = 'AGENT2_UNREAL_UNITS_TO_METERS = 0\.01'; Label = 'trace centimeter-to-meter constant' },
    [pscustomobject]@{ Text = $trace; Pattern = 'float3 deltaMeters = delta \* AGENT2_UNREAL_UNITS_TO_METERS'; Label = 'trace converts reconstructed delta' },
    [pscustomobject]@{ Text = $trace; Pattern = 'abs\(dot\(deltaMeters, centerNormal\)\) < 0\.03'; Label = 'coplanar threshold remains 3 cm' },
    [pscustomobject]@{ Text = $trace; Pattern = 'dot\(deltaMeters, deltaMeters\)'; Label = 'distance falloff operates in meters squared' },
    [pscustomobject]@{ Text = $denoise; Pattern = 'AGENT2_UNREAL_UNITS_TO_METERS = 0\.01'; Label = 'denoiser centimeter-to-meter constant' },
    [pscustomobject]@{ Text = $denoise; Pattern = 'planeDistance = dot\(samplePosition - centerPosition, centerNormal\) \* AGENT2_UNREAL_UNITS_TO_METERS'; Label = 'A-trous plane distance operates in meters' }
)) {
    if ($assertion.Text -notmatch $assertion.Pattern) { throw "Unit-scale source assertion failed: $($assertion.Label)" }
}

$scale = 0.01
function Distance-Fade([double]$centimeters) {
    $meters = $centimeters * $scale
    return 1.0 / (1.0 + $meters * $meters)
}
function Plane-Weight([double]$centimeters) {
    $meters = $centimeters * $scale
    return [Math]::Exp(-$meters * $meters * 100.0)
}

$fade100 = Distance-Fade 100.0
$fade200 = Distance-Fade 200.0
$plane3 = Plane-Weight 3.0
$legacyFade100 = 1.0 / (1.0 + 100.0 * 100.0)
$legacyPlane3 = [Math]::Exp(-3.0 * 3.0 * 100.0)

if ([Math]::Abs($fade100 - 0.5) -gt 1e-12) { throw 'One-meter distance falloff is not 0.5.' }
if ([Math]::Abs($fade200 - 0.2) -gt 1e-12) { throw 'Two-meter distance falloff is not 0.2.' }
if ($plane3 -lt 0.91 -or $plane3 -gt 0.92) { throw 'Three-centimeter A-trous plane weight left the expected donor range.' }
if ($legacyFade100 -ge 0.001 -or $legacyPlane3 -ge 1e-100) { throw 'Legacy unscaled controls no longer demonstrate the centimeter failure.' }

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    classification = 'unreal-centimeter-to-r3d-meter-domain-verified'
    unrealContract = [ordered]@{ unrealUnitsToMeters = $scale; source = 'https://dev.epicgames.com/documentation/unreal-engine/world-settings?application_version=4.27' }
    analyticCases = @(
        [ordered]@{ distanceCm = 100.0; distanceM = 1.0; distanceFade = $fade100 },
        [ordered]@{ distanceCm = 200.0; distanceM = 2.0; distanceFade = $fade200 },
        [ordered]@{ planeDistanceCm = 3.0; planeDistanceM = 0.03; denoisePlaneWeight = $plane3 }
    )
    preventedFailure = [ordered]@{ unscaledOneMeterFade = $legacyFade100; unscaledThreeCentimeterPlaneWeight = $legacyPlane3 }
    sourceSha256 = [ordered]@{ trace = (Get-FileHash -Algorithm SHA256 -LiteralPath $tracePath).Hash; denoise = (Get-FileHash -Algorithm SHA256 -LiteralPath $denoisePath).Hash }
    runtimeEligible = $false
    installed = $false
}

$outputFull = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull)) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($outputFull, ($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine, $utf8)

[pscustomobject]@{
    result = 'pass'
    oneMeterFade = $fade100
    twoMeterFade = $fade200
    threeCentimeterPlaneWeight = $plane3
    output = $outputFull
    runtimeEligible = $false
}
