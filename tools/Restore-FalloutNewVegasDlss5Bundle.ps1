[CmdletBinding()]
param([Parameter(Mandatory)][string] $ReceiptPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$receiptFull = (Resolve-Path -LiteralPath $ReceiptPath).Path
if (-not $receiptFull.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing a New Vegas restore receipt outside workspace artifacts: $receiptFull"
}

function Get-Sha256Upper {
    param([string] $Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Resolve-ContainedPath {
    param([string] $Root, [string] $Relative, [string] $Description)
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Unsafe $Description path in restore receipt: $Relative"
    }
    $candidate = [IO.Path]::GetFullPath((Join-Path $Root $Relative.Replace('/', '\')))
    if (-not $candidate.StartsWith($Root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description escapes its allowed root: $Relative"
    }
    return $candidate
}

$receiptRoot = Split-Path -Parent $receiptFull
$receipt = Get-Content -Raw -LiteralPath $receiptFull | ConvertFrom-Json
$validInstallKinds = @('fallout-new-vegas-dlss5-transport-install', 'fallout-new-vegas-dlss5-full-install')
if ($receipt.schemaVersion -ne 1 -or [string]$receipt.kind -notin $validInstallKinds -or $receipt.installed -ne $true -or $receipt.restored -ne $false) {
    throw 'Receipt does not identify an active New Vegas DLSS5 install.'
}
$gameRoot = [IO.Path]::GetFullPath([string]$receipt.gameRoot).TrimEnd('\')
if ([string]$receipt.gameExecutable -ne 'FalloutNV.exe') { throw 'Restore receipt has an unexpected game executable.' }
$gameExe = Join-Path $gameRoot 'FalloutNV.exe'
if (-not (Test-Path -LiteralPath $gameExe -PathType Leaf)) { throw "Receipt game root no longer contains FalloutNV.exe: $gameRoot" }
if ((Get-Sha256Upper $gameExe) -ne ([string]$receipt.gameExecutableSha256).ToUpperInvariant()) { throw 'FalloutNV.exe changed since installation; refusing restore.' }
if (Get-Process -Name 'FalloutNV' -ErrorAction SilentlyContinue) { throw 'FalloutNV.exe is running. Close the game before restoring files.' }

# Preflight every target before changing any one of them.
foreach ($record in @($receipt.targets)) {
    $relative = [string]$record.relativePath
    $target = Resolve-ContainedPath $gameRoot $relative 'target'
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Installed target is missing; refusing partial restore: $relative" }
    if ((Get-Sha256Upper $target) -ne ([string]$record.packageSha256).ToUpperInvariant()) {
        throw "Installed target drifted; refusing partial restore: $relative"
    }
    if ($record.existedBefore) {
        $backup = Resolve-ContainedPath $receiptRoot ([string]$record.backupRelativePath) 'backup'
        if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { throw "Backup is missing: $relative" }
        if ((Get-Sha256Upper $backup) -ne ([string]$record.originalSha256).ToUpperInvariant()) { throw "Backup hash mismatch: $relative" }
    }
}

foreach ($record in @($receipt.targets)) {
    $relative = [string]$record.relativePath
    $target = Resolve-ContainedPath $gameRoot $relative 'target'
    if ($record.existedBefore) {
        $backup = Resolve-ContainedPath $receiptRoot ([string]$record.backupRelativePath) 'backup'
        Copy-Item -LiteralPath $backup -Destination $target -Force
        if ((Get-Sha256Upper $target) -ne ([string]$record.originalSha256).ToUpperInvariant()) { throw "Restored target hash mismatch: $relative" }
    }
    else {
        Remove-Item -LiteralPath $target -Force
        if (Test-Path -LiteralPath $target) { throw "Package-created target was not removed: $relative" }
    }
}

$restoreReceipt = [ordered]@{
    schemaVersion = 1
    kind = ([string]$receipt.kind -replace '-install$', '-restore')
    mode = [string]$receipt.mode
    packageId = [string]$receipt.packageId
    installReceiptSha256 = Get-Sha256Upper $receiptFull
    gameRoot = $gameRoot
    targetCount = @($receipt.targets).Count
    restoredUtc = [DateTime]::UtcNow.ToString('o')
    restored = $true
}
$restorePath = Join-Path $receiptRoot 'restore-receipt.json'
[IO.File]::WriteAllText($restorePath, (($restoreReceipt | ConvertTo-Json -Depth 6) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    PackageId = [string]$receipt.packageId
    GameRoot = $gameRoot
    RestoreReceiptPath = $restorePath
    TargetCount = @($receipt.targets).Count
    Restored = $true
}
