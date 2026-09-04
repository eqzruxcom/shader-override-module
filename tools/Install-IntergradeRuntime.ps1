[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$GameRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes',
    [switch]$AllowUnknownExecutable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedExeHash = '25B54C345C94EE9F6C6876B9C7537A69E6B0EEF25F322207C32A8DDCEE816635'
$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$stageRoot = Join-Path $projectPath 'artifacts\intergrade-runtime'
$targetRoot = Join-Path $GameRoot 'End\Binaries\Win64'
$exePath = Join-Path $targetRoot 'ff7remake_.exe'
$installManifestPath = Join-Path $projectPath 'artifacts\installed-intergrade-runtime.json'

if (-not (Test-Path -LiteralPath $stageRoot -PathType Container)) {
    throw 'Staged runtime is missing. Run Stage-IntergradeRuntime.ps1 first.'
}

if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    throw "Intergrade executable not found: $exePath"
}

$actualExeHash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
if (-not $AllowUnknownExecutable -and $actualExeHash -ne $expectedExeHash) {
    throw "Executable hash changed. Expected $expectedExeHash, found $actualExeHash. Use -AllowUnknownExecutable only after validating the new build."
}

$timestamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$backupRoot = Join-Path $projectPath "backups\Intergrade\$timestamp"
$payload = @(Get-ChildItem -LiteralPath $stageRoot -Recurse -File | Where-Object Name -ne 'stage-manifest.json')
$records = [Collections.Generic.List[object]]::new()

if (-not $PSCmdlet.ShouldProcess($targetRoot, "Install staged 3Dmigoto DX11 runtime with backup at $backupRoot")) {
    return
}

New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

try {
    foreach ($source in $payload) {
        $relativePath = $source.FullName.Substring($stageRoot.Length + 1)
        $destination = Join-Path $targetRoot $relativePath
        $destinationDirectory = Split-Path -Parent $destination
        $backupPath = Join-Path $backupRoot $relativePath
        $hadOriginal = Test-Path -LiteralPath $destination -PathType Leaf

        if ($hadOriginal) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
            Copy-Item -LiteralPath $destination -Destination $backupPath
        }

        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        Copy-Item -LiteralPath $source.FullName -Destination $destination -Force

        $sourceHash = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash
        $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        if ($sourceHash -ne $destinationHash) {
            throw "Copy verification failed: $relativePath"
        }

        $records.Add([pscustomobject]@{
            relativePath = $relativePath
            installedSha256 = $destinationHash
            hadOriginal = $hadOriginal
            originalSha256 = if ($hadOriginal) { (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash } else { $null }
        })
    }
}
catch {
    foreach ($record in @($records) | Sort-Object relativePath -Descending) {
        $destination = Join-Path $targetRoot $record.relativePath
        $backupPath = Join-Path $backupRoot $record.relativePath
        if ($record.hadOriginal) {
            Copy-Item -LiteralPath $backupPath -Destination $destination -Force
        }
        elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
            Remove-Item -LiteralPath $destination -Force
        }
    }
    throw
}

$manifest = [ordered]@{
    schemaVersion = 1
    installedAtUtc = [DateTime]::UtcNow.ToString('o')
    targetRoot = $targetRoot
    executable = [ordered]@{
        path = $exePath
        sha256 = $actualExeHash
    }
    backupRoot = $backupRoot
    files = @($records)
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $installManifestPath -Encoding UTF8
Write-Output "Installed and verified $($records.Count) files in $targetRoot"
Write-Output "Backup: $backupRoot"
Write-Output "Manifest: $installManifestPath"
