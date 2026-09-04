[CmdletBinding()]
param(
    [string]$ExpectedExe = 'ff7remake_.exe',
    [switch]$SkipLiveDryRun
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$controller = Join-Path $root 'tools\FF7-InputController.ahk'
$wrapper = Join-Path $root 'tools\Send-FF7Input.ps1'
$ahk = Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'
$run = Join-Path $root ('artifacts\controller-contract-tests\' + [datetime]::UtcNow.ToString('yyyyMMdd-HHmmssfff'))
New-Item -ItemType Directory -Path $run -Force | Out-Null

function Invoke-AhkController([string[]]$Arguments) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $ahk
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in $Arguments) { [void]$info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($info)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $stdout; Stderr = $stderr }
}

$selfReceipt = Join-Path $run 'self-test.json'
$self = Invoke-AhkController @($controller, '--receipt', $selfReceipt, '--self-test')
if ($self.ExitCode -ne 0) { throw "Self-test failed: $($self.Stderr)" }
$selfResult = Get-Content -Raw -LiteralPath $selfReceipt | ConvertFrom-Json
if ($selfResult.status -ne 'self-test-pass' -or $selfResult.warningDelayMilliseconds -ne 0) {
    throw 'Unexpected self-test receipt.'
}

$invalidReceipt = Join-Path $run 'invalid-command.json'
$invalid = Invoke-AhkController @($controller, 'arbitrary-key', '--receipt', $invalidReceipt)
if ($invalid.ExitCode -eq 0) { throw 'The arbitrary command was not rejected.' }
$invalidResult = Get-Content -Raw -LiteralPath $invalidReceipt | ConvertFrom-Json
if ($invalidResult.status -ne 'error' -or $invalidResult.message -ne 'Command is not whitelisted') {
    throw 'Unexpected invalid-command receipt.'
}

$liveResult = $null
if (-not $SkipLiveDryRun) {
    $liveResult = & $wrapper -Command clearhunt -ExpectedExe $ExpectedExe -DryRun -ReceiptDirectory $run
    if ($liveResult.status -ne 'dry-run-pass' -or $liveResult.warningDelayMilliseconds -ne 0) {
        throw 'Unexpected live dry-run receipt.'
    }
}

[pscustomobject]@{
    Result = 'pass'
    Directory = $run
    SelfTest = $selfResult.status
    ArbitraryCommandRejected = $true
    LiveDryRun = if ($liveResult) { $liveResult.method } else { 'skipped' }
    InputSent = $false
}
