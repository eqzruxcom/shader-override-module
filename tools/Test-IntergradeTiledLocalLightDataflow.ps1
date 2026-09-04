[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$analyzer = Join-Path $PSScriptRoot 'Analyze-IntergradeTiledLocalLightDataflow.ps1'
$a = Join-Path $root 'artifacts\analysis\intergrade-tiled-local-light-dataflow.test-a.json'
$b = Join-Path $root 'artifacts\analysis\intergrade-tiled-local-light-dataflow.test-b.json'

try {
    & $analyzer -OutputPath $a | Out-Host
    & $analyzer -OutputPath $b | Out-Host
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $a).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $b).Hash) { throw 'Local-light dataflow report is not deterministic' }
    $report = Get-Content -Raw -LiteralPath $a | ConvertFrom-Json
    if ($report.detector -ne 'ff7-remake-tiled-local-light-dataflow-v1') { throw 'Unexpected detector ID' }
    if ($report.variantCount -ne 5) { throw 'Expected all five accepted variants' }
    if (@($report.variants | Where-Object classification -ne 'shared-tiled-local-light-evaluator').Count -ne 0) { throw 'A variant escaped the shared local-light classification' }
    foreach ($variant in $report.variants) {
        if (@($variant.checks.psobject.Properties.Value) -contains $false) { throw "A local-light invariant failed for $($variant.hash)" }
    }
    if ($report.correctedInterpretation.safeLabel -ne 'local-light distance-attenuation-mode flag') { throw 'Safe attenuation-mode label changed' }
    if ($report.correctedInterpretation.directionalOwnership -notmatch '^not evidenced') { throw 'Directional fail-closed classification regressed' }
    if ($report.correctedInterpretation.exactFieldIdentity -notmatch '^unresolved') { throw 'Exact-field evidence boundary regressed' }
} finally {
    foreach ($path in @($a,$b)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
}

Write-Host 'PASS: all five accepted shaders are pinned as shared tiled local-light evaluators; the attenuation-mode flag is not directional evidence.'

