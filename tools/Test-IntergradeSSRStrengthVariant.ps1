[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ssr-strength-generator-test')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$generator = Join-Path $repoRoot 'tools\New-IntergradeSSRStrengthVariant.ps1'
$matrixRoot = Join-Path $OutputDirectory 'matrix'
New-Item -ItemType Directory -Path $matrixRoot -Force | Out-Null

$levels = @('0','0.25','0.5','0.75')
$results = foreach ($level in $levels) {
    & $generator -Strength $level -OutputDirectory $matrixRoot
}
if (@($results).Count -ne 4) { throw 'Expected four compiled SSR strength variants.' }
if (@($results.ObjectSha256 | Select-Object -Unique).Count -ne 4) { throw 'SSR-strength variants did not produce four unique shader objects.' }

foreach ($result in $results) {
    $manifest = Get-Content -Raw -LiteralPath $result.Manifest | ConvertFrom-Json
    if ($manifest.effect -ne 'screen-space-reflection-strength') { throw "Unexpected effect in $($result.Manifest)." }
    if ([double]$manifest.strength -ne [double]$result.Strength) { throw "Strength mismatch in $($result.Manifest)." }
    if (($manifest.controlledChannels -join ',') -ne 'x,y,z' -or ($manifest.preservedChannels -join ',') -ne 'w') {
        throw "Packed-channel safety contract mismatch in $($result.Manifest)."
    }
    $source = Get-Content -Raw -LiteralPath $result.Source
    if ($source -notmatch 'o0\.xyz = cb1\[128\]\.xxx \* r0\.xyz \* ssrStrength;') {
        throw "SSR radiance attenuation formula is missing from $($result.Source)."
    }
    if ($source -notmatch '(?m)^      o0\.w = r0\.w;$') {
        throw "SSR alpha preservation is missing from $($result.Source)."
    }
}

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    shaderHash = 'b2bc6059f9a39c7f'
    formula = 'rgb = original.rgb * strength; a = original.a'
    safety = 'Only reflection-radiance RGB is attenuated. Hit or confidence alpha is preserved at the original HLSL dataflow boundary.'
    variants = @($results | ForEach-Object {
        [ordered]@{ strength = $_.Strength; sourceSha256 = $_.SourceSha256; objectSha256 = $_.ObjectSha256 }
    })
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$reportPath = Join-Path $OutputDirectory 'report.json'
[IO.File]::WriteAllText($reportPath, (($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

Write-Output 'Intergrade SSR strength generator tests passed.'
Write-Output "Report: $reportPath"
