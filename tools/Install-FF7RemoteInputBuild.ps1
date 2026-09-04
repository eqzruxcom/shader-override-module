[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$PackageDirectory,

    [string]$GameDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64',

    [string]$BackupRoot = 'F:\Shader3Dmigoto\FF7Remake'
)

$ErrorActionPreference = 'Stop'

if (Get-Process -Name 'ff7remake_' -ErrorAction SilentlyContinue) {
    throw 'FF7 Remake is running. Stop the game before installing a proxy DLL.'
}

$package = (Resolve-Path -LiteralPath $PackageDirectory).Path
$game = (Resolve-Path -LiteralPath $GameDirectory).Path
$manifestPath = Join-Path $package 'manifest.json'
$payload = Join-Path $package 'payload'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Package manifest is missing: $manifestPath"
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.Status -ne 'staged-not-installed') {
    throw "Unexpected package status: $($manifest.Status)"
}

$deploymentFiles = @('d3d11.dll', 'nvapi64.dll')
foreach ($name in $deploymentFiles) {
    $packageFile = Join-Path $payload $name
    $liveFile = Join-Path $game $name
    if (-not (Test-Path -LiteralPath $packageFile -PathType Leaf)) {
        throw "Package file is missing: $packageFile"
    }
    if (-not (Test-Path -LiteralPath $liveFile -PathType Leaf)) {
        throw "Live file is missing: $liveFile"
    }

    $entry = @($manifest.Files | Where-Object Path -eq "payload\$name")
    if ($entry.Count -ne 1) {
        throw "Manifest must contain one payload entry for $name."
    }
    $actualHash = (Get-FileHash -LiteralPath $packageFile -Algorithm SHA256).Hash
    if ($actualHash -ne $entry[0].Sha256) {
        throw "Package hash mismatch for $name."
    }
}

if (-not $PSCmdlet.ShouldProcess($game, "Back up and install rebuilt 3Dmigoto DLLs from $package")) {
    return
}

New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
$stamp = [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$backup = Join-Path $BackupRoot "$stamp-pre-install-remote-input"
if (Test-Path -LiteralPath $backup) {
    throw "Backup directory already exists: $backup"
}
New-Item -ItemType Directory -Path $backup | Out-Null

$backupEntries = @()
foreach ($name in $deploymentFiles) {
    $liveFile = Join-Path $game $name
    $backupFile = Join-Path $backup $name
    Copy-Item -LiteralPath $liveFile -Destination $backupFile
    $backupEntries += [pscustomobject]@{
        Name = $name
        Sha256 = (Get-FileHash -LiteralPath $backupFile -Algorithm SHA256).Hash
        Length = (Get-Item -LiteralPath $backupFile).Length
    }
}
Copy-Item -LiteralPath (Join-Path $game 'd3dx.ini') -Destination $backup

$backupManifest = [pscustomobject]@{
    CreatedUtc = [datetime]::UtcNow.ToString('o')
    SourceGameDirectory = $game
    InstalledPackage = $package
    Files = $backupEntries
}
[IO.File]::WriteAllText(
    (Join-Path $backup 'restore-manifest.json'),
    ($backupManifest | ConvertTo-Json -Depth 4),
    [Text.UTF8Encoding]::new($false))

try {
    foreach ($name in $deploymentFiles) {
        Copy-Item -LiteralPath (Join-Path $payload $name) -Destination (Join-Path $game $name) -Force
    }

    foreach ($name in $deploymentFiles) {
        $entry = @($manifest.Files | Where-Object Path -eq "payload\$name")[0]
        $installedHash = (Get-FileHash -LiteralPath (Join-Path $game $name) -Algorithm SHA256).Hash
        if ($installedHash -ne $entry.Sha256) {
            throw "Installed hash mismatch for $name."
        }
    }
}
catch {
    foreach ($name in $deploymentFiles) {
        Copy-Item -LiteralPath (Join-Path $backup $name) -Destination (Join-Path $game $name) -Force
    }
    throw "Installation failed and the original DLLs were restored from $backup. $($_.Exception.Message)"
}

[pscustomobject]@{
    Result = 'installed'
    Package = $package
    Backup = $backup
    GameDirectory = $game
    D3D11Version = (Get-Item -LiteralPath (Join-Path $game 'd3d11.dll')).VersionInfo.FileVersion
    D3D11Sha256 = (Get-FileHash -LiteralPath (Join-Path $game 'd3d11.dll') -Algorithm SHA256).Hash
}
