[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$ProcessId,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$GameRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes',
    [ValidateRange(1,60)][int]$PollSeconds = 5,
    [ValidateRange(1,1440)][int]$MaxMinutes = 180,
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectPath "artifacts\runtime-health\watch-$ProcessId"
}
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $projectPath 'artifacts\runtime-health')).TrimEnd('\')
if (-not $outputRoot.StartsWith($allowedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Runtime watcher output must remain below artifacts/runtime-health.'
}
[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$checker = Join-Path $PSScriptRoot 'Get-IntergradeRuntimeHealth.ps1'
$startedAt = [DateTime]::UtcNow
$deadline = $startedAt.AddMinutes($MaxMinutes)
$startupPath = Join-Path $outputRoot 'startup.json'
$startup = & $checker -ProjectRoot $projectPath -GameRoot $GameRoot -ProcessId $ProcessId -OutputPath $startupPath
if ($startup.Classification -eq 'process-exited') { throw "Process $ProcessId was already absent when the watcher started." }
Write-Output "WATCHING PID=$ProcessId START=$($startedAt.ToString('o')) CLASSIFICATION=$($startup.Classification)"

$polls = 0
while ([DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Seconds $PollSeconds
    $polls++
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        $exitPath = Join-Path $outputRoot 'exit.json'
        $exit = & $checker -ProjectRoot $projectPath -GameRoot $GameRoot -ProcessId $ProcessId -OutputPath $exitPath
        $summary = [ordered]@{
            schemaVersion=1;processId=$ProcessId;startedAtUtc=$startedAt.ToString('o');observedExitAtUtc=[DateTime]::UtcNow.ToString('o')
            polls=$polls;classification=[string]$exit.Classification;startup='startup.json';exit='exit.json'
        }
        $summaryPath = Join-Path $outputRoot 'watch-summary.json'
        [IO.File]::WriteAllText($summaryPath,($summary|ConvertTo-Json -Depth 5)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
        Write-Output "EXIT PID=$ProcessId POLLS=$polls SNAPSHOT=$exitPath SUMMARY=$summaryPath"
        return
    }
}

$timeoutPath = Join-Path $outputRoot 'timeout.json'
$timeout = & $checker -ProjectRoot $projectPath -GameRoot $GameRoot -ProcessId $ProcessId -OutputPath $timeoutPath
Write-Output "TIMEOUT PID=$ProcessId POLLS=$polls CLASSIFICATION=$($timeout.Classification) SNAPSHOT=$timeoutPath"
