[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $InstallReceiptPath,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')][string] $SessionId,
    [string] $OutputParent = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\fallout-new-vegas-dlss5-live-capture-sessions')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$outputParentFull = [IO.Path]::GetFullPath($OutputParent).TrimEnd('\')
$sessionRoot = Join-Path $outputParentFull $SessionId
$utf8 = [Text.UTF8Encoding]::new($false)
if (-not ($outputParentFull -eq $artifactsRoot -or $outputParentFull.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase))) {
    throw "Refusing capture-session output outside workspace artifacts: $outputParentFull"
}
if (Test-Path -LiteralPath $sessionRoot) { throw "Refusing to overwrite a capture session: $sessionRoot" }
$receiptFull = (Resolve-Path -LiteralPath $InstallReceiptPath).Path
if (-not $receiptFull.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Install receipt must be below workspace artifacts.' }
$receipt = Get-Content -Raw -LiteralPath $receiptFull | ConvertFrom-Json
if ($receipt.schemaVersion -ne 1 -or $receipt.installed -ne $true -or $receipt.restored -ne $false -or
    [string]$receipt.mode -notin @('transport-only', 'full-neural-candidate')) { throw 'Install receipt is not an active New Vegas DLSS5 install.' }
$gameRoot = [IO.Path]::GetFullPath([string]$receipt.gameRoot).TrimEnd('\')
$gameExe = Join-Path $gameRoot 'FalloutNV.exe'
if (-not (Test-Path -LiteralPath $gameExe -PathType Leaf)) { throw 'Install receipt game root no longer contains FalloutNV.exe.' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $gameExe).Hash -ne ([string]$receipt.gameExecutableSha256).ToUpperInvariant()) { throw 'FalloutNV.exe no longer matches the install receipt.' }
if (Get-Process -Name FalloutNV -ErrorAction SilentlyContinue) { throw 'Close FalloutNV.exe before starting an evidence capture.' }
$packageManifest = Join-Path ([string]$receipt.packageRoot) 'runtime-bundle.json'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $packageManifest).Hash -ne ([string]$receipt.packageManifestSha256).ToUpperInvariant()) { throw 'Package manifest no longer matches the install receipt.' }
foreach ($target in @($receipt.targets)) {
    $relative = [string]$target.relativePath
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative.Contains(':') -or $relative -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Install receipt contains an unsafe target path: $relative"
    }
    $installed = [IO.Path]::GetFullPath((Join-Path $gameRoot $relative.Replace('/', '\')))
    if (-not $installed.StartsWith($gameRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Installed target escapes the game root: $relative" }
    if (-not (Test-Path -LiteralPath $installed -PathType Leaf)) { throw "Installed payload is missing before capture: $relative" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $installed).Hash -ne ([string]$target.packageSha256).ToUpperInvariant()) {
        throw "Installed payload drifted before capture: $relative"
    }
}

$phase = if ($receipt.mode -eq 'transport-only') { 'transport' } else { 'neural' }
$logs = @(
    [ordered]@{ role = 'dxvkLog'; sourceRelativePath = 'FalloutNV_d3d9.log' },
    [ordered]@{ role = 'gameReShadeLog'; sourceRelativePath = 'ReShade.log' },
    [ordered]@{ role = 'feedLog'; sourceRelativePath = 'dlss5-feed.log' },
    [ordered]@{ role = 'feedLayerLog'; sourceRelativePath = 'layers/x86/feed-vk-layer.log' },
    [ordered]@{ role = 'hostLog'; sourceRelativePath = 'host64/dlss5-feed-host.log' }
)
if ($phase -eq 'neural') { $logs += [ordered]@{ role = 'hostReShadeLog'; sourceRelativePath = 'host64/ReShade.log' } }
$snapshots = @($logs | ForEach-Object {
    $path = Join-Path $gameRoot $_.sourceRelativePath.Replace('/', '\')
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    [ordered]@{
        role = $_.role
        sourceRelativePath = $_.sourceRelativePath
        existed = $exists
        length = if ($exists) { [long](Get-Item -LiteralPath $path).Length } else { [long]0 }
        sha256 = if ($exists) { (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToUpperInvariant() } else { $null }
        lastWriteUtc = if ($exists) { (Get-Item -LiteralPath $path).LastWriteTimeUtc.ToString('o') } else { $null }
    }
})
[IO.Directory]::CreateDirectory($sessionRoot) | Out-Null
$start = [ordered]@{
    schemaVersion = 1
    kind = 'fallout-new-vegas-dlss5-live-capture-start'
    sessionId = $SessionId
    phase = $phase
    startedUtc = [DateTime]::UtcNow.ToString('o')
    installReceiptPath = $receiptFull
    installReceiptSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $receiptFull).Hash.ToUpperInvariant()
    packageId = [string]$receipt.packageId
    packageManifestSha256 = [string]$receipt.packageManifestSha256
    gameRoot = $gameRoot
    gameExecutableSha256 = [string]$receipt.gameExecutableSha256
    logs = $snapshots
    completed = $false
}
$startPath = Join-Path $sessionRoot 'capture-start.json'
[IO.File]::WriteAllText($startPath, (($start | ConvertTo-Json -Depth 8) + [Environment]::NewLine), $utf8)
[pscustomobject]@{
    SessionId = $SessionId
    SessionRoot = $sessionRoot
    Phase = $phase
    StartedUtc = $start.startedUtc
    LaunchCommand = Join-Path $gameRoot 'Launch-FalloutNV-DLSS5.cmd'
    Next = if ($phase -eq 'transport') { 'Run the game, capture the visible left-half mode-1 split, exit, then complete this session.' } else { 'Run the game for at least 600 moving-camera frames, capture neural off/on images, exit, then complete this session.' }
}
