[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$stager=Join-Path $PSScriptRoot 'Stage-IntergradeLightingOwnershipCapture.ps1'
$pack=Join-Path $root 'artifacts\intergrade-lighting-ownership-capture-pack-20260904-v1'
$testRoot=Join-Path $root ('artifacts\lighting-ownership-stage-tests\'+[Guid]::NewGuid().ToString('N'))
$target=Join-Path $testRoot 'End\Binaries\Win64'
$mods=Join-Path $target 'Mods'
$backups=Join-Path $testRoot 'Backups'
[void][IO.Directory]::CreateDirectory($mods)
try{
    $status=& $stager -Action Status -TargetWin64Directory $target -PackRoot $pack -BackupRoot $backups
    if($status.Status -ne 'not-staged'){throw 'Initial capture-stage status is wrong.'}
    $ackRejected=$false
    try{& $stager -Action Stage -TargetWin64Directory $target -PackRoot $pack -BackupRoot $backups -Confirm:$false|Out-Null}catch{$ackRejected=$_.Exception.Message -match 'AcknowledgeCaptureOnly'}
    if(-not $ackRejected -or (Test-Path -LiteralPath $backups)){throw 'Capture stage did not reject missing acknowledgement before writes.'}
    $stage=& $stager -Action Stage -TargetWin64Directory $target -PackRoot $pack -BackupRoot $backups -AcknowledgeCaptureOnly -Confirm:$false
    if($stage.Status -ne 'staged' -or [bool]$stage.RenderingMutated -or $stage.KeysAdded -ne 0){throw 'Capture stage result violated its read-only contract.'}
    $ini=Join-Path $mods 'IntergradeLightingOwnershipCapture.ini'
    [IO.File]::AppendAllText($ini,"`r`n; drift",[Text.UTF8Encoding]::new($false))
    if((& $stager -Action Status -TargetWin64Directory $target -PackRoot $pack -BackupRoot $backups).Status -ne 'drifted'){throw 'Capture stage drift was not detected.'}
    $restoreRejected=$false
    try{& $stager -Action Restore -TargetWin64Directory $target -PackRoot $pack -BackupRoot $backups -Confirm:$false|Out-Null}catch{$restoreRejected=$_.Exception.Message -match 'drifted'}
    if(-not $restoreRejected){throw 'Capture restore accepted a drifted managed file.'}
    [IO.File]::Copy((Join-Path $pack 'Mods\IntergradeLightingOwnershipCapture.ini'),$ini,$true)
    $restore=& $stager -Action Restore -TargetWin64Directory $target -PackRoot $pack -BackupRoot $backups -Confirm:$false
    if($restore.Status -ne 'restored' -or (Test-Path -LiteralPath $ini)){throw 'Capture INI exact restore/removal failed.'}
    [pscustomobject]@{Result='pass';AtomicStage='verified';DriftGuard='verified';ExactRemoval='verified';RenderingMutated=$false;LiveGameTouched=$false}
}
finally{if(Test-Path -LiteralPath $testRoot -PathType Container){[IO.Directory]::Delete($testRoot,$true)}}

