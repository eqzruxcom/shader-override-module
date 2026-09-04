[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$resolver = Join-Path $PSScriptRoot 'Resolve-IntergradeLightingCoverageCandidates.ps1'
$a = Join-Path $root 'artifacts\analysis\intergrade-lighting-coverage-resolution.test-a.json'
$b = Join-Path $root 'artifacts\analysis\intergrade-lighting-coverage-resolution.test-b.json'

try {
    & $resolver -OutputPath $a | Out-Host
    & $resolver -OutputPath $b | Out-Host
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $a).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $b).Hash) {
        throw 'Lighting coverage resolution is not deterministic'
    }
    $report = Get-Content -Raw -LiteralPath $a | ConvertFrom-Json
    if ($report.detector -ne 'ff7-remake-lighting-coverage-resolution-v1') { throw 'Unexpected detector ID' }
    if ($report.sampleGI.exactCompatibleCount -ne 0) { throw 'Unexpected strict SampleGI match' }
    if ($report.sampleGI.nearMatchCount -ne 3 -or $report.sampleGI.resolvedFalsePositiveCount -ne 3 -or $report.sampleGI.unresolvedNearMatchCount -ne 0) {
        throw 'Current SampleGI near matches are not completely resolved'
    }
    $expected = @('a26b3473289dba2d','adb544f9a11d6c7e','b9e2305a994308f2')
    if ((@($report.sampleGI.resolutions.hash | Sort-Object) -join ',') -ne (($expected | Sort-Object) -join ',')) { throw 'Resolved hash set changed' }
    if (@($report.sampleGI.resolutions | Where-Object status -ne 'disqualified-from-sample-gi').Count -ne 0) { throw 'A near match is not fail-closed' }
    if ($report.acceptedTiledSurfaceLightFamily.independentCaptureCount -ne 5) { throw 'Five-capture tiled-light proof regressed' }
    if ($report.indirectLightingBoundary.shader -ne 'c473ab75b7519f7e-ps') { throw 'Pre-temporal injection boundary changed' }
    if ($report.safetyPolicy.liveInstall -ne 'deferred while the user sleeps') { throw 'Overnight live-install gate regressed' }
    if ($report.safetyPolicy.keys -notmatch '^F10 remains shader reload') { throw 'Key contract regressed' }
} finally {
    foreach ($path in @($a,$b)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
}

Write-Host 'PASS: all three current SampleGI near matches are independently disqualified and the c473 pre-temporal boundary is retained.'
