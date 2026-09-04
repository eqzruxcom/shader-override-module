[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][string]$GameRoot,
    [Parameter(Mandatory)][string]$SnapshotDirectory,
    [switch]$AllowExternalGameRoot,
    [switch]$AllowExternalSnapshot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$game = [IO.Path]::GetFullPath($GameRoot).TrimEnd('\')
$snapshot = [IO.Path]::GetFullPath($SnapshotDirectory).TrimEnd('\')
$allowedBackupRoot = [IO.Path]::GetFullPath('F:\Shader3Dmigoto\Backups').TrimEnd('\')

if (-not (Test-Path -LiteralPath $game -PathType Container)) { throw "Game root is missing: $game" }
if (-not $game.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    if (-not $AllowExternalGameRoot) { throw "External game root requires -AllowExternalGameRoot: $game" }
    if (-not $game.EndsWith('\End\Binaries\Win64', [StringComparison]::OrdinalIgnoreCase)) {
        throw "External game root must be the exact FF7 Remake Win64 directory: $game"
    }
}
if (-not $snapshot.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    if (-not $AllowExternalSnapshot) { throw "External snapshot requires -AllowExternalSnapshot: $snapshot" }
    if (-not $snapshot.StartsWith($allowedBackupRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "External snapshot must remain under $allowedBackupRoot"
    }
}

$verified = & (Join-Path $PSScriptRoot 'Assert-IntergradeDxvkLiveTestBackup.ps1') `
    -SnapshotDirectory $snapshot -AllowExternalSnapshot:$AllowExternalSnapshot
if ($verified.Valid -ne $true -or $verified.DxvkInstalled -ne $false -or $verified.GameFilesModified -ne $false) {
    throw 'Preinstall snapshot failed the immutable backup contract.'
}

$manifestPath = Join-Path $snapshot 'preinstall-backup.json'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if (-not $game.Equals([IO.Path]::GetFullPath([string]$manifest.gameRoot).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
    throw "Snapshot belongs to a different game root: $($manifest.gameRoot)"
}
$exe = Join-Path $game ([string]$manifest.gameExecutable.relativePath)
if (-not (Test-Path -LiteralPath $exe -PathType Leaf) -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash -ne [string]$manifest.gameExecutable.sha256) {
    throw 'Current game executable does not match the snapshot fingerprint.'
}

$bundleManifestPath = Join-Path $snapshot 'provenance\runtime-bundle.json'
$rollbackPlanPath = Join-Path $snapshot 'provenance\rollback-plan.json'
$bundleManifest = Get-Content -Raw -LiteralPath $bundleManifestPath | ConvertFrom-Json
$rollbackPlan = Get-Content -Raw -LiteralPath $rollbackPlanPath | ConvertFrom-Json
if ($bundleManifest.packageId -ne $manifest.packageId -or $rollbackPlan.packageId -ne $manifest.packageId -or
    $rollbackPlan.restoreBackedUpFiles -ne $true -or $rollbackPlan.removePackageCreatedFiles -ne $true -or
    $rollbackPlan.verifyRestoredHashes -ne $true) {
    throw 'Copied bundle provenance does not authorize the required rollback behavior.'
}

function Resolve-UnderRoot([string]$Root, [string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or
        $Relative -match '(^|[\\/])\.\.([\\/]|$)') { throw "Unsafe relative path: $Relative" }
    $full = [IO.Path]::GetFullPath((Join-Path $Root $Relative.Replace('/','\')))
    if (-not $full.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes root: $Relative"
    }
    $full
}

$targets = @($manifest.installTargets)
$planned = @($rollbackPlan.exactTargetRelativePaths | ForEach-Object { [string]$_ })
if ($targets.Count -ne 8 -or $planned.Count -ne 8 -or
    @(Compare-Object ($targets.relativePath | Sort-Object) ($planned | Sort-Object)).Count -ne 0) {
    throw 'Snapshot and rollback plan do not identify the same eight exact targets.'
}

$packageHashes = @{}
foreach ($entry in @($bundleManifest.files)) {
    $relative = [string]$entry.relativePath
    if ($planned -contains $relative) { $packageHashes[$relative.ToLowerInvariant()] = ([string]$entry.sha256).ToUpperInvariant() }
}
if ($packageHashes.Count -ne 8) { throw 'Runtime bundle does not publish hashes for all eight rollback targets.' }

$actions = [Collections.Generic.List[object]]::new()
foreach ($entry in $targets) {
    $relative = [string]$entry.relativePath
    $destination = Resolve-UnderRoot -Root $game -Relative $relative
    $packageHash = [string]$packageHashes[$relative.ToLowerInvariant()]
    $existsNow = Test-Path -LiteralPath $destination -PathType Leaf
    $currentHash = if ($existsNow) { (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash } else { $null }

    if ($entry.existedBefore -eq $true) {
        $originalHash = ([string]$entry.sha256).ToUpperInvariant()
        if (-not $existsNow) { throw "Originally existing target is unexpectedly missing: $relative" }
        if ($currentHash -ne $originalHash -and $currentHash -ne $packageHash) {
            throw "Refusing to overwrite drifted target during rollback: $relative ($currentHash)"
        }
        $actions.Add([pscustomobject]@{
            RelativePath=$relative
            Action=if ($currentHash -eq $originalHash) { 'already-restored' } else { 'restore-backup' }
            Destination=$destination
            Backup=Resolve-UnderRoot -Root $snapshot -Relative ([string]$entry.backupPath)
            ExpectedAfter=$originalHash
        })
    } else {
        if ($existsNow -and $currentHash -ne $packageHash) {
            throw "Refusing to delete non-package file during rollback: $relative ($currentHash)"
        }
        $actions.Add([pscustomobject]@{
            RelativePath=$relative
            Action=if ($existsNow) { 'remove-package-file' } else { 'already-absent' }
            Destination=$destination
            Backup=$null
            ExpectedAfter=$null
        })
    }
}

$changes = @($actions | Where-Object Action -in @('restore-backup','remove-package-file'))
if ($changes.Count -eq 0) {
    [pscustomobject]@{ Status='already-restored'; Snapshot=$snapshot; ChangedFiles=0; VerifiedTargets=8 }
    return
}
if (-not $PSCmdlet.ShouldProcess($game, "Restore native D3D11 state from verified snapshot $snapshot")) {
    $actions
    return
}

foreach ($action in $changes) {
    if ($action.Action -eq 'restore-backup') {
        [IO.File]::Copy([string]$action.Backup, [string]$action.Destination, $true)
    } elseif ($action.Action -eq 'remove-package-file') {
        Remove-Item -LiteralPath ([string]$action.Destination) -Force
    }
}

foreach ($action in $actions) {
    if ($null -eq $action.ExpectedAfter) {
        if (Test-Path -LiteralPath ([string]$action.Destination)) { throw "Rollback failed to remove: $($action.RelativePath)" }
    } else {
        if (-not (Test-Path -LiteralPath ([string]$action.Destination) -PathType Leaf) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath ([string]$action.Destination)).Hash -ne [string]$action.ExpectedAfter) {
            throw "Rollback verification failed: $($action.RelativePath)"
        }
    }
}

$receipt = [ordered]@{
    schemaVersion=1
    kind='ff7-remake-dxvk-rollback-receipt'
    completedUtc=[DateTime]::UtcNow.ToString('o')
    packageId=[string]$manifest.packageId
    gameRoot=$game
    snapshot=$snapshot
    changedFiles=$changes.Count
    verifiedTargets=8
    result='native-state-restored'
}
$receiptPath = Join-Path $snapshot ('rollback-receipt-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.json')
[IO.File]::WriteAllText($receiptPath, (($receipt | ConvertTo-Json -Depth 5) + "`r`n"), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Status='restored'
    Snapshot=$snapshot
    Receipt=$receiptPath
    ChangedFiles=$changes.Count
    VerifiedTargets=8
}
