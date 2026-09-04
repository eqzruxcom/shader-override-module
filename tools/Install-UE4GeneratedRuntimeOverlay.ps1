[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$GeneratedRuntimeDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\generated-runtime\FF7RemakeIntergrade'),
    [string]$GameRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes',
    [string]$InstallManifestPath,
    [switch]$AllowUnknownExecutable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$generatedRoot = (Resolve-Path -LiteralPath $GeneratedRuntimeDirectory).Path.TrimEnd('\')
$allowedGeneratedRoot = [IO.Path]::GetFullPath((Join-Path $projectPath 'artifacts\generated-runtime')).TrimEnd('\')
$generatedManifestPath = Join-Path $generatedRoot 'runtime-manifest.json'
$targetRoot = [IO.Path]::GetFullPath((Join-Path $GameRoot 'End\Binaries\Win64')).TrimEnd('\')
$exePath = Join-Path $targetRoot 'ff7remake_.exe'
$utf8 = [Text.UTF8Encoding]::new($false)

if ([string]::IsNullOrWhiteSpace($InstallManifestPath)) {
    $InstallManifestPath = Join-Path $projectPath 'artifacts\installed-generated-runtime-overlay.json'
}
$installManifestFull = [IO.Path]::GetFullPath($InstallManifestPath)
if (-not $installManifestFull.StartsWith($projectPath + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Install manifest must remain inside the project workspace.'
}
if (-not $generatedRoot.StartsWith($allowedGeneratedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Generated runtime must remain below $allowedGeneratedRoot."
}
if (-not (Test-Path -LiteralPath $generatedManifestPath -PathType Leaf)) { throw "Generated runtime manifest is missing: $generatedManifestPath" }
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { throw "Game executable is missing: $exePath" }

$generatedManifest = Get-Content -Raw -LiteralPath $generatedManifestPath | ConvertFrom-Json
if ([bool]$generatedManifest.licensedRegexDependency) { throw 'Refusing to install a generated runtime with a licensed regex dependency.' }
if (@($generatedManifest.files).Count -lt 2) { throw 'Generated runtime payload is unexpectedly empty.' }
$expectedExeHash = [string]$generatedManifest.executable.sha256
$actualExeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $exePath).Hash
if (-not $AllowUnknownExecutable -and $actualExeHash -ne $expectedExeHash) {
    throw "Executable hash changed. Expected $expectedExeHash, found $actualExeHash."
}

$timestamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$backupRoot = Join-Path $projectPath "backups\GeneratedRuntimeOverlay\$timestamp"
$records = [Collections.Generic.List[object]]::new()
$legacyDiagnostics = @(
    Join-Path $targetRoot 'Mods\RebirthEffectsDX11.ini'
    Join-Path $targetRoot 'Mods\RebirthFogGlobalDX11.ini'
)
$activeLegacyDiagnostics = @($legacyDiagnostics | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
if ($activeLegacyDiagnostics.Count) {
    throw "Refusing generated-runtime overlay installation while legacy diagnostic INIs are active: $($activeLegacyDiagnostics -join ', ')"
}

if (-not $PSCmdlet.ShouldProcess($targetRoot, "Install generated runtime overlay with backup at $backupRoot")) { return }
[IO.Directory]::CreateDirectory($backupRoot) | Out-Null

try {
    foreach ($payload in @($generatedManifest.files)) {
        $relativePath = ([string]$payload.relativePath).Replace('/', '\')
        if ([IO.Path]::IsPathRooted($relativePath) -or $relativePath -match '(^|\\)\.\.(\\|$)') {
            throw "Unsafe generated payload path: $relativePath"
        }
        $source = [IO.Path]::GetFullPath((Join-Path $generatedRoot $relativePath))
        $destination = [IO.Path]::GetFullPath((Join-Path $targetRoot $relativePath))
        if (-not $source.StartsWith($generatedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Payload source escaped generated runtime: $source" }
        if (-not $destination.StartsWith($targetRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Payload destination escaped game runtime: $destination" }
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Generated payload file is missing: $source" }
        $sourceSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
        if ($sourceSha -ne [string]$payload.sha256) { throw "Generated payload hash mismatch: $relativePath" }

        $hadOriginal = Test-Path -LiteralPath $destination -PathType Leaf
        $backupPath = Join-Path $backupRoot $relativePath
        $originalSha = $null
        if ($hadOriginal) {
            [IO.Directory]::CreateDirectory((Split-Path -Parent $backupPath)) | Out-Null
            Copy-Item -LiteralPath $destination -Destination $backupPath
            $originalSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $backupPath).Hash
        }
        [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
        $installedSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash
        if ($installedSha -ne $sourceSha) { throw "Live overlay copy verification failed: $relativePath" }
        $records.Add([pscustomobject][ordered]@{
            relativePath = $relativePath.Replace('\', '/')
            installedSha256 = $installedSha
            hadOriginal = $hadOriginal
            originalSha256 = $originalSha
        })
    }
} catch {
    foreach ($record in @($records) | Sort-Object relativePath -Descending) {
        $relativePath = ([string]$record.relativePath).Replace('/', '\')
        $destination = Join-Path $targetRoot $relativePath
        $backupPath = Join-Path $backupRoot $relativePath
        if ([bool]$record.hadOriginal) {
            Copy-Item -LiteralPath $backupPath -Destination $destination -Force
        } elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
            Remove-Item -LiteralPath $destination -Force
        }
    }
    throw
}

$installManifest = [ordered]@{
    schemaVersion = 1
    installedAtUtc = [DateTime]::UtcNow.ToString('o')
    adapterId = [string]$generatedManifest.adapterId
    sourceManifest = $generatedManifestPath.Substring($projectPath.Length + 1).Replace('\', '/')
    sourceManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $generatedManifestPath).Hash
    targetRoot = $targetRoot
    executable = [ordered]@{ path = $exePath; sha256 = $actualExeHash }
    backupRoot = $backupRoot
    files = @($records)
}
[IO.Directory]::CreateDirectory((Split-Path -Parent $installManifestFull)) | Out-Null
[IO.File]::WriteAllText($installManifestFull, ($installManifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine, $utf8)

[pscustomobject]@{
    Adapter = [string]$generatedManifest.adapterId
    InstalledFiles = @($records).Count
    Target = $targetRoot
    Backup = $backupRoot
    Manifest = $installManifestFull
    ReloadRequired = $true
}
