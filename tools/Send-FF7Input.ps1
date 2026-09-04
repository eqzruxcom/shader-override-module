[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('focus', 'screenshot', 'f2', 'reload', 'frameanalysis', 'enter', 'pageup', 'pagedown', 'clearhunt')]
    [string]$Command,

    [switch]$DryRun,

    [switch]$RequireIpc,

    [switch]$ContinueSequence,

    [string]$ExpectedExe = 'ff7remake_.exe',

    [string]$ReceiptDirectory = (Join-Path $PSScriptRoot '..\artifacts\game-input')
)

$ErrorActionPreference = 'Stop'

$ahk = Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'
$controller = Join-Path $PSScriptRoot 'FF7-InputController.ahk'

if (-not (Test-Path -LiteralPath $ahk -PathType Leaf)) {
    throw "AutoHotkey v2 was not found at: $ahk"
}
if (-not (Test-Path -LiteralPath $controller -PathType Leaf)) {
    throw "FF7 input controller was not found at: $controller"
}

$stamp = [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$receipt = Join-Path $ReceiptDirectory "$stamp-$Command.json"
$arguments = @($controller, $Command, '--expected-exe', $ExpectedExe, '--receipt', $receipt)
if ($DryRun) { $arguments += '--dry-run' }
if ($RequireIpc) { $arguments += '--require-ipc' }
if ($ContinueSequence) { $arguments += '--skip-warning' }

$action = if ($DryRun) { "Verify one $ExpectedExe window without sending $Command" } elseif ($ContinueSequence) { "Continue the current warned control sequence with $Command" } else { "Warn for five seconds, then begin a control sequence with $Command" }
if (-not $PSCmdlet.ShouldProcess($ExpectedExe, $action)) { return }

# AutoHotkey64.exe is a GUI-subsystem process. Invoke it through ProcessStartInfo
# so paths remain exact and PowerShell waits until the one-shot controller exits.
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $ahk
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
foreach ($argument in $arguments) {
    [void]$startInfo.ArgumentList.Add($argument)
}

$process = [System.Diagnostics.Process]::Start($startInfo)
$stdout = $process.StandardOutput.ReadToEnd()
$stderr = $process.StandardError.ReadToEnd()
$process.WaitForExit()

if ($process.ExitCode -ne 0) {
    throw "FF7 input controller exited with code $($process.ExitCode). $stderr Receipt: $receipt"
}
if (-not (Test-Path -LiteralPath $receipt -PathType Leaf)) {
    throw "FF7 input controller did not write its receipt. Output: $stdout"
}

$result = Get-Content -Raw -LiteralPath $receipt | ConvertFrom-Json
if ($DryRun -and $result.status -ne 'dry-run-pass') {
    throw "Unexpected dry-run status: $($result.status)"
}
if (-not $DryRun -and $result.status -ne 'sent') {
    throw "Unexpected input status: $($result.status)"
}

$result
