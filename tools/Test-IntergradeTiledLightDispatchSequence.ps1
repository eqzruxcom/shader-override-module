[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$analyzer = Join-Path $PSScriptRoot 'Analyze-IntergradeTiledLightDispatchSequence.ps1'
$a = Join-Path $root 'artifacts\analysis\intergrade-tiled-light-dispatch-sequence.test-a.json'
$b = Join-Path $root 'artifacts\analysis\intergrade-tiled-light-dispatch-sequence.test-b.json'
$expectedHashes = @('c30cdc8365df9840','62b33a2d1e505241','5a9fbefe0ab6f815','0e97888f9a8767da','08bb8764f1840179')
$expectedOffsets = @(0,12,24,36,48)

try {
    & $analyzer -OutputPath $a | Out-Host
    & $analyzer -OutputPath $b | Out-Host
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $a).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $b).Hash) {
        throw 'Dispatch-sequence report is not deterministic'
    }
    $report = Get-Content -Raw -LiteralPath $a | ConvertFrom-Json
    if ($report.detector -ne 'ff7-remake-tiled-light-dispatch-sequence-v1') { throw 'Unexpected detector ID' }
    if ($report.captureCount -ne 5) { throw "Expected five independent captures; found $($report.captureCount)" }
    if ((@($report.canonicalSequence.hash) -join ',') -ne ($expectedHashes -join ',')) { throw 'Canonical hash order changed' }
    if ((@($report.canonicalSequence.offset) -join ',') -ne ($expectedOffsets -join ',')) { throw 'Canonical indirect offsets changed' }
    foreach ($capture in $report.captures) {
        if ($capture.classifier.hash -ne 'f97a821dddaa328a') { throw 'Classifier identity changed' }
        if ($capture.argumentResourceHash -ne '6380a698') { throw 'Indirect argument resource identity changed' }
        if (@($capture.sequence).Count -ne 5) { throw 'A capture no longer contains the full five-dispatch sequence' }
        if ((@($capture.sequence.hash) -join ',') -ne ($expectedHashes -join ',')) { throw 'Per-capture hash order changed' }
        if ((@($capture.sequence.offset) -join ',') -ne ($expectedOffsets -join ',')) { throw 'Per-capture offsets changed' }
    }
    if ($report.safetyPolicy.objectLabels -notmatch '^Never') { throw 'Object-label fail-closed policy regressed' }
    if ($report.safetyPolicy.directionalAndIes -notmatch '^Require') { throw 'Directional/IES evidence gate regressed' }
} finally {
    foreach ($path in @($a,$b)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
}

Write-Host 'PASS: five independent captures retain one classifier, one indirect argument buffer, and the exact five-bucket 0/12/24/36/48 tiled-light sequence.'
