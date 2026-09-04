[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$InstallManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($InstallManifestPath)) {
    $InstallManifestPath = Join-Path $projectPath 'artifacts\installed-generated-runtime-overlay.json'
}
$manifestFull = (Resolve-Path -LiteralPath $InstallManifestPath).Path
if (-not $manifestFull.StartsWith($projectPath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Install manifest escaped the project.' }
$manifest = Get-Content -Raw -LiteralPath $manifestFull | ConvertFrom-Json
$targetRoot = [IO.Path]::GetFullPath([string]$manifest.targetRoot).TrimEnd('\')
$backupRoot = [IO.Path]::GetFullPath([string]$manifest.backupRoot).TrimEnd('\')
if (-not $backupRoot.StartsWith((Join-Path $projectPath 'backups\GeneratedRuntimeOverlay') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Backup root is outside the generated-runtime overlay backup area.'
}

if (-not $PSCmdlet.ShouldProcess($targetRoot, 'Restore files from before the generated runtime overlay installation')) { return }
foreach ($record in @($manifest.files) | Sort-Object relativePath -Descending) {
    $relativePath = ([string]$record.relativePath).Replace('/', '\')
    $destination = [IO.Path]::GetFullPath((Join-Path $targetRoot $relativePath))
    if (-not $destination.StartsWith($targetRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe uninstall target: $destination" }
    if ([bool]$record.hadOriginal) {
        $backupPath = [IO.Path]::GetFullPath((Join-Path $backupRoot $relativePath))
        if (-not $backupPath.StartsWith($backupRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe backup path: $backupPath" }
        if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) { throw "Required backup is missing: $backupPath" }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $backupPath).Hash -ne [string]$record.originalSha256) { throw "Backup hash mismatch: $relativePath" }
        Copy-Item -LiteralPath $backupPath -Destination $destination -Force
    } elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
        $currentSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash
        if ($currentSha -ne [string]$record.installedSha256) { throw "Refusing to delete a modified generated file: $relativePath" }
        Remove-Item -LiteralPath $destination -Force
    }
}

[pscustomobject]@{
    Adapter = [string]$manifest.adapterId
    RestoredFiles = @($manifest.files).Count
    Target = $targetRoot
    Backup = $backupRoot
    Result = 'restored'
}
