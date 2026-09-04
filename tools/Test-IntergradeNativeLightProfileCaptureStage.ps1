[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$generator = Join-Path $PSScriptRoot 'New-IntergradeNativeLightProfileCapturePack.ps1'
$verifier = Join-Path $PSScriptRoot 'Test-IntergradeNativeLightProfileCapturePack.ps1'
$stager = Join-Path $PSScriptRoot 'Stage-IntergradeNativeLightProfileCapture.ps1'
$familyRoot = Join-Path $root 'artifacts\accepted-contact-family-rebuild-20260904-v2-portable'
$testRoot = Join-Path $root ('artifacts\native-light-profile-capture-stage-tests\' + [Guid]::NewGuid().ToString('N'))
$pack = Join-Path $testRoot 'Pack'
$target = Join-Path $testRoot 'End\Binaries\Win64'
$mods = Join-Path $target 'Mods'
$backups = Join-Path $testRoot 'Backups'

try {
    & $generator -AcceptedFamilyRoot $familyRoot -OutputRoot $pack | Out-Null
    & $verifier -PackRoot $pack | Out-Null
    [void][IO.Directory]::CreateDirectory($mods)
    $status = & $stager -Action Status -TargetWin64Directory $target -PackRoot $pack -BackupRoot $backups
    if ($status.Status -ne 'not-staged') { throw 'Initial capture-stage status is wrong.' }
    $ackRejected = $false
    try { & $stager -Action Stage -TargetWin64Directory $target -PackRoot $pack -BackupRoot $backups -Confirm:$false | Out-Null } catch { $ackRejected = $_.Exception.Message -match 'AcknowledgeCaptureOnly' }
    if (-not $ackRejected -or (Test-Path -LiteralPath $backups)) { throw 'Capture stage did not reject missing acknowledgement before writes.' }
    $stage = & $stager -Action Stage -TargetWin64Directory $target -PackRoot $pack -BackupRoot $backups -AcknowledgeCaptureOnly -Confirm:$false
    if ($stage.Status -ne 'staged' -or [bool]$stage.RenderingMutated -or $stage.KeysAdded -ne 0) { throw 'Capture stage result violated its read-only contract.' }
    $ini = Join-Path $mods 'IntergradeNativeLightProfileCapture.ini'
    [IO.File]::AppendAllText($ini,"`r`n; drift",[Text.UTF8Encoding]::new($false))
    if ((& $stager -Action Status -TargetWin64Directory $target -PackRoot $pack -BackupRoot $backups).Status -ne 'drifted') { throw 'Capture stage drift was not detected.' }
    $restoreRejected = $false
    try { & $stager -Action Restore -TargetWin64Directory $target -PackRoot $pack -BackupRoot $backups -Confirm:$false | Out-Null } catch { $restoreRejected = $_.Exception.Message -match 'drifted' }
    if (-not $restoreRejected) { throw 'Capture restore accepted a drifted managed file.' }
    [IO.File]::Copy((Join-Path $pack 'Mods\IntergradeNativeLightProfileCapture.ini'),$ini,$true)
    $restore = & $stager -Action Restore -TargetWin64Directory $target -PackRoot $pack -BackupRoot $backups -Confirm:$false
    if ($restore.Status -ne 'restored' -or (Test-Path -LiteralPath $ini)) { throw 'Capture INI exact restore/removal failed.' }
    [pscustomobject]@{Result='pass';FreshGeneration='verified';AtomicStage='verified';DriftGuard='verified';ExactRemoval='verified';RenderingMutated=$false;LiveGameTouched=$false}
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) { [IO.Directory]::Delete($testRoot,$true) }
}
