[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$BackupDirectory,

    [string]$GameDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64',

    [string]$BackupRoot = 'F:\Shader3Dmigoto\FF7Remake'
)

$ErrorActionPreference = 'Stop'

if (Get-Process -Name 'ff7remake_' -ErrorAction SilentlyContinue) {
    throw 'FF7 Remake is running. Stop the game before restoring proxy DLLs.'
}

$backup = (Resolve-Path -LiteralPath $BackupDirectory).Path
$root = (Resolve-Path -LiteralPath $BackupRoot).Path
$game = (Resolve-Path -LiteralPath $GameDirectory).Path
if (-not $backup.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Backup must be inside the configured backup root: $root"
}

$manifestPath = Join-Path $backup 'restore-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Restore manifest is missing: $manifestPath"
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json

$restoreFiles = @('d3d11.dll', 'nvapi64.dll')
foreach ($name in $restoreFiles) {
    $backupFile = Join-Path $backup $name
    if (-not (Test-Path -LiteralPath $backupFile -PathType Leaf)) {
        throw "Backup file is missing: $backupFile"
    }
    $entry = @($manifest.Files | Where-Object Name -eq $name)
    if ($entry.Count -ne 1) {
        throw "Restore manifest must contain one entry for $name."
    }
    if ((Get-FileHash -LiteralPath $backupFile -Algorithm SHA256).Hash -ne $entry[0].Sha256) {
        throw "Backup hash mismatch for $name."
    }
}

if (-not $PSCmdlet.ShouldProcess($game, "Restore 3Dmigoto DLLs from $backup")) {
    return
}

foreach ($name in $restoreFiles) {
    Copy-Item -LiteralPath (Join-Path $backup $name) -Destination (Join-Path $game $name) -Force
}

foreach ($name in $restoreFiles) {
    $entry = @($manifest.Files | Where-Object Name -eq $name)[0]
    if ((Get-FileHash -LiteralPath (Join-Path $game $name) -Algorithm SHA256).Hash -ne $entry.Sha256) {
        throw "Restored hash mismatch for $name."
    }
}

[pscustomobject]@{
    Result = 'restored'
    Backup = $backup
    GameDirectory = $game
    D3D11Version = (Get-Item -LiteralPath (Join-Path $game 'd3d11.dll')).VersionInfo.FileVersion
    D3D11Sha256 = (Get-FileHash -LiteralPath (Join-Path $game 'd3d11.dll') -Algorithm SHA256).Hash
}
