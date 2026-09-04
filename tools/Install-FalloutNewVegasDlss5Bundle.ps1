[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $BundleDirectory,
    [Parameter(Mandatory)][string] $GameDirectory,
    [switch] $AcknowledgeTransportOnly,
    [switch] $AcknowledgeFullNeuralCandidate,
    [string] $ReceiptParent = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\fallout-new-vegas-dlss5-installs')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$receiptParentFull = [IO.Path]::GetFullPath($ReceiptParent).TrimEnd('\')
$transportAssertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5Bundle.ps1'
$fullAssertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5FullBundle.ps1'
$utf8 = [Text.UTF8Encoding]::new($false)

function Get-Sha256Upper {
    param([string] $Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Get-PeMachine {
    param([string] $Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x88 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) { throw "Not a PE image: $Path" }
    $pe = [BitConverter]::ToInt32($bytes, 0x3c)
    if ($pe -lt 0 -or $pe + 6 -gt $bytes.Length -or $bytes[$pe] -ne 0x50 -or $bytes[$pe + 1] -ne 0x45) { throw "Invalid PE header: $Path" }
    return [BitConverter]::ToUInt16($bytes, $pe + 4)
}

if (-not ($receiptParentFull -eq $artifactsRoot -or $receiptParentFull.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase))) {
    throw "Refusing to write New Vegas install receipts outside workspace artifacts: $receiptParentFull"
}

$candidateRoot = [IO.Path]::GetFullPath($BundleDirectory).TrimEnd('\')
$candidateManifestPath = Join-Path $candidateRoot 'runtime-bundle.json'
if (-not $candidateRoot.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing a New Vegas bundle outside workspace artifacts: $candidateRoot" }
if (-not (Test-Path -LiteralPath $candidateManifestPath -PathType Leaf)) { throw "runtime-bundle.json is missing: $candidateManifestPath" }
$candidateManifest = Get-Content -Raw -LiteralPath $candidateManifestPath | ConvertFrom-Json
$mode = [string]$candidateManifest.mode
switch ($mode) {
    'transport-only' {
        if (-not $AcknowledgeTransportOnly -or $AcknowledgeFullNeuralCandidate) {
            throw 'Pass only -AcknowledgeTransportOnly to confirm this installs mode=1 transport validation, not DLSS5 neural rendering.'
        }
        $assertPath = $transportAssertPath
        $receiptKind = 'fallout-new-vegas-dlss5-transport-install'
    }
    'full-neural-candidate' {
        if (-not $AcknowledgeFullNeuralCandidate -or $AcknowledgeTransportOnly) {
            throw 'Pass only -AcknowledgeFullNeuralCandidate to confirm this installs an unvalidated mode=2 RenoDX/DLSS5 candidate without frame generation.'
        }
        $assertPath = $fullAssertPath
        $receiptKind = 'fallout-new-vegas-dlss5-full-install'
    }
    default { throw "Unsupported New Vegas bundle mode: $mode" }
}

$validated = & $assertPath -BundleDirectory $candidateRoot
$bundleRoot = [IO.Path]::GetFullPath($validated.BundleRoot).TrimEnd('\')
$gameRoot = (Resolve-Path -LiteralPath $GameDirectory).Path.TrimEnd('\')
if (-not (Test-Path -LiteralPath $gameRoot -PathType Container)) { throw "Game directory does not exist: $gameRoot" }
$gameExe = Join-Path $gameRoot 'FalloutNV.exe'
if (-not (Test-Path -LiteralPath $gameExe -PathType Leaf)) { throw "FalloutNV.exe is missing: $gameExe" }
if ((Get-PeMachine $gameExe) -ne 0x014c) { throw "FalloutNV.exe is not an x86 PE image: $gameExe" }
if (Get-Process -Name 'FalloutNV' -ErrorAction SilentlyContinue) { throw 'FalloutNV.exe is running. Close the game before staging or restoring files.' }

$manifestPath = Join-Path $bundleRoot 'runtime-bundle.json'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$installRecords = @($manifest.files | Where-Object { [string]$_.relativePath -notmatch '^README-(TRANSPORT|DLSS5)\.md$' })
if ($installRecords.Count -lt 20) { throw 'Bundle does not contain the expected runtime payload.' }

$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$receiptRoot = Join-Path $receiptParentFull ($manifest.packageId + '-' + $stamp)
$backupFilesRoot = Join-Path $receiptRoot 'backup'
if (Test-Path -LiteralPath $receiptRoot) { throw "Install receipt already exists: $receiptRoot" }
[IO.Directory]::CreateDirectory($backupFilesRoot) | Out-Null

# Refuse directory/file type collisions before creating backups or changing the game.
foreach ($entry in $installRecords) {
    $relative = [string]$entry.relativePath
    $target = Join-Path $gameRoot $relative.Replace('/', '\')
    if (Test-Path -LiteralPath $target -PathType Container) { throw "Install target is a directory, not a file: $relative" }
}

$targetRecords = [Collections.Generic.List[object]]::new()
foreach ($entry in $installRecords) {
    $relative = [string]$entry.relativePath
    $source = Join-Path $bundleRoot $relative.Replace('/', '\')
    $target = Join-Path $gameRoot $relative.Replace('/', '\')
    $existed = Test-Path -LiteralPath $target -PathType Leaf
    $originalSha = $null
    $backupRelative = $null
    if ($existed) {
        $originalSha = Get-Sha256Upper $target
        $backupRelative = ('backup/' + $relative)
        $backup = Join-Path $receiptRoot $backupRelative.Replace('/', '\')
        [IO.Directory]::CreateDirectory((Split-Path -Parent $backup)) | Out-Null
        Copy-Item -LiteralPath $target -Destination $backup
        if ((Get-Sha256Upper $backup) -ne $originalSha) { throw "Backup hash mismatch before install: $relative" }
    }
    $targetRecords.Add([ordered]@{
        relativePath = $relative
        existedBefore = [bool]$existed
        originalSha256 = $originalSha
        backupRelativePath = $backupRelative
        packageSha256 = ([string]$entry.sha256).ToUpperInvariant()
    })
}

$receipt = [ordered]@{
    schemaVersion = 1
    kind = $receiptKind
    mode = $mode
    packageId = [string]$manifest.packageId
    packageRoot = $bundleRoot
    packageManifestSha256 = Get-Sha256Upper $manifestPath
    gameRoot = $gameRoot
    gameExecutable = 'FalloutNV.exe'
    gameExecutableSha256 = Get-Sha256Upper $gameExe
    createdUtc = [DateTime]::UtcNow.ToString('o')
    targets = @($targetRecords)
    installed = $false
    restored = $false
}
$receiptPath = Join-Path $receiptRoot 'install-receipt.json'
[IO.File]::WriteAllText($receiptPath, (($receipt | ConvertTo-Json -Depth 8) + [Environment]::NewLine), $utf8)

$written = [Collections.Generic.List[object]]::new()
try {
    foreach ($record in $targetRecords) {
        $relative = [string]$record.relativePath
        $source = Join-Path $bundleRoot $relative.Replace('/', '\')
        $target = Join-Path $gameRoot $relative.Replace('/', '\')
        [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
        $written.Add($record)
        if ((Get-Sha256Upper $target) -ne [string]$record.packageSha256) { throw "Installed file hash mismatch: $relative" }
    }
    $receipt.installed = $true
    $receipt.installedUtc = [DateTime]::UtcNow.ToString('o')
    [IO.File]::WriteAllText($receiptPath, (($receipt | ConvertTo-Json -Depth 8) + [Environment]::NewLine), $utf8)
}
catch {
    for ($index = $written.Count - 1; $index -ge 0; $index--) {
        $record = $written[$index]
        $target = Join-Path $gameRoot ([string]$record.relativePath).Replace('/', '\')
        if ($record.existedBefore) {
            $backup = Join-Path $receiptRoot ([string]$record.backupRelativePath).Replace('/', '\')
            Copy-Item -LiteralPath $backup -Destination $target -Force
        }
        elseif (Test-Path -LiteralPath $target -PathType Leaf) {
            Remove-Item -LiteralPath $target -Force
        }
    }
    throw
}

[pscustomobject]@{
    PackageId = [string]$manifest.packageId
    GameRoot = $gameRoot
    ReceiptPath = $receiptPath
    TargetCount = $targetRecords.Count
    Installed = $true
    RuntimeEligible = $false
    Mode = $mode
}
