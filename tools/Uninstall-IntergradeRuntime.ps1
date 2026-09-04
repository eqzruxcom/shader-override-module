[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$manifestPath = Join-Path $projectPath 'artifacts\installed-intergrade-runtime.json'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Install manifest not found: $manifestPath"
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$targetRoot = [IO.Path]::GetFullPath([string]$manifest.targetRoot).TrimEnd('\')
$backupRoot = [IO.Path]::GetFullPath([string]$manifest.backupRoot).TrimEnd('\')

if (-not $backupRoot.StartsWith($projectPath + '\backups\Intergrade\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Backup path is outside the expected workspace backup tree: $backupRoot"
}

if (-not $PSCmdlet.ShouldProcess($targetRoot, 'Remove only verified installed files and restore recorded originals')) {
    return
}

foreach ($record in @($manifest.files) | Sort-Object relativePath -Descending) {
    $destination = Join-Path $targetRoot $record.relativePath
    $backupPath = Join-Path $backupRoot $record.relativePath

    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        $currentHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        if ($currentHash -ne $record.installedSha256) {
            Write-Warning "Leaving modified file untouched: $destination"
            continue
        }
        Remove-Item -LiteralPath $destination -Force
    }

    if ($record.hadOriginal) {
        if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            throw "Recorded backup is missing: $backupPath"
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $backupPath -Destination $destination
    }
}

Write-Output 'Verified runtime files removed; recorded originals restored.'
