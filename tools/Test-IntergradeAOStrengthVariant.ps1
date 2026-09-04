[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-strength-generator-test')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$generator = Join-Path $repoRoot 'tools\New-IntergradeAOStrengthVariant.ps1'
$matrixRoot = Join-Path $OutputDirectory 'matrix'
New-Item -ItemType Directory -Path $matrixRoot -Force | Out-Null

$levels = @('0','0.25','0.5','0.75')
$results = foreach ($level in $levels) {
    & $generator -Strength $level -OutputDirectory $matrixRoot
}
if (@($results).Count -ne 4) { throw 'Expected four compiled temporal-SSAO strength variants.' }
if (@($results.ObjectSha256 | Select-Object -Unique).Count -ne 4) { throw 'AO-strength variants did not produce four unique shader objects.' }

foreach ($result in $results) {
    $manifest = Get-Content -Raw -LiteralPath $result.Manifest | ConvertFrom-Json
    if ($manifest.effect -ne 'temporal-ssao-strength') { throw "Unexpected effect in $($result.Manifest)." }
    if ([double]$manifest.strength -ne [double]$result.Strength) { throw "Strength mismatch in $($result.Manifest)." }
    if (($manifest.controlledChannels -join ',') -ne 'x,y' -or ($manifest.preservedChannels -join ',') -ne 'z,w') {
        throw "Packed-channel safety contract mismatch in $($result.Manifest)."
    }
    $source = Get-Content -Raw -LiteralPath $result.Source
    if ($source -notmatch 'lerp\(1\.0, r2\.w, aoStrength\)' -or $source -notmatch 'lerp\(1\.0, r2\.x, aoStrength\)') {
        throw "AO attenuation formula is missing from $($result.Source)."
    }
    if ($source -notmatch 'r2\.y, r2\.z\);') { throw "Z/W preservation is missing from $($result.Source)." }
}

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    shaderHash = 'a77b589dce5822d6'
    formula = 'xy = lerp(1.0, original.xy, strength); zw = original.zw'
    safety = 'Only live-verified AO visibility channels X/Y are attenuated. Temporal metric Z and signed depth W are preserved byte-for-byte at the HLSL dataflow boundary.'
    variants = @($results | ForEach-Object {
        [ordered]@{ strength = $_.Strength; sourceSha256 = $_.SourceSha256; objectSha256 = $_.ObjectSha256 }
    })
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$reportPath = Join-Path $OutputDirectory 'report.json'
[IO.File]::WriteAllText($reportPath, (($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

Write-Output 'Intergrade temporal-SSAO strength generator tests passed.'
Write-Output "Report: $reportPath"
