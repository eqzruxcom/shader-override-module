[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$stager = Join-Path $PSScriptRoot 'Stage-IntergradeR3DSSGIPreTemporal.ps1'
$working = Join-Path $root 'artifacts\agent2-r3d-ssgi-late-scene-pack'
$pack = Join-Path $root 'artifacts\agent2-r3d-ssgi-pre-temporal-pack'
$testRoot = Join-Path $root ('artifacts\pre-temporal-stage-tests\' + [Guid]::NewGuid().ToString('N'))
$target = Join-Path $testRoot 'End\Binaries\Win64'
$mods = Join-Path $target 'Mods'
$fixes = Join-Path $target 'ShaderFixes'
$backups = Join-Path $testRoot 'Backups'
[void][IO.Directory]::CreateDirectory($mods)
[void][IO.Directory]::CreateDirectory($fixes)

function Get-Tree([string]$Path) {
    $map=[ordered]@{}
    foreach($file in @(Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName)){$map[[IO.Path]::GetRelativePath($Path,$file.FullName)]=(Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash}
    $map
}
function Assert-Tree([Collections.IDictionary]$Expected,[Collections.IDictionary]$Actual,[string]$Label){
    if(([string]::Join('|',$Expected.Keys)) -cne ([string]::Join('|',$Actual.Keys))){throw "$Label inventory changed."}
    foreach($key in $Expected.Keys){if($Expected[$key] -ne $Actual[$key]){throw "$Label hash changed: $key"}}
}

try {
    $workingManifest=Get-Content -Raw -LiteralPath (Join-Path $working 'manifest.json')|ConvertFrom-Json
    foreach($entry in @($workingManifest.payloadFiles)){
        $relative=([string]$entry.relativePath).Replace('/','\')
        $source=Join-Path $working $relative
        $destination=Join-Path $target $relative
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        [IO.File]::Copy($source,$destination,$false)
    }
    $before=Get-Tree $target
    $status=& $stager -Action Status -TargetWin64Directory $target -PackRoot $pack -WorkingPackRoot $working -BackupRoot $backups
    if($status.Status -ne 'not-staged'){throw 'Initial status did not fail closed as not-staged.'}

    $ackRejected=$false
    try{& $stager -Action Stage -TargetWin64Directory $target -PackRoot $pack -WorkingPackRoot $working -BackupRoot $backups -Confirm:$false|Out-Null}catch{$ackRejected=$_.Exception.Message -match 'AcknowledgeOfflineCandidate'}
    if(-not $ackRejected -or (Test-Path -LiteralPath $backups)){throw 'Missing acknowledgement did not reject before writes.'}

    $staged=& $stager -Action Stage -TargetWin64Directory $target -PackRoot $pack -WorkingPackRoot $working -BackupRoot $backups -AcknowledgeOfflineCandidate -Confirm:$false
    if($staged.Status -ne 'staged' -or -not $staged.Af6Quarantined -or $staged.Files -ne 9){throw 'Stage result is incomplete.'}
    if(Test-Path -LiteralPath (Join-Path $fixes 'af6cd28a0108a18a-ps.txt')){throw 'Late-scene af6 replacement survived pre-temporal staging.'}
    $ini=Get-Content -Raw -LiteralPath (Join-Path $mods 'Agent2R3DSSGITest.ini')
    if($ini -notmatch '(?im)^hash\s*=\s*c473ab75b7519f7e\s*$' -or $ini -match '(?im)^hash\s*=\s*af6cd28a0108a18a\s*$'){throw 'Staged hook ownership is wrong.'}
    $stageStatus=& $stager -Action Status -TargetWin64Directory $target -PackRoot $pack -WorkingPackRoot $working -BackupRoot $backups
    if($stageStatus.Status -ne 'staged'){throw 'Staged status verification failed.'}

    $trace=Join-Path $mods 'Agent2R3DSSGITraceE2AA_ps.hlsl'
    [IO.File]::AppendAllText($trace,"`r`n// drift",[Text.UTF8Encoding]::new($false))
    $drift=& $stager -Action Status -TargetWin64Directory $target -PackRoot $pack -WorkingPackRoot $working -BackupRoot $backups
    if($drift.Status -ne 'drifted'){throw 'Staged drift was not detected.'}
    $restoreRejected=$false
    try{& $stager -Action Restore -TargetWin64Directory $target -PackRoot $pack -WorkingPackRoot $working -BackupRoot $backups -Confirm:$false|Out-Null}catch{$restoreRejected=$_.Exception.Message -match 'drifted'}
    if(-not $restoreRejected){throw 'Restore did not reject a drifted staged file.'}
    [IO.File]::Copy((Join-Path $pack 'Mods\Agent2R3DSSGITraceE2AA_ps.hlsl'),$trace,$true)

    $restored=& $stager -Action Restore -TargetWin64Directory $target -PackRoot $pack -WorkingPackRoot $working -BackupRoot $backups -Confirm:$false
    if($restored.Status -ne 'restored' -or -not $restored.Af6Restored -or $restored.Files -ne 9){throw 'Restore result is incomplete.'}
    Assert-Tree $before (Get-Tree $target) 'Restored predecessor'
    [pscustomobject]@{Result='pass';FilesTransitioned=9;Af6Quarantine='verified';DriftGuard='verified';ExactRestore='verified';LiveGameTouched=$false}
}
finally {
    if(Test-Path -LiteralPath $testRoot -PathType Container){[IO.Directory]::Delete($testRoot,$true)}
}

