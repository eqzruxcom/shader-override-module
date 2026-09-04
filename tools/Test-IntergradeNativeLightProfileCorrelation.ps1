[CmdletBinding()]
param(
    [string]$CaptureDirectory = 'F:\Shader3Dmigoto\snapshot-20260831-114015-080\game-shader-state\FrameAnalysis-2026-08-30-211238',
    [string]$BaseAnalysisPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-contact-capture-profile-membership-20260904\analysis.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$analyzer = Join-Path $PSScriptRoot 'analyze_intergrade_native_light_profiles.py'
$preservedAnalyzer = Join-Path $PSScriptRoot 'analyze_intergrade_contact_capture.py'
$expectedPreservedAnalyzerHash = '75790EA47FC8F2484A762EA1F47F48E1644EC601720E5C376E1E77101497822A'
$output = Join-Path $root ('artifacts\analysis\native-light-profile-correlation-test-' + [guid]::NewGuid().ToString('N'))

foreach ($path in @($CaptureDirectory, $BaseAnalysisPath, $analyzer, $preservedAnalyzer)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required input is missing: $path" }
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $preservedAnalyzer).Hash -ne $expectedPreservedAnalyzerHash) {
    throw 'The guarded contact-shadow analyzer changed; this correlator must remain separate.'
}

try {
    & python $analyzer $CaptureDirectory $BaseAnalysisPath $output | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Native-light correlator exited with code $LASTEXITCODE" }
    $report = Get-Content -Raw -LiteralPath (Join-Path $output 'analysis.json') | ConvertFrom-Json

    if ($report.schemaVersion -ne 2 -or $report.result -ne 'two-unprofiled-red-beacon-candidates-with-unsaturated-native-tile-lists') {
        throw 'Unexpected native-light correlation result.'
    }
    if ((@($report.redBeaconCandidates.index) -join ',') -ne '1,0') { throw 'Projected red-beacon pair changed.' }
    foreach ($candidate in @($report.redBeaconCandidates)) {
        if ($candidate.profileFlagged -or $candidate.flags -ne 0 -or -not $candidate.projectedLightCenterInsideViewport) {
            throw "Red-beacon candidate $($candidate.index) no longer proves the unprofiled in-view contract."
        }
        if ([Math]::Abs([double]$candidate.radius - 70.0) -gt 0.001 -or [double]$candidate.redDominance -lt 10.0) {
            throw "Red-beacon candidate $($candidate.index) no longer has the expected physical/color signature."
        }
    }
    if ($report.tileLightList.capacityPerTile -ne 64 -or $report.tileLightList.observedSampledCounts.max -ne 16 -or $report.tileLightList.sampledCapacityReached) {
        throw 'Captured native tile-list capacity evidence changed.'
    }
    if ($report.installed -or $report.runtimeEligible) { throw 'Read-only evidence became runtime eligible.' }
} finally {
    if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Recurse -Force }
}

Write-Host 'PASS: records 1/0 are the two in-view 70-unit red-beacon candidates, both unprofiled; sampled native tile lists peak at 16 of 64.'
