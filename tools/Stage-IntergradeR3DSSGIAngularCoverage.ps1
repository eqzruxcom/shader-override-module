[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][ValidateSet('Stage','Status','Restore')][string]$Action,
    [Parameter(Mandatory)][string]$TargetWin64Directory,
    [string]$CandidateRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-angular-coverage-live-candidate-v1'),
    [string]$PredecessorCandidateRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-temporal-live-candidate-static-reprojection-v2'),
    [string]$BackupRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-angular-live-stage-backups'),
    [switch]$AllowExternalTarget,
    [switch]$AcknowledgeOfflineCandidate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$target = [IO.Path]::GetFullPath($TargetWin64Directory).TrimEnd('\')
$candidate = [IO.Path]::GetFullPath($CandidateRoot).TrimEnd('\')
$predecessor = [IO.Path]::GetFullPath($PredecessorCandidateRoot).TrimEnd('\')
$backup = [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')
$external = -not $target.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase)
$approvedExternalBackupRoot = [IO.Path]::GetFullPath('F:\Shader3Dmigoto\Backups').TrimEnd('\')
$backupInWorkspace = $backup.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase)
$backupOnApprovedDrive = $backup.StartsWith($approvedExternalBackupRoot + '\',[StringComparison]::OrdinalIgnoreCase)
$utf8 = [Text.UTF8Encoding]::new($false)

function Get-Hash([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash }
function Write-Json([string]$Path,[object]$Value) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path)))
    [IO.File]::WriteAllText($Path,($Value | ConvertTo-Json -Depth 16) + [Environment]::NewLine,$utf8)
}
function Test-Phase([object[]]$Records,[string]$Phase) {
    foreach ($record in $Records) {
        $wanted = $record.$Phase
        $exists = Test-Path -LiteralPath $record.destination -PathType Leaf
        if ([bool]$wanted.existed) {
            if (-not $exists -or (Get-Hash $record.destination) -ne [string]$wanted.sha256) { return $false }
        } elseif ($exists) { return $false }
    }
    return $true
}

if ($external) {
    if (-not $AllowExternalTarget) { throw "External target requires -AllowExternalTarget: $target" }
    if (-not $target.EndsWith('\End\Binaries\Win64',[StringComparison]::OrdinalIgnoreCase)) { throw 'External target must be an exact FF7 Remake End\Binaries\Win64 directory.' }
}
foreach ($item in @(@($candidate,'CandidateRoot'),@($predecessor,'PredecessorCandidateRoot'))) {
    if (-not $item[0].StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "$($item[1]) must remain inside the workspace." }
}
if (-not $backupInWorkspace -and -not $backupOnApprovedDrive) { throw 'BackupRoot must remain inside the workspace or under F:\Shader3Dmigoto\Backups.' }
if ($external -and -not $backupOnApprovedDrive) { throw 'A real-game stage or restore requires BackupRoot under F:\Shader3Dmigoto\Backups.' }
foreach ($directory in @($target,(Join-Path $target 'Mods'),(Join-Path $target 'ShaderFixes'))) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Required target directory is missing: $directory" }
}

$manifestPath = Join-Path $candidate 'manifest.json'
$predecessorManifestPath = Join-Path $predecessor 'manifest.json'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$predecessorManifest = Get-Content -Raw -LiteralPath $predecessorManifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.packageId -ne 'agent2-r3d-ssgi-angular-coverage-live-v1' -or
    $manifest.result -ne 'pass' -or $manifest.kind -ne 'controlled-live-candidate' -or
    -not [bool]$manifest.runtimeEligible -or [bool]$manifest.installed -or [bool]$manifest.liveTestsPerformed -or
    -not [bool]$manifest.validation.angularPackGatePassed -or -not [bool]$manifest.validation.wrapperBuiltReleaseX64 -or
    $manifest.controls.F10 -ne 'native reload, unchanged' -or $manifest.controls.PageDown -ne 'graduated master, unchanged') {
    throw 'Angular live candidate manifest failed its closed contract.'
}
if ($predecessorManifest.schemaVersion -ne 1 -or $predecessorManifest.packageId -ne [string]$manifest.predecessor.packageId -or
    $predecessorManifest.result -ne 'pass' -or $predecessorManifest.kind -ne 'controlled-live-candidate' -or
    (Get-Hash $predecessorManifestPath) -ne [string]$manifest.predecessor.manifestSha256) {
    throw 'Temporal predecessor candidate is missing or drifted.'
}

