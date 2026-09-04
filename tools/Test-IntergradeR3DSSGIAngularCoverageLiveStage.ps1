[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$generator = Join-Path $PSScriptRoot 'New-IntergradeR3DSSGIAngularCoverageLiveCandidate.ps1'
$stager = Join-Path $PSScriptRoot 'Stage-IntergradeR3DSSGIAngularCoverage.ps1'
$pack = Join-Path $root 'artifacts\agent2-r3d-ssgi-angular-coverage-pack-v1'
$predecessor = Join-Path $root 'artifacts\agent2-r3d-ssgi-temporal-live-candidate-static-reprojection-v2'
$testRoot = Join-Path $root ('artifacts\angular-live-stage-tests\' + [Guid]::NewGuid().ToString('N'))
$candidate = Join-Path $testRoot 'Candidate'
$target = Join-Path $testRoot 'End\Binaries\Win64'
$mods = Join-Path $target 'Mods'
$fixes = Join-Path $target 'ShaderFixes'
$backups = Join-Path $testRoot 'Backups'

function Get-Hash([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash }
function Get-Tree([string]$Path) {
    $map = [ordered]@{}
    foreach ($file in @(Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName)) { $map[[IO.Path]::GetRelativePath($Path,$file.FullName)] = Get-Hash $file.FullName }
    return $map
}
function Assert-Tree([Collections.IDictionary]$Expected,[Collections.IDictionary]$Actual,[string]$Label) {
    if (([string]::Join('|',$Expected.Keys)) -cne ([string]::Join('|',$Actual.Keys))) { throw "$Label inventory changed." }
    foreach ($key in $Expected.Keys) { if ($Expected[$key] -ne $Actual[$key]) { throw "$Label hash changed: $key" } }
}

try {
    & $generator -PackRoot $pack -PredecessorCandidateRoot $predecessor -OutputRoot $candidate | Out-Null
    [void][IO.Directory]::CreateDirectory($mods)
    [void][IO.Directory]::CreateDirectory($fixes)
    $predecessorManifest = Get-Content -Raw -LiteralPath (Join-Path $predecessor 'manifest.json') | ConvertFrom-Json
    foreach ($entry in @($predecessorManifest.files)) {
        $relative = ([string]$entry.relativePath).Replace('/','\')
        $destinationRelative = if ($relative -eq 'Runtime\d3d11.dll') {'d3d11.dll'} else {$relative}
        $destination = Join-Path $target $destinationRelative
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        [IO.File]::Copy((Join-Path $predecessor $relative),$destination,$false)
    }
    $before = Get-Tree $target

    $status = & $stager -Action Status -TargetWin64Directory $target -CandidateRoot $candidate -PredecessorCandidateRoot $predecessor -BackupRoot $backups
    if ($status.Status -ne 'not-staged') { throw 'Initial status did not fail closed as not-staged.' }
    $ackRejected = $false
    try { & $stager -Action Stage -TargetWin64Directory $target -CandidateRoot $candidate -PredecessorCandidateRoot $predecessor -BackupRoot $backups -Confirm:$false | Out-Null } catch { $ackRejected = $_.Exception.Message -match 'AcknowledgeOfflineCandidate' }
    if (-not $ackRejected -or (Test-Path -LiteralPath $backups)) { throw 'Missing acknowledgement did not reject before writes.' }

    $unexpectedDense = Join-Path $mods 'Agent2R3DSSGITrace8E2AA_ps.hlsl'
    [IO.File]::WriteAllText($unexpectedDense,'pre-existing dense trace',[Text.UTF8Encoding]::new($false))
    $existingRejected = $false
    try { & $stager -Action Stage -TargetWin64Directory $target -CandidateRoot $candidate -PredecessorCandidateRoot $predecessor -BackupRoot $backups -AcknowledgeOfflineCandidate -Confirm:$false | Out-Null } catch { $existingRejected = $_.Exception.Message -match 'unexpectedly already exists' }
    if (-not $existingRejected -or (Test-Path -LiteralPath $backups)) { throw 'A pre-existing dense trace did not reject before backup or writes.' }
    [IO.File]::Delete($unexpectedDense)

    $staged = & $stager -Action Stage -TargetWin64Directory $target -CandidateRoot $candidate -PredecessorCandidateRoot $predecessor -BackupRoot $backups -AcknowledgeOfflineCandidate -Confirm:$false
    if ($staged.Status -ne 'staged' -or $staged.Files -ne 12 -or -not $staged.RelaunchRequired) { throw 'Stage result is incomplete.' }
    foreach ($name in @('Agent2R3DSSGITrace8E2AA_ps.hlsl','Agent2R3DSSGITrace16E2AA_ps.hlsl')) {
        if (-not (Test-Path -LiteralPath (Join-Path $mods $name) -PathType Leaf)) { throw "Dense trace was not staged: $name" }
    }
    $stageStatus = & $stager -Action Status -TargetWin64Directory $target -CandidateRoot $candidate -PredecessorCandidateRoot $predecessor -BackupRoot $backups
    if ($stageStatus.Status -ne 'staged') { throw 'Staged status verification failed.' }

    $trace = Join-Path $mods 'Agent2R3DSSGITrace8E2AA_ps.hlsl'
    [IO.File]::AppendAllText($trace,"`r`n// drift",[Text.UTF8Encoding]::new($false))
    $drift = & $stager -Action Status -TargetWin64Directory $target -CandidateRoot $candidate -PredecessorCandidateRoot $predecessor -BackupRoot $backups
    if ($drift.Status -ne 'drifted') { throw 'Staged drift was not detected.' }
    $restoreRejected = $false
    try { & $stager -Action Restore -TargetWin64Directory $target -CandidateRoot $candidate -PredecessorCandidateRoot $predecessor -BackupRoot $backups -Confirm:$false | Out-Null } catch { $restoreRejected = $_.Exception.Message -match 'drifted' }
    if (-not $restoreRejected) { throw 'Restore did not reject a drifted staged file.' }
    [IO.File]::Copy((Join-Path $candidate 'Mods\Agent2R3DSSGITrace8E2AA_ps.hlsl'),$trace,$true)

    $restored = & $stager -Action Restore -TargetWin64Directory $target -CandidateRoot $candidate -PredecessorCandidateRoot $predecessor -BackupRoot $backups -Confirm:$false
    if ($restored.Status -ne 'restored' -or $restored.Files -ne 12) { throw 'Restore result is incomplete.' }
    Assert-Tree $before (Get-Tree $target) 'Restored temporal predecessor'
    Write-Output 'PASS: angular live candidate rejects a pre-existing dense trace, stages twelve exact files, detects drift, refuses unsafe restore, and restores the complete temporal predecessor byte-for-byte without touching the game.'
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) { [IO.Directory]::Delete($testRoot,$true) }
}
