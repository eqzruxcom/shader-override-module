[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $CaptureSessionDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')][string] $EvidenceId,
    [string] $TransportSplitScreenshotPath,
    [string] $NeuralOffScreenshotPath,
    [string] $NeuralOnScreenshotPath,
    [string] $OutputParent = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\fallout-new-vegas-dlss5-live-evidence')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$sessionRoot = (Resolve-Path -LiteralPath $CaptureSessionDirectory).Path.TrimEnd('\')
$startPath = Join-Path $sessionRoot 'capture-start.json'
$outputParentFull = [IO.Path]::GetFullPath($OutputParent).TrimEnd('\')
$finalRoot = Join-Path $outputParentFull $EvidenceId
$temporaryRoot = Join-Path $outputParentFull ('.staging-' + $EvidenceId + '-' + [Guid]::NewGuid().ToString('N'))
$assertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5LiveEvidence.ps1'
$utf8 = [Text.UTF8Encoding]::new($false)
$moved = $false
if (-not $sessionRoot.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Capture session must be below workspace artifacts.' }
if (-not ($outputParentFull -eq $artifactsRoot -or $outputParentFull.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase))) { throw 'Evidence output must be below workspace artifacts.' }
if (Test-Path -LiteralPath $finalRoot) { throw "Refusing to overwrite live evidence: $finalRoot" }
$start = Get-Content -Raw -LiteralPath $startPath | ConvertFrom-Json
if ($start.schemaVersion -ne 1 -or $start.kind -ne 'fallout-new-vegas-dlss5-live-capture-start' -or $start.completed -ne $false) { throw 'Capture session is invalid or already completed.' }
$gameRoot = [IO.Path]::GetFullPath([string]$start.gameRoot).TrimEnd('\')
if (Get-Process -Name FalloutNV -ErrorAction SilentlyContinue) { throw 'Exit FalloutNV.exe before completing evidence capture.' }
$receiptPath = (Resolve-Path -LiteralPath ([string]$start.installReceiptPath)).Path
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $receiptPath).Hash -ne ([string]$start.installReceiptSha256).ToUpperInvariant()) { throw 'Install receipt changed after capture start.' }
$receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json
$gameExe = Join-Path $gameRoot 'FalloutNV.exe'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $gameExe).Hash -ne ([string]$start.gameExecutableSha256).ToUpperInvariant()) { throw 'FalloutNV.exe changed during capture.' }
$endedUtc = [DateTime]::UtcNow
$startedUtc = ([DateTimeOffset]$start.startedUtc).UtcDateTime

if ($start.phase -eq 'transport') {
    if ([string]::IsNullOrWhiteSpace($TransportSplitScreenshotPath)) { throw 'Transport capture requires -TransportSplitScreenshotPath.' }
    if ($NeuralOffScreenshotPath -or $NeuralOnScreenshotPath) { throw 'Transport capture must not include neural screenshots.' }
}
else {
    if ([string]::IsNullOrWhiteSpace($NeuralOffScreenshotPath) -or [string]::IsNullOrWhiteSpace($NeuralOnScreenshotPath)) { throw 'Neural capture requires both off/on screenshots.' }
    if ($TransportSplitScreenshotPath) { throw 'Neural capture must not include a transport-split screenshot.' }
}

