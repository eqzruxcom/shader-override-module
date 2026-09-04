[CmdletBinding()]
param(
    [string]$SourceLog = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\FrameAnalysis-2026-09-04-001641\log.txt'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspaceRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifactRoot = Join-Path $workspaceRoot 'artifacts'
$testParent = Join-Path $artifactRoot 'lighting-ownership-ingest-tests'
$testRoot = Join-Path $testParent ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff'))
$captureRoot = Join-Path $testRoot 'captures'
$capture = Join-Path $captureRoot 'FrameAnalysis-known'
$output = Join-Path $testRoot 'result.json'
$incompleteOutput = Join-Path $testRoot 'incomplete.json'
$analyzer = Join-Path $PSScriptRoot 'Invoke-IntergradeLightingOwnershipCaptureAnalysis.ps1'

if (-not (Test-Path -LiteralPath $SourceLog -PathType Leaf)) { throw "Pinned source log is missing: $SourceLog" }
[void](New-Item -ItemType Directory -Path $capture -Force)
Copy-Item -LiteralPath $SourceLog -Destination (Join-Path $capture 'log.txt')

try {
    & $analyzer -CaptureRoot $captureRoot -Target @('c473ab75b7519f7e:ps','a26b3473289dba2d:cs') -OutputPath $output | Out-Null
    $report = Get-Content -Raw -LiteralPath $output | ConvertFrom-Json
    if ($report.result -ne 'pass' -or [int]$report.captureCount -ne 1 -or @($report.missingIdentities).Count) {
        throw 'Known-capture aggregation did not pass cleanly.'
    }
    $c473 = @($report.captures[0].targets | Where-Object identity -eq 'c473ab75b7519f7e-ps')
    $a26 = @($report.captures[0].targets | Where-Object identity -eq 'a26b3473289dba2d-cs')
    if ($c473.Count -ne 1 -or -not $c473[0].observed -or [int]$c473[0].executionCount -ne 1) { throw 'c473 was not aggregated exactly once.' }
    if ($a26.Count -ne 1 -or -not $a26[0].observed -or [int]$a26[0].executionCount -ne 1) { throw 'a26 was not aggregated exactly once.' }
    $c473First = @($c473[0].executions[0].outputs | Where-Object slot -eq 0)[0].firstConsumer
    $a26First = @($a26[0].executions[0].outputs | Where-Object slot -eq 1)[0].firstConsumer
    if ($c473First.identity -ne 'af6cd28a0108a18a-ps' -or @($c473First.inputSlots) -notcontains 0) {
        throw 'c473 first-consumer aggregation changed.'
    }
    if ($a26First.identity -ne '58101bdcc044cd88-cs' -or @($a26First.inputSlots) -notcontains 0) {
        throw 'a26 first-consumer aggregation changed.'
    }

    $duplicateRejected = $false
    try {
        & $analyzer -CaptureRoot $captureRoot -Target @('c473ab75b7519f7e:ps','c473ab75b7519f7e:ps') -OutputPath (Join-Path $testRoot 'duplicate.json') | Out-Null
    } catch { $duplicateRejected = $_.Exception.Message -match 'Duplicate targets' }
    if (-not $duplicateRejected) { throw 'Duplicate target guard did not reject.' }

    $missingRejected = $false
    try {
        & $analyzer -CaptureRoot $captureRoot -Target @('adb544f9a11d6c7e:cs') -OutputPath $incompleteOutput -RequireObserved | Out-Null
    } catch { $missingRejected = $_.Exception.Message -match 'not observed' }
    if (-not $missingRejected -or -not (Test-Path -LiteralPath $incompleteOutput)) { throw 'RequireObserved did not fail closed with a report.' }
    $incomplete = Get-Content -Raw -LiteralPath $incompleteOutput | ConvertFrom-Json
    if ($incomplete.result -ne 'incomplete' -or @($incomplete.missingIdentities) -notcontains 'adb544f9a11d6c7e-cs') {
        throw 'Incomplete report did not preserve the missing target.'
    }

    [pscustomobject]@{
        Result = 'pass'
        CaptureAggregation = 'verified'
        FirstConsumerChains = 'verified'
        DuplicateGuard = 'verified'
        MissingTargetGuard = 'verified'
        LiveGameTouched = $false
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
