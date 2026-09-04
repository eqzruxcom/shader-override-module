[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ssr-composite-probe-test')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$generator = Join-Path $repoRoot 'tools\New-IntergradeSSRCompositeProbe.ps1'
$modes = @('RawRgb', 'AmplifiedRgb', 'HitMask', 'RadianceMask')
$results = foreach ($mode in $modes) {
    & $generator -Mode $mode -OutputDirectory $OutputDirectory
}

if ($results.Count -ne 4) { throw "Expected four SSR composite probes, got $($results.Count)." }
if (@($results.ObjectSha256 | Select-Object -Unique).Count -ne 4) { throw 'SSR composite probes did not produce four unique objects.' }

foreach ($result in $results) {
    $manifest = Get-Content -Raw -LiteralPath $result.Manifest | ConvertFrom-Json
    if ($manifest.mode -ne $result.Mode) { throw "Manifest mode mismatch for $($result.Mode)." }
    if ($manifest.shaderHash -ne 'e2aa1c8cb39e0a55') { throw 'Unexpected downstream composite hash.' }
    if ($manifest.producerShader -ne 'b2bc6059f9a39c7f') { throw 'Unexpected SSR producer hash.' }
    if ($manifest.sourceSlot -ne 't11' -or $manifest.sourceResourceHash -ne '36f63b9f') {
        throw "Resource contract mismatch for $($result.Mode)."
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $result.Source).Hash -ne $manifest.sourceSha256) {
        throw "Source hash mismatch for $($result.Mode)."
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $result.Object).Hash -ne $manifest.objectSha256) {
        throw "Object hash mismatch for $($result.Mode)."
    }
}

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    modes = @($results | ForEach-Object {
        [ordered]@{
            mode = $_.Mode
            sourceSha256 = $_.SourceSha256
            objectSha256 = $_.ObjectSha256
        }
    })
}
$reportPath = Join-Path $OutputDirectory 'report.json'
[IO.File]::WriteAllText($reportPath, (($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

Write-Output 'Intergrade downstream SSR composite probe tests passed.'
Write-Output "Report: $reportPath"