function Get-Sha256Upper { param([string] $Path) return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant() }
function Copy-Screenshot {
    param([string] $Source, [string] $Role, [string] $Name, [string] $Root, [DateTime] $Started)
    $resolved = (Resolve-Path -LiteralPath $Source).Path
    $item = Get-Item -LiteralPath $resolved
    if ($item.Length -lt 1024) { throw "$Role screenshot is implausibly small." }
    if ($item.LastWriteTimeUtc -lt $Started.AddSeconds(-2)) { throw "$Role screenshot predates the capture session." }
    $extension = [IO.Path]::GetExtension($resolved).ToLowerInvariant()
    if ($extension -notin @('.png', '.jpg', '.jpeg', '.bmp')) { throw "$Role screenshot must be PNG, JPEG, or BMP." }
    $destination = Join-Path $Root ('screenshots\' + $Name + $extension)
    [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
    Copy-Item -LiteralPath $resolved -Destination $destination
    return [ordered]@{ role = $Role; relativePath = $destination.Substring($Root.Length + 1).Replace('\', '/'); sha256 = Get-Sha256Upper $destination; sizeBytes = [long](Get-Item $destination).Length }
}

try {
    [IO.Directory]::CreateDirectory((Join-Path $temporaryRoot 'logs')) | Out-Null
    $files = [Collections.Generic.List[object]]::new()
    foreach ($snapshot in @($start.logs)) {
        $source = Join-Path $gameRoot ([string]$snapshot.sourceRelativePath).Replace('/', '\')
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Required runtime log is missing: $($snapshot.sourceRelativePath)" }
        $item = Get-Item -LiteralPath $source
        if ($item.LastWriteTimeUtc -lt $startedUtc.AddSeconds(-2)) { throw "Runtime log was not updated during this capture: $($snapshot.sourceRelativePath)" }
        $bytes = [IO.File]::ReadAllBytes($source)
        $offset = 0
        if ($snapshot.existed -and $snapshot.length -gt 0 -and $bytes.Length -ge [long]$snapshot.length) {
            $prefix = [byte[]]::new([int]$snapshot.length)
            [Array]::Copy($bytes, 0, $prefix, 0, [int]$snapshot.length)
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $prefixHash = ([BitConverter]::ToString($sha.ComputeHash($prefix))).Replace('-', '') } finally { $sha.Dispose() }
            if ($prefixHash -eq [string]$snapshot.sha256) { $offset = [int]$snapshot.length }
        }
        if ($offset -ge $bytes.Length) { throw "Runtime log has no new bytes for this capture: $($snapshot.sourceRelativePath)" }
        $tail = [byte[]]::new($bytes.Length - $offset)
        [Array]::Copy($bytes, $offset, $tail, 0, $tail.Length)
        $destination = Join-Path $temporaryRoot ('logs\' + [string]$snapshot.role + '.log')
        [IO.File]::WriteAllBytes($destination, $tail)
        $files.Add([ordered]@{ role = [string]$snapshot.role; relativePath = $destination.Substring($temporaryRoot.Length + 1).Replace('\', '/'); sha256 = Get-Sha256Upper $destination; sizeBytes = [long]$tail.Length })
    }
    if ($start.phase -eq 'transport') {
        $files.Add((Copy-Screenshot $TransportSplitScreenshotPath 'transportSplitScreenshot' 'transport-split' $temporaryRoot $startedUtc))
    }
    else {
        $files.Add((Copy-Screenshot $NeuralOffScreenshotPath 'neuralOffScreenshot' 'neural-off' $temporaryRoot $startedUtc))
        $files.Add((Copy-Screenshot $NeuralOnScreenshotPath 'neuralOnScreenshot' 'neural-on' $temporaryRoot $startedUtc))
    }
    $manifest = [ordered]@{
        schemaVersion = 1
        kind = 'fallout-new-vegas-dlss5-live-evidence'
        evidenceId = $EvidenceId
        adapter = 'FalloutNewVegas'
        phase = [string]$start.phase
        capturedUtc = $endedUtc.ToString('o')
        run = [ordered]@{ startedUtc = ([DateTimeOffset]$start.startedUtc).ToUniversalTime().ToString('o'); endedUtc = $endedUtc.ToString('o') }
        binding = [ordered]@{
            packageId = [string]$start.packageId
            packageManifestSha256 = [string]$start.packageManifestSha256
            installReceiptSha256 = [string]$start.installReceiptSha256
            gameExecutableSha256 = [string]$start.gameExecutableSha256
            captureStartSha256 = Get-Sha256Upper $startPath
        }
        files = @($files)
        policy = [ordered]@{ synthetic = $false; gameDirectoryRetained = $false; rawLogsRetained = $true; frameGenerationIncluded = $false }
    }
    [IO.File]::WriteAllText((Join-Path $temporaryRoot 'live-evidence.json'), (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine), $utf8)
    [IO.Directory]::CreateDirectory($outputParentFull) | Out-Null
    [IO.Directory]::Move($temporaryRoot, $finalRoot)
    $moved = $true
    $result = & $assertPath -EvidenceDirectory $finalRoot
    $start.completed = $true
    $start | Add-Member -NotePropertyName completedUtc -NotePropertyValue $endedUtc.ToString('o')
    $start | Add-Member -NotePropertyName evidenceId -NotePropertyValue $EvidenceId
    $start | Add-Member -NotePropertyName evidenceManifestSha256 -NotePropertyValue (Get-Sha256Upper (Join-Path $finalRoot 'live-evidence.json'))
    [IO.File]::WriteAllText($startPath, (($start | ConvertTo-Json -Depth 8) + [Environment]::NewLine), $utf8)
    return $result
}
catch {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
    if ($moved -and (Test-Path -LiteralPath $finalRoot -PathType Container)) { Remove-Item -LiteralPath $finalRoot -Recurse -Force }
    throw
}
