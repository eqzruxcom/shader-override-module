[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$analyzer = Join-Path $PSScriptRoot 'Analyze-IntergradeNativeVelocitySequence.ps1'
$a = Join-Path $root 'artifacts\analysis\intergrade-native-velocity-sequence.test-a.json'
$b = Join-Path $root 'artifacts\analysis\intergrade-native-velocity-sequence.test-b.json'

try {
    & $analyzer -OutputPath $a | Out-Host
    & $analyzer -OutputPath $b | Out-Host
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $a).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $b).Hash) {
        throw 'Native velocity sequence report is not deterministic'
    }
    $report = Get-Content -Raw -LiteralPath $a | ConvertFrom-Json
    if ($report.detector -ne 'ff7-remake-native-velocity-sequence-v1') { throw 'Unexpected detector ID' }
    if ($report.capture.frame.width -ne 2560 -or $report.capture.frame.height -ne 1440) { throw 'Captured frame dimensions changed' }
    if ($report.runtimeSequence.sceneTemporalResolve.ps -ne 'c473ab75b7519f7e') { throw 'Temporal boundary hash changed' }
    if ($report.runtimeSequence.velocityTileReduction.cs -ne 'a26b3473289dba2d') { throw 'Reduction hash changed' }
    if ($report.runtimeSequence.velocityTileDilation.cs -ne '58101bdcc044cd88') { throw 'Dilation hash changed' }
    if ($report.runtimeSequence.followingFullscreenPass.ps -ne 'af6cd28a0108a18a') { throw 'Following fullscreen hash changed' }
    if ($report.runtimeSequence.velocityTileReduction.event -ne ($report.runtimeSequence.sceneTemporalResolve.event + 1)) { throw 'Reduction is no longer immediately after temporal boundary' }
    if ($report.runtimeSequence.velocityTileDilation.event -ne ($report.runtimeSequence.velocityTileReduction.event + 1)) { throw 'Dilation is no longer immediately after reduction' }
    if ($report.runtimeSequence.followingFullscreenPass.event -ne ($report.runtimeSequence.velocityTileDilation.event + 1)) { throw 'Following fullscreen pass is no longer adjacent' }
    if ($report.velocityTileReduction.outputGrid.width -ne 160 -or $report.velocityTileReduction.outputGrid.height -ne 90) { throw 'Reduction grid changed' }
    if ($report.velocityTileDilation.dispatchCoverage.width -ne 160 -or $report.velocityTileDilation.dispatchCoverage.height -ne 96) { throw 'Dilation coverage changed' }
    if (@($report.velocityTileReduction.checks.psobject.Properties.Value) -contains $false) { throw 'A reduction proof check failed' }
    if (@($report.velocityTileDilation.checks.psobject.Properties.Value) -contains $false) { throw 'A dilation proof check failed' }
    if ($report.sampleGIExclusion.verdict -ne 'proven structural and runtime false positive') { throw 'SampleGI exclusion regressed' }
    if ($report.sampleGIExclusion.policy -notmatch '^Do not classify') { throw 'Fail-closed policy regressed' }
} finally {
    foreach ($path in @($a,$b)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
}

Write-Host 'PASS: native c473 -> a26b -> 5810 -> af6c order and the full-frame velocity reduction/dilation dataflow are pinned.'
