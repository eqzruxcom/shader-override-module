[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\temporal-variant-generator-test\matrix')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$descriptorPath = Join-Path $repoRoot 'src\Engine\UE4\PassDescriptors\volumetric-scattering-history-sm5.json'
$generator = Join-Path $repoRoot 'tools\New-UE4TemporalScatteringVariant.ps1'
$descriptor = Get-Content -Raw -LiteralPath $descriptorPath | ConvertFrom-Json
$contract = $descriptor.runtimeContract
$current = [double]$contract.temporalCurrentWeight
$history = [double]$contract.temporalHistoryWeight

if ([Math]::Abs(($current + $history) - 1.0) -gt 0.000001) {
    throw 'Descriptor temporal weights do not sum to one.'
}

$expected = @(
    @{ target = 0.0; scale = 0.0 },
    @{ target = 0.25; scale = 0.689655172413793 },
    @{ target = 0.5; scale = 0.869565217391304 },
    @{ target = 0.75; scale = 0.952380952380952 },
    @{ target = 1.0; scale = 1.0 }
)

$declared = @($contract.postControlSynthesis.verifiedTargets)
foreach ($entry in $expected | Where-Object { $_.target -in @(0.25, 0.5, 0.75) }) {
    $match = @($declared | Where-Object { [double]$_.target -eq [double]$entry.target })
    if ($match.Count -ne 1) { throw "Descriptor is missing target $($entry.target)." }
    if ([Math]::Abs(([double]$match[0].perFrameScale) - [double]$entry.scale) -gt 0.000000001) {
        throw "Descriptor scale mismatch for target $($entry.target)."
    }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$results = foreach ($entry in $expected) {
    $percent = [int]([double]$entry.target * 100)
    $output = Join-Path $OutputDirectory ("generated-{0:D3}_cs.hlsl" -f $percent)
    $result = & $generator -TargetSteadyState ([double]$entry.target) -OutputHlsl $output -Compile
    $manifest = Get-Content -Raw -LiteralPath $result.Manifest | ConvertFrom-Json
    if ([Math]::Abs(([double]$manifest.perFrameScale) - [double]$entry.scale) -gt 0.000000001) {
        throw "Generated scale mismatch for target $($entry.target)."
    }
    if ($manifest.registers.sourceSrv -ne 't113' -or $manifest.registers.outputUav -ne 'u0') {
        throw "Generated register mismatch for target $($entry.target)."
    }
    [pscustomobject]@{
        target = [double]$entry.target
        perFrameScale = [double]$manifest.perFrameScale
        sourceSha256 = [string]$manifest.sourceSha256
        objectSha256 = [string]$manifest.objectSha256
        assemblySha256 = [string]$manifest.assemblySha256
    }
}

$report = [ordered]@{
    schemaVersion = 1
    descriptor = [string]$descriptor.id
    descriptorSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $descriptorPath).Hash
    temporalCurrentWeight = $current
    temporalHistoryWeight = $history
    cases = @($results)
    result = 'pass'
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$reportPath = Join-Path $OutputDirectory 'report.json'
[IO.File]::WriteAllText(
    $reportPath,
    (($report | ConvertTo-Json -Depth 6) + [Environment]::NewLine),
    [Text.UTF8Encoding]::new($false))

Write-Output 'UE4 temporal scattering variant tests passed.'
Write-Output "Report: $reportPath"
