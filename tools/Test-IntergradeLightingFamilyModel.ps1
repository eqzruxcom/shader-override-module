[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$resolver = Join-Path $PSScriptRoot 'Resolve-IntergradeLightingFamilyModel.ps1'
$a = Join-Path $root 'artifacts\analysis\intergrade-lighting-family-model.test-a.json'
$b = Join-Path $root 'artifacts\analysis\intergrade-lighting-family-model.test-b.json'

try {
    & $resolver -OutputPath $a | Out-Host
    & $resolver -OutputPath $b | Out-Host
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $a).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $b).Hash) { throw 'Lighting-family model is not deterministic' }
    $report = Get-Content -Raw -LiteralPath $a | ConvertFrom-Json
    if ($report.detector -ne 'ff7-remake-lighting-family-model-v3' -or $report.schemaVersion -ne 3) { throw 'Unexpected lighting-family model schema' }
    if ($report.provenLocalLightFamily.variantCount -ne 5 -or $report.provenLocalLightFamily.captureCount -ne 5) { throw 'Five-variant/five-capture contract changed' }
    if (@($report.provenLocalLightFamily.variants | Where-Object { -not $_.localPointOrSpotDataflow -or -not $_.angularProfileBranch }).Count -ne 0) { throw 'Local/profile family invariant regressed' }
    if (@($report.provenLocalLightFamily.variants | Where-Object attenuationModeIsDirectionalClassifier).Count -ne 0) { throw 'Attenuation mode was incorrectly promoted to a directional classifier' }
    if (@($report.provenLocalLightFamily.variants | Where-Object outputComposition -ne 'read-modify-write-existing-lighting').Count -ne 0) { throw 'Read/modify/write invariant regressed' }
    if ($report.unresolvedCoverage.directionalLightOwner -notmatch '^not captured') { throw 'Directional coverage was overclaimed' }
    if ($report.indirectLighting.preparedNextBoundary -ne 'c473ab75b7519f7e-ps') { throw 'Pre-temporal boundary changed' }
    if ($report.indirectLighting.nativeVelocityReduction -ne 'a26b3473289dba2d' -or $report.indirectLighting.nativeVelocityDilation -ne '58101bdcc044cd88') { throw 'Native velocity negative controls changed' }
    if ($report.immutableKeyContract.F10 -notmatch 'reload only' -or $report.immutableKeyContract.F2 -notmatch 'experiment toggle only') { throw 'Key contract regressed' }
} finally {
    foreach ($path in @($a,$b)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
}

Write-Host 'PASS: resolved lighting-family model preserves five local-light buckets, integrated profiles, native velocity, missing directional ownership, and the key contract.'

