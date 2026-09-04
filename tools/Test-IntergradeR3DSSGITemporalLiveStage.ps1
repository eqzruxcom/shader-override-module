[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$generator = Join-Path $PSScriptRoot 'New-IntergradeR3DSSGITemporalLiveCandidate.ps1'
$stager = Join-Path $PSScriptRoot 'Stage-IntergradeR3DSSGITemporalHistory.ps1'
$candidate = Join-Path $root 'artifacts\agent2-r3d-ssgi-temporal-live-candidate'
$predecessor = Join-Path $root 'artifacts\agent2-r3d-ssgi-pre-temporal-pack'
$testRoot = Join-Path $root ('artifacts\temporal-live-stage-tests\' + [Guid]::NewGuid().ToString('N'))
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
    & $generator | Out-Null
    [void][IO.Directory]::CreateDirectory($mods)
    [void][IO.Directory]::CreateDirectory($fixes)
    $predecessorManifest = Get-Content -Raw -LiteralPath (Join-Path $predecessor 'manifest.json') | ConvertFrom-Json
    foreach ($entry in @($predecessorManifest.files)) { [IO.File]::Copy((Join-Path (Join-Path $predecessor 'Mods') ([string]$entry.name)),(Join-Path $mods ([string]$entry.name)),$false) }
    $wrapper = Join-Path $target 'd3d11.dll'
    [IO.File]::WriteAllText($wrapper,'fixture predecessor wrapper',[Text.UTF8Encoding]::new($false))
    $wrapperHash = Get-Hash $wrapper
    $before = Get-Tree $target

    $status = & $stager -Action Status -TargetWin64Directory $target -CandidateRoot $candidate -PredecessorPackRoot $predecessor -BackupRoot $backups -ExpectedPredecessorWrapperSha256 $wrapperHash
    if ($status.Status -ne 'not-staged') { throw 'Initial status did not fail closed as not-staged.' }
    $ackRejected = $false
    try { & $stager -Action Stage -TargetWin64Directory $target -CandidateRoot $candidate -PredecessorPackRoot $predecessor -BackupRoot $backups -ExpectedPredecessorWrapperSha256 $wrapperHash -Confirm:$false | Out-Null } catch { $ackRejected = $_.Exception.Message -match 'AcknowledgeOfflineCandidate' }
    if (-not $ackRejected -or (Test-Path -LiteralPath $backups)) { throw 'Missing acknowledgement did not reject before writes.' }

    $staged = & $stager -Action Stage -TargetWin64Directory $target -CandidateRoot $candidate -PredecessorPackRoot $predecessor -BackupRoot $backups -ExpectedPredecessorWrapperSha256 $wrapperHash -AcknowledgeOfflineCandidate -Confirm:$false
    if ($staged.Status -ne 'staged' -or $staged.Files -ne 10 -or -not $staged.RelaunchRequired) { throw 'Stage result is incomplete.' }
    $candidateManifest = Get-Content -Raw -LiteralPath (Join-Path $candidate 'manifest.json') | ConvertFrom-Json
    if ((Get-Hash $wrapper) -ne [string]$candidateManifest.wrapper.sha256) { throw 'Candidate wrapper was not staged exactly.' }
    if (-not (Test-Path -LiteralPath (Join-Path $mods 'Agent2R3DSSGITemporalHistory_ps.hlsl') -PathType Leaf)) { throw 'Temporal shader was not staged.' }
    $stageStatus = & $stager -Action Status -TargetWin64Directory $target -CandidateRoot $candidate -PredecessorPackRoot $predecessor -BackupRoot $backups -ExpectedPredecessorWrapperSha256 $wrapperHash
    if ($stageStatus.Status -ne 'staged') { throw 'Staged status verification failed.' }

    $trace = Join-Path $mods 'Agent2R3DSSGITraceE2AA_ps.hlsl'
    [IO.File]::AppendAllText($trace,"`r`n// drift",[Text.UTF8Encoding]::new($false))
    $drift = & $stager -Action Status -TargetWin64Directory $target -CandidateRoot $candidate -PredecessorPackRoot $predecessor -BackupRoot $backups -ExpectedPredecessorWrapperSha256 $wrapperHash
    if ($drift.Status -ne 'drifted') { throw 'Staged drift was not detected.' }
    $restoreRejected = $false
    try { & $stager -Action Restore -TargetWin64Directory $target -CandidateRoot $candidate -PredecessorPackRoot $predecessor -BackupRoot $backups -ExpectedPredecessorWrapperSha256 $wrapperHash -Confirm:$false | Out-Null } catch { $restoreRejected = $_.Exception.Message -match 'drifted' }
    if (-not $restoreRejected) { throw 'Restore did not reject a drifted staged file.' }
    [IO.File]::Copy((Join-Path $candidate 'Mods\Agent2R3DSSGITraceE2AA_ps.hlsl'),$trace,$true)

    $restored = & $stager -Action Restore -TargetWin64Directory $target -CandidateRoot $candidate -PredecessorPackRoot $predecessor -BackupRoot $backups -ExpectedPredecessorWrapperSha256 $wrapperHash -Confirm:$false
    if ($restored.Status -ne 'restored' -or $restored.Files -ne 10) { throw 'Restore result is incomplete.' }
    Assert-Tree $before (Get-Tree $target) 'Restored predecessor'
    Write-Output 'PASS: temporal live candidate stages ten exact files, detects drift, refuses unsafe restore, and restores the complete predecessor byte-for-byte without touching the game.'
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) { [IO.Directory]::Delete($testRoot,$true) }
}
