[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')][string]$CaptureId,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$InstallManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($InstallManifestPath)) { $InstallManifestPath = Join-Path $projectPath "artifacts\installed-validation-capture-kits\$CaptureId.json" }
$manifestFull = (Resolve-Path -LiteralPath $InstallManifestPath).Path
if (-not $manifestFull.StartsWith($projectPath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Install manifest escaped the project.' }
$manifest = & (Join-Path $PSScriptRoot 'Assert-UE4ValidationManifest.ps1') -Kind Install -Path $manifestFull -ProjectRoot $projectPath
if ([string]$manifest.captureId -ne $CaptureId) { throw 'Capture id does not match the install manifest.' }
$targetRoot = [IO.Path]::GetFullPath([string]$manifest.targetRoot).TrimEnd('\')
$backupRoot = [IO.Path]::GetFullPath([string]$manifest.backupRoot).TrimEnd('\')
$allowedBackup = Join-Path $projectPath "backups\UE4ValidationCaptureKit\$CaptureId"
if (-not $backupRoot.StartsWith($allowedBackup + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Backup root escaped the capture-kit backup area.' }
$processName = [IO.Path]::GetFileNameWithoutExtension([string]$manifest.gameExecutable.path)
if (@(Get-Process -Name $processName -ErrorAction SilentlyContinue).Count) { throw "Refusing rollback while $processName is running." }
if (-not $PSCmdlet.ShouldProcess($targetRoot, 'Restore files from before neutral capture-kit installation')) { return }

foreach ($record in @($manifest.files) | Sort-Object relativePath -Descending) {
    $name = [string]$record.relativePath
    if ($name -notin @('d3d11.dll','d3dcompiler_46.dll','nvapi64.dll','d3dx.ini')) { throw "Unsafe manifest target: $name" }
    $destination = Join-Path $targetRoot $name
    if ([bool]$record.hadOriginal) {
        $backup = Join-Path $backupRoot $name
        if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { throw "Backup is missing: $backup" }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $backup).Hash -ne [string]$record.originalSha256) { throw "Backup hash mismatch: $name" }
        Copy-Item -LiteralPath $backup -Destination $destination -Force
    } elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash -ne [string]$record.installedSha256) { throw "Refusing to delete modified generated-only file: $name" }
        Remove-Item -LiteralPath $destination -Force
    }
}
[pscustomobject]@{ CaptureId=$CaptureId; RestoredFiles=@($manifest.files).Count; Target=$targetRoot; Backup=$backupRoot; Result='restored' }
