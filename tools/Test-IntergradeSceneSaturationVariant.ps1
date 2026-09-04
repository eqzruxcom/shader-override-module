[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\scene-saturation-generator-test')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$generator = Join-Path $repoRoot 'tools\New-IntergradeSceneSaturationVariant.ps1'
$matrixRoot = Join-Path $OutputDirectory 'matrix'
New-Item -ItemType Directory -Path $matrixRoot -Force | Out-Null

$results = foreach ($level in @(0.0, 0.25, 0.5, 0.75)) {
    & $generator -Saturation $level -OutputDirectory $matrixRoot
}
if (@($results).Count -ne 4) { throw 'Expected four generated saturation variants.' }
if (@($results.ObjectSha256 | Select-Object -Unique).Count -ne 4) {
    throw 'Saturation variants did not produce four unique shader objects.'
}
foreach ($result in $results) {
    if (-not (Test-Path -LiteralPath $result.Source -PathType Leaf)) { throw "Missing source: $($result.Source)" }
    if (-not (Test-Path -LiteralPath $result.Object -PathType Leaf)) { throw "Missing object: $($result.Object)" }
    if (-not (Test-Path -LiteralPath $result.Manifest -PathType Leaf)) { throw "Missing manifest: $($result.Manifest)" }
}

$invalidRejected = $false
try { & $generator -Saturation 0.333 -OutputDirectory $matrixRoot | Out-Null }
catch { $invalidRejected = $_.Exception.Message -match 'whole percentage point' }
if (-not $invalidRejected) { throw 'Non-whole saturation percentage was not rejected.' }

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    levels = @($results | ForEach-Object {
        [ordered]@{
            saturation = $_.Saturation
            sourceSha256 = $_.SourceSha256
            objectSha256 = $_.ObjectSha256
        }
    })
    negativeCases = @('non-whole-percentage')
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$reportPath = Join-Path $OutputDirectory 'report.json'
[IO.File]::WriteAllText($reportPath, (($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

Write-Output 'Intergrade scene-saturation variant tests passed.'
Write-Output "Report: $reportPath"
