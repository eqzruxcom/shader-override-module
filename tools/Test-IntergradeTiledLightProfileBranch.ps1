[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$analyzer = Join-Path $PSScriptRoot 'Analyze-IntergradeTiledLightProfileBranch.ps1'
$a = Join-Path $root 'artifacts\analysis\intergrade-tiled-light-profile-branch.test-a.json'
$b = Join-Path $root 'artifacts\analysis\intergrade-tiled-light-profile-branch.test-b.json'

try {
    & $analyzer -OutputPath $a | Out-Host
    & $analyzer -OutputPath $b | Out-Host
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $a).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $b).Hash) {
        throw 'Tiled-light profile report is not deterministic'
    }
    $report = Get-Content -Raw -LiteralPath $a | ConvertFrom-Json
    if ($report.detector -ne 'ff7-remake-tiled-light-angular-profile-branch-v1') { throw 'Unexpected detector ID' }
    if ($report.variantCount -ne 5) { throw 'Expected all five accepted variants' }
    if (@($report.variants | Where-Object outputComposition -eq 'read-modify-write-existing-lighting').Count -ne 5) { throw 'All-five read/modify/write invariant changed' }
    if (@($report.variants | Where-Object profileTextureSlot -eq 7).Count -ne 2) { throw 'Lower-register variant count changed' }
    if (@($report.variants | Where-Object profileTextureSlot -eq 8).Count -ne 3) { throw 'Higher-register variant count changed' }
    if (@($report.variants | Where-Object { $_.priorLightingTextureSlot -ne ($_.profileTextureSlot + 1) }).Count -ne 0) { throw 'Profile/prior-lighting adjacency changed' }
    foreach ($variant in $report.variants) {
        if (@($variant.checks.psobject.Properties.Value) -contains $false) { throw "A profile invariant check failed for $($variant.hash)" }
    }
    if ($report.classification.runtimeActivation -notmatch '^not proven') { throw 'Runtime activation evidence gate regressed' }
    if ($report.classification.directionalOwnership -notmatch '^unchanged and still unproven') { throw 'Directional evidence gate regressed' }
} finally {
    foreach ($path in @($a,$b)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
}

Write-Host 'PASS: all five tiled-light variants retain the angular profile atlas and read/modify/write prior-lighting chain with register-shifted bindings.'
