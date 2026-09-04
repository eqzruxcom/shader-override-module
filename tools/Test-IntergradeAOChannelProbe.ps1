[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-channel-probe-test')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$generator = Join-Path $repoRoot 'tools\New-IntergradeAOChannelProbe.ps1'
$matrixRoot = Join-Path $OutputDirectory 'matrix'
New-Item -ItemType Directory -Path $matrixRoot -Force | Out-Null

$results = foreach ($channel in @('x','y','z','w')) {
    & $generator -ZeroChannel $channel -OutputDirectory $matrixRoot
}
if (@($results).Count -ne 4) { throw 'Expected four temporal-SSAO channel-isolation variants.' }
if (@($results.ObjectSha256 | Select-Object -Unique).Count -ne 4) { throw 'Temporal-SSAO channel probes did not produce four unique objects.' }
foreach ($result in $results) {
    $manifest = Get-Content -Raw -LiteralPath $result.Manifest | ConvertFrom-Json
    if ($manifest.zeroChannel -ne $result.ZeroChannel -or $manifest.verification -ne 'strict-compile-diagnostic-only') {
        throw "Probe manifest mismatch for channel $($result.ZeroChannel)."
    }
}

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    shaderHash = 'a77b589dce5822d6'
    warning = 'Packed output contains current AO, temporal AO/history data, reprojection weight, and signed depth; do not uniformly scale xyzw.'
    probes = @($results | ForEach-Object {
        [ordered]@{ zeroChannel = $_.ZeroChannel; sourceSha256 = $_.SourceSha256; objectSha256 = $_.ObjectSha256 }
    })
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$reportPath = Join-Path $OutputDirectory 'report.json'
[IO.File]::WriteAllText($reportPath, (($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

Write-Output 'Intergrade temporal-SSAO packed-channel probe tests passed.'
Write-Output "Report: $reportPath"