$candidateMap = @{}
foreach ($entry in @($manifest.files)) {
    $relative = ([string]$entry.relativePath).Replace('/','\')
    $source = Join-Path $candidate $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or (Get-Hash $source) -ne [string]$entry.sha256) { throw "Candidate payload drifted: $relative" }
    $candidateMap[$relative] = [ordered]@{source=$source;sha256=[string]$entry.sha256}
}
$expectedNames = @(
    'Agent2R3DSSGICompositeE2AA_ps.hlsl','Agent2R3DSSGIDenoise16_ps.hlsl','Agent2R3DSSGIDenoise2_ps.hlsl',
    'Agent2R3DSSGIDenoise4_ps.hlsl','Agent2R3DSSGIDenoise8_ps.hlsl','Agent2R3DSSGIFullscreen_vs.hlsl',
    'Agent2R3DSSGITest.ini','Agent2R3DSSGITemporalHistory_ps.hlsl','Agent2R3DSSGITrace16E2AA_ps.hlsl',
    'Agent2R3DSSGITrace8E2AA_ps.hlsl','Agent2R3DSSGITraceE2AA_ps.hlsl'
)
$expectedCandidatePaths = @('Runtime\d3d11.dll') + @($expectedNames | ForEach-Object { 'Mods\' + $_ })
if ((@($candidateMap.Keys | Sort-Object) -join '|') -cne (@($expectedCandidatePaths | Sort-Object) -join '|')) { throw 'Angular candidate inventory changed.' }

$predecessorMap = @{}
foreach ($entry in @($predecessorManifest.files)) {
    $relative = ([string]$entry.relativePath).Replace('/','\')
    $path = Join-Path $predecessor $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Hash $path) -ne [string]$entry.sha256) { throw "Predecessor payload drifted: $relative" }
    $predecessorMap[$relative] = [string]$entry.sha256
}
if ($predecessorMap.Count -ne [int]$manifest.predecessor.payloadFileCount -or $predecessorMap.Count -ne 10) { throw 'Temporal predecessor inventory changed.' }
if ($predecessorMap['Runtime\d3d11.dll'] -ne [string]$manifest.predecessor.wrapperSha256) { throw 'Pinned predecessor wrapper hash changed.' }
if ($candidateMap['Runtime\d3d11.dll'].sha256 -ne $predecessorMap['Runtime\d3d11.dll']) { throw 'Candidate wrapper is not byte-identical to the temporal predecessor.' }

$mods = Join-Path $target 'Mods'
$statePath = Join-Path $backup 'active-state.json'
if ($Action -eq 'Status') {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { [pscustomobject]@{Status='not-staged';Installed=$false;Target=$target;State=$statePath}; return }
    $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    if ($state.packageId -ne [string]$manifest.packageId -or -not [string]::Equals([string]$state.target,$target,[StringComparison]::OrdinalIgnoreCase)) { throw 'State belongs to another package or target.' }
    $status = if ($state.status -eq 'staged' -and (Test-Phase @($state.files) 'after')) {'staged'} elseif ($state.status -eq 'restored' -and (Test-Phase @($state.files) 'before')) {'restored'} else {'drifted'}
    [pscustomobject]@{Status=$status;Installed=($status -eq 'staged');Target=$target;State=$statePath;Files=@($state.files).Count}; return
}

if ($external) {
    if ($null -ne (Get-Process -Name 'ff7remake_' -ErrorAction SilentlyContinue)) { throw 'FF7 Remake must be closed before replacing or restoring loaded files.' }
    $exe = Join-Path $target 'ff7remake_.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf) -or (Get-Hash $exe) -ne [string]$manifest.executable.sha256) { throw 'FF7 Remake executable fingerprint changed.' }
    $contact = Join-Path $mods 'ContactShadows.ini'
    if (-not (Test-Path -LiteralPath $contact -PathType Leaf) -or (Get-Hash $contact) -ne 'F86A81DEE319C6A6E98933D4AC99C0477B6E5D8B43E6F7D29272FDDA476B5478') { throw 'Accepted automatic contact-shadow family drifted.' }
}

if ($Action -eq 'Stage') {
    if (-not $AcknowledgeOfflineCandidate) { throw 'Stage requires -AcknowledgeOfflineCandidate because angular behavior remains live-unproven.' }
    if (Test-Path -LiteralPath $statePath) { throw "A staging state already exists: $statePath" }
    foreach ($relative in $predecessorMap.Keys) {
        $destinationRelative = if ($relative -eq 'Runtime\d3d11.dll') {'d3d11.dll'} else {$relative}
        $path = Join-Path $target $destinationRelative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Hash $path) -ne $predecessorMap[$relative]) { throw "Live temporal predecessor drifted: $destinationRelative" }
    }
    foreach ($name in @('Agent2R3DSSGITrace8E2AA_ps.hlsl','Agent2R3DSSGITrace16E2AA_ps.hlsl')) {
        if (Test-Path -LiteralPath (Join-Path $mods $name)) { throw "New angular trace unexpectedly already exists: $name" }
    }
    if (Test-Path -LiteralPath (Join-Path $target 'ShaderFixes\af6cd28a0108a18a-ps.txt')) { throw 'Late-scene af6 replacement must remain quarantined.' }
    if (-not $PSCmdlet.ShouldProcess($target,'Stage angular-coverage diagnostic with exact rollback')) { return }
    [void][IO.Directory]::CreateDirectory($backup)
    $snapshot = Join-Path $backup (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
    [void][IO.Directory]::CreateDirectory($snapshot)
    $records = [Collections.Generic.List[object]]::new()
    foreach ($relative in $expectedCandidatePaths) {
        $destinationRelative = if ($relative -eq 'Runtime\d3d11.dll') {'d3d11.dll'} else {$relative}
        $destination = Join-Path $target $destinationRelative
        $hadOriginal = Test-Path -LiteralPath $destination -PathType Leaf
        $backupPath = if ($hadOriginal) { Join-Path $snapshot (($destinationRelative -replace '[\\/]','__') + '.before') } else { $null }
        if ($hadOriginal) { [IO.File]::Copy($destination,$backupPath,$false) }
        $records.Add([ordered]@{
            relativePath=$destinationRelative.Replace('\','/');destination=$destination;source=$candidateMap[$relative].source
            before=[ordered]@{existed=$hadOriginal;sha256=if($hadOriginal){Get-Hash $destination}else{$null};backup=$backupPath}
            after=[ordered]@{existed=$true;sha256=$candidateMap[$relative].sha256}
        })
    }
    $state = [ordered]@{schemaVersion=1;packageId=[string]$manifest.packageId;status='staging';target=$target;snapshot=$snapshot;candidateManifest=$manifestPath;files=@($records)}
    Write-Json $statePath $state
    try {
        foreach ($record in $records) { [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($record.destination)); [IO.File]::Copy($record.source,$record.destination,$true) }
        if (-not (Test-Phase @($records) 'after')) { throw 'Post-stage payload verification failed.' }
        $state.status = 'staged'; Write-Json $statePath $state
    } catch {
        $failure = $_
        foreach ($record in $records) { if ([bool]$record.before.existed) {[IO.File]::Copy($record.before.backup,$record.destination,$true)} elseif (Test-Path -LiteralPath $record.destination) {[IO.File]::Delete($record.destination)} }
        $state.status = if (Test-Phase @($records) 'before') {'automatic-rollback-after-stage-failure'} else {'automatic-rollback-incomplete'}
        Write-Json $statePath $state
        if ($state.status -eq 'automatic-rollback-incomplete') { throw "Stage failed and rollback was incomplete: $statePath" }
        throw $failure
    }
    [pscustomobject]@{Status='staged';Installed=$true;Files=$records.Count;ReloadRequired=$false;RelaunchRequired=$true;State=$statePath}; return
}

if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw "No staging state exists: $statePath" }
$state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
if ($state.packageId -ne [string]$manifest.packageId -or $state.status -ne 'staged' -or -not [string]::Equals([string]$state.target,$target,[StringComparison]::OrdinalIgnoreCase)) { throw 'Only this package exact staged state can be restored.' }
if (-not (Test-Phase @($state.files) 'after')) { throw 'Restore refused because staged files drifted.' }
foreach ($record in @($state.files | Where-Object { [bool]$_.before.existed })) {
    if (-not (Test-Path -LiteralPath $record.before.backup -PathType Leaf) -or (Get-Hash $record.before.backup) -ne [string]$record.before.sha256) { throw "Restore backup drifted: $($record.relativePath)" }
}
if (-not $PSCmdlet.ShouldProcess($target,'Restore exact temporal predecessor')) { return }
foreach ($record in @($state.files)) {
    if ([bool]$record.before.existed) { [IO.File]::Copy($record.before.backup,$record.destination,$true) }
    elseif (Test-Path -LiteralPath $record.destination -PathType Leaf) { [IO.File]::Delete($record.destination) }
}
if (-not (Test-Phase @($state.files) 'before')) { throw 'Post-restore verification failed.' }
$state.status = 'restored'
$state | Add-Member -NotePropertyName restoredAtUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
Write-Json $statePath $state
[pscustomobject]@{Status='restored';Installed=$false;Files=@($state.files).Count;RelaunchRequired=$true;State=$statePath}
