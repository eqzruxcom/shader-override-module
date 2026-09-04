[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][string]$GameRoot,
    [Parameter(Mandatory)][string]$BundleDirectory,
    [Parameter(Mandatory)][string]$SnapshotDirectory,
    [switch]$AllowExternalGameRoot,
    [switch]$AllowExternalSnapshot,
    [Parameter(Mandatory)][switch]$AcknowledgeReplaces3DMigotoD3D11
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$game = [IO.Path]::GetFullPath($GameRoot).TrimEnd('\')
$bundle = [IO.Path]::GetFullPath($BundleDirectory).TrimEnd('\')
$snapshot = [IO.Path]::GetFullPath($SnapshotDirectory).TrimEnd('\')
$allowedBackupRoot = [IO.Path]::GetFullPath('F:\Shader3Dmigoto\Backups').TrimEnd('\')

if (-not (Test-Path -LiteralPath $game -PathType Container)) { throw "Game root is missing: $game" }
if (-not $game.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    if (-not $AllowExternalGameRoot) { throw "External game root requires -AllowExternalGameRoot: $game" }
    if (-not $game.EndsWith('\End\Binaries\Win64', [StringComparison]::OrdinalIgnoreCase)) {
        throw "External game root must be the exact FF7 Remake Win64 directory: $game"
    }
}
if (-not $bundle.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Runtime bundle must remain inside the workspace: $bundle"
}
if (-not $snapshot.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    if (-not $AllowExternalSnapshot) { throw "External snapshot requires -AllowExternalSnapshot: $snapshot" }
    if (-not $snapshot.StartsWith($allowedBackupRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "External snapshot must remain under $allowedBackupRoot"
    }
}
if (-not $AcknowledgeReplaces3DMigotoD3D11) {
    throw 'Explicit acknowledgement is required because this test replaces the game d3d11.dll provider and therefore does not run beside 3DMigoto.'
}

$running = @(Get-Process -Name 'ff7remake_' -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    throw "FF7 Remake is running (PID $($running[0].Id)); live DXVK installation is forbidden until the process exits."
}

$bundleStatus = & (Join-Path $PSScriptRoot 'Assert-DxvkD3D11RuntimeBundle.ps1') -BundleDirectory $bundle
if ($bundleStatus.Valid -ne $true -or $bundleStatus.ReplacementCount -ne 5 -or
    $bundleStatus.Installed -ne $false -or $bundleStatus.RuntimeEligible -ne $false) {
    throw 'DXVK runtime bundle failed its reviewed offline contract.'
}
$backupStatus = & (Join-Path $PSScriptRoot 'Assert-IntergradeDxvkLiveTestBackup.ps1') `
    -SnapshotDirectory $snapshot -AllowExternalSnapshot:$AllowExternalSnapshot
if ($backupStatus.Valid -ne $true -or $backupStatus.DxvkInstalled -ne $false -or
    $backupStatus.GameFilesModified -ne $false) {
    throw 'Preinstall snapshot failed its immutable backup contract.'
}

$bundleManifestPath = Join-Path $bundle 'runtime-bundle.json'
$bundleRollbackPath = Join-Path $bundle 'rollback-plan.json'
$bundleManifest = Get-Content -Raw -LiteralPath $bundleManifestPath | ConvertFrom-Json
$rollbackPlan = Get-Content -Raw -LiteralPath $bundleRollbackPath | ConvertFrom-Json
$snapshotManifestPath = Join-Path $snapshot 'preinstall-backup.json'
$snapshotManifest = Get-Content -Raw -LiteralPath $snapshotManifestPath | ConvertFrom-Json

if ($bundleManifest.packageId -ne $snapshotManifest.packageId -or
    $rollbackPlan.packageId -ne $snapshotManifest.packageId) {
    throw 'Bundle and preinstall snapshot package IDs do not match.'
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $bundleManifestPath).Hash -ne
        [string]$snapshotManifest.bundleManifestSha256 -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $bundleRollbackPath).Hash -ne
        [string]$snapshotManifest.rollbackPlanSha256) {
    throw 'The selected bundle does not match the bundle preserved by the preinstall snapshot.'
}
if (-not $game.Equals([IO.Path]::GetFullPath([string]$snapshotManifest.gameRoot).TrimEnd('\'),
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Snapshot belongs to a different game root: $($snapshotManifest.gameRoot)"
}
$exe = Join-Path $game ([string]$snapshotManifest.gameExecutable.relativePath)
if (-not (Test-Path -LiteralPath $exe -PathType Leaf) -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash -ne [string]$snapshotManifest.gameExecutable.sha256) {
    throw 'Current game executable does not match the reviewed adapter and snapshot fingerprint.'
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

$targets = @($snapshotManifest.installTargets)
$planned = @($rollbackPlan.exactTargetRelativePaths | ForEach-Object { [string]$_ })
if ($targets.Count -ne 8 -or $planned.Count -ne 8 -or
    @(Compare-Object ($targets.relativePath | Sort-Object) ($planned | Sort-Object)).Count -ne 0) {
    throw 'Snapshot and bundle do not identify the same eight exact install targets.'
}

$bundleFiles = @{}
foreach ($entry in @($bundleManifest.files)) {
    $relative = [string]$entry.relativePath
    if ($planned -contains $relative) { $bundleFiles[$relative.ToLowerInvariant()] = $entry }
}
if ($bundleFiles.Count -ne 8) { throw 'Bundle does not publish all eight exact install targets.' }

# Installation is allowed only from the exact native state captured by this snapshot.
foreach ($entry in $targets) {
    $relative = [string]$entry.relativePath
    $destination = Resolve-UnderRoot -Root $game -Relative $relative
    $existsNow = Test-Path -LiteralPath $destination -PathType Leaf
    if ($entry.existedBefore -eq $true) {
        if (-not $existsNow -or (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash -ne [string]$entry.sha256) {
            throw "Native install target drifted since backup: $relative"
        }
    } elseif ($existsNow) {
        throw "Package-created target already exists; restore or investigate before install: $relative"
    }
}

# Preserve 3DMigoto configuration and accepted contact-shadow evidence exactly.
foreach ($entry in @($snapshotManifest.nativeComparisonContext)) {
    $livePath = Resolve-UnderRoot -Root $game -Relative ([string]$entry.relativePath)
    if (-not (Test-Path -LiteralPath $livePath -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $livePath).Hash -ne [string]$entry.sha256) {
        throw "Native comparison context drifted since backup: $($entry.relativePath)"
    }
}

$copyPlan = [Collections.Generic.List[object]]::new()
foreach ($relative in $planned) {
    $source = Resolve-UnderRoot -Root $bundle -Relative $relative
    $destination = Resolve-UnderRoot -Root $game -Relative $relative
    $record = $bundleFiles[$relative.ToLowerInvariant()]
    if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash -ne [string]$record.sha256 -or
        (Get-Item -LiteralPath $source).Length -ne [long]$record.sizeBytes) {
        throw "Bundle source failed hash/size verification: $relative"
    }
    $copyPlan.Add([pscustomobject]@{
        RelativePath=$relative
        Source=$source
        Destination=$destination
        Sha256=([string]$record.sha256).ToUpperInvariant()
        SizeBytes=[long]$record.sizeBytes
    })
}

if (-not $PSCmdlet.ShouldProcess($game, "Install reviewed DXVK D3D11 test package $($bundleManifest.packageId)")) {
    $copyPlan
    return
}

$stage = Join-Path $game ('.codex-dxvk-stage-' + [Guid]::NewGuid().ToString('N'))
$stageFull = [IO.Path]::GetFullPath($stage).TrimEnd('\')
if (-not $stageFull.StartsWith($game + '\.codex-dxvk-stage-', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe staging directory: $stageFull"
}
$finalWritesStarted = $false
try {
    [IO.Directory]::CreateDirectory($stageFull) | Out-Null
    foreach ($item in $copyPlan) {
        $staged = Resolve-UnderRoot -Root $stageFull -Relative ([string]$item.RelativePath)
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($staged)) | Out-Null
        [IO.File]::Copy([string]$item.Source, $staged, $false)
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $staged).Hash -ne [string]$item.Sha256) {
            throw "Staged payload hash mismatch: $($item.RelativePath)"
        }
    }

    $finalWritesStarted = $true
    foreach ($item in $copyPlan) {
        $staged = Resolve-UnderRoot -Root $stageFull -Relative ([string]$item.RelativePath)
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([string]$item.Destination)) | Out-Null
        [IO.File]::Copy($staged, [string]$item.Destination, $true)
    }
    foreach ($item in $copyPlan) {
        if (-not (Test-Path -LiteralPath ([string]$item.Destination) -PathType Leaf) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath ([string]$item.Destination)).Hash -ne [string]$item.Sha256 -or
            (Get-Item -LiteralPath ([string]$item.Destination)).Length -ne [long]$item.SizeBytes) {
            throw "Installed payload failed hash/size verification: $($item.RelativePath)"
        }
    }
} catch {
    $failure = $_
    if ($finalWritesStarted) {
        & (Join-Path $PSScriptRoot 'Restore-IntergradeDxvkLiveTest.ps1') `
            -GameRoot $game -SnapshotDirectory $snapshot `
            -AllowExternalGameRoot:$AllowExternalGameRoot -AllowExternalSnapshot:$AllowExternalSnapshot -Confirm:$false | Out-Null
    }
    throw $failure
} finally {
    if (Test-Path -LiteralPath $stageFull -PathType Container) {
        $resolvedStage = [IO.Path]::GetFullPath($stageFull).TrimEnd('\')
        if (-not $resolvedStage.StartsWith($game + '\.codex-dxvk-stage-', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing unsafe staging cleanup: $resolvedStage"
        }
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}

$receipt = [ordered]@{
    schemaVersion=1
    kind='ff7-remake-dxvk-install-receipt'
    installedUtc=[DateTime]::UtcNow.ToString('o')
    packageId=[string]$bundleManifest.packageId
    gameRoot=$game
    snapshot=$snapshot
    replaces3DMigotoD3D11=$true
    installedTargets=@($copyPlan | ForEach-Object {
        [ordered]@{relativePath=$_.RelativePath;sha256=$_.Sha256;sizeBytes=$_.SizeBytes}
    })
    rollbackTool=(Join-Path $PSScriptRoot 'Restore-IntergradeDxvkLiveTest.ps1')
    result='installed-and-hash-verified'
}
$receiptPath = Join-Path $snapshot ('install-receipt-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.json')
[IO.File]::WriteAllText($receiptPath, (($receipt | ConvertTo-Json -Depth 7) + "`r`n"), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Status='installed'
    PackageId=[string]$bundleManifest.packageId
    Receipt=$receiptPath
    InstalledTargets=$copyPlan.Count
    Replaces3DMigotoD3D11=$true
    RequiresFullGameRestart=$true
}
