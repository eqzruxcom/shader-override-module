[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SnapshotDirectory,
    [switch]$AllowExternalSnapshot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$snapshot = [IO.Path]::GetFullPath($SnapshotDirectory).TrimEnd('\')
$allowedExternalRoot = [IO.Path]::GetFullPath('F:\Shader3Dmigoto\Backups').TrimEnd('\')

if (-not (Test-Path -LiteralPath $snapshot -PathType Container)) {
    throw "Snapshot directory is missing: $snapshot"
}
if (-not $snapshot.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    if (-not $AllowExternalSnapshot) { throw "External snapshot requires -AllowExternalSnapshot: $snapshot" }
    if (-not $snapshot.StartsWith($allowedExternalRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "External snapshot must remain under $allowedExternalRoot"
    }
}

$manifestPath = Join-Path $snapshot 'preinstall-backup.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Backup manifest is missing: $manifestPath"
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.kind -ne 'ff7-remake-dxvk-preinstall-backup' -or
    $manifest.complete -ne $true -or $manifest.policy.dxvkInstalled -ne $false -or
    $manifest.policy.gameFilesModified -ne $false -or $manifest.policy.restoreBeforeDelete -ne $true -or
    $manifest.policy.verifyHashes -ne $true) {
    throw 'Backup manifest contract is invalid.'
}

function Resolve-SnapshotPath([string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or
        $Relative -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Unsafe backup path: $Relative"
    }
    $full = [IO.Path]::GetFullPath((Join-Path $snapshot $Relative.Replace('/','\')))
    if (-not $full.StartsWith($snapshot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Backup path escapes snapshot: $Relative"
    }
    $full
}

$targets = @($manifest.installTargets)
if ($targets.Count -ne 8 -or @($targets.relativePath | Select-Object -Unique).Count -ne 8) {
    throw "Expected exactly eight unique install targets, found $($targets.Count)."
}
$existing = 0
$absent = 0
foreach ($entry in $targets) {
    if ($entry.existedBefore -eq $true) {
        $existing++
        $path = Resolve-SnapshotPath ([string]$entry.backupPath)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Backed-up target is missing: $($entry.relativePath)" }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$entry.sha256 -or
            (Get-Item -LiteralPath $path).Length -ne [long]$entry.sizeBytes) {
            throw "Backed-up target failed hash/size verification: $($entry.relativePath)"
        }
    } else {
        $absent++
        if ($null -ne $entry.backupPath -or $null -ne $entry.sha256 -or $null -ne $entry.sizeBytes) {
            throw "Absent target incorrectly claims backup data: $($entry.relativePath)"
        }
    }
}

$context = @($manifest.nativeComparisonContext)
if ($context.Count -ne 7 -or @($context.relativePath | Select-Object -Unique).Count -ne 7) {
    throw "Expected exactly seven unique native-context files, found $($context.Count)."
}
foreach ($entry in $context) {
    $path = Resolve-SnapshotPath ([string]$entry.backupPath)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Native-context backup is missing: $($entry.relativePath)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$entry.sha256 -or
        (Get-Item -LiteralPath $path).Length -ne [long]$entry.sizeBytes) {
        throw "Native-context backup failed hash/size verification: $($entry.relativePath)"
    }
}

$bundleManifest = Resolve-SnapshotPath 'provenance/runtime-bundle.json'
$rollbackPlan = Resolve-SnapshotPath 'provenance/rollback-plan.json'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $bundleManifest).Hash -ne [string]$manifest.bundleManifestSha256) {
    throw 'Copied runtime-bundle manifest failed hash verification.'
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $rollbackPlan).Hash -ne [string]$manifest.rollbackPlanSha256) {
    throw 'Copied rollback plan failed hash verification.'
}

[pscustomobject]@{
    Valid=$true
    Snapshot=$snapshot
    PackageId=[string]$manifest.packageId
    InstallTargets=$targets.Count
    ExistingTargets=$existing
    AbsentTargets=$absent
    ContextFiles=$context.Count
    DxvkInstalled=$false
    GameFilesModified=$false
}
