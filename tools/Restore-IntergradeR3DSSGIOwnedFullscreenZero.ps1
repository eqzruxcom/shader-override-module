[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [Parameter(Mandatory)]
    [string]$ReceiptPath,
    [switch]$AllowExternalTarget
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$receiptFile = [IO.Path]::GetFullPath($ReceiptPath)
if (-not (Test-Path -LiteralPath $receiptFile -PathType Leaf)) { throw "Receipt is missing: $receiptFile" }
if (-not $receiptFile.StartsWith((Join-Path $workspace 'artifacts') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Receipt must be inside the workspace artifacts directory.'
}
$receipt = Get-Content -Raw -LiteralPath $receiptFile | ConvertFrom-Json
if ($receipt.schemaVersion -ne 1 -or $receipt.action -ne 'stage-owned-fullscreen-zero' -or $receipt.diagnosticOnly -ne $true) {
    throw 'Receipt contract is invalid.'
}
$target = [IO.Path]::GetFullPath([string]$receipt.targetModsDirectory).TrimEnd('\')
if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw "Target Mods directory is missing: $target" }
if (-not $target.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    if (-not $AllowExternalTarget) { throw "External target requires -AllowExternalTarget: $target" }
    if (-not $target.EndsWith('\End\Binaries\Win64\Mods', [StringComparison]::OrdinalIgnoreCase)) {
        throw "External target must be an exact FF7 Remake Win64 Mods directory: $target"
    }
}
$backup = [IO.Path]::GetFullPath([string]$receipt.backupDirectory).TrimEnd('\')
if (-not $backup.StartsWith((Split-Path -Parent $receiptFile) + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Receipt backup directory is not colocated with its receipt.'
}

$after = @($receipt.after)
$before = @($receipt.before)
if ($after.Count -ne 8 -or $before.Count -ne 8) { throw 'Receipt file set is incomplete.' }
foreach ($entry in $after) {
    $live = Join-Path $target ([string]$entry.name)
    if (-not (Test-Path -LiteralPath $live -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $live).Hash -ne [string]$entry.sha256) {
        throw "Live diagnostic file drifted; refusing rollback: $($entry.name)"
    }
}
foreach ($entry in $before | Where-Object existed) {
    $saved = Join-Path $backup ([string]$entry.name)
    if (-not (Test-Path -LiteralPath $saved -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $saved).Hash -ne [string]$entry.sha256) {
        throw "Rollback backup drifted: $($entry.name)"
    }
}

if (-not $PSCmdlet.ShouldProcess($target, 'Restore files that preceded the diagnostic owned-fullscreen SSGI stage')) { return }
foreach ($entry in $before) {
    $live = Join-Path $target ([string]$entry.name)
    if ($entry.existed) {
        [IO.File]::Copy((Join-Path $backup ([string]$entry.name)), $live, $true)
    } elseif (Test-Path -LiteralPath $live -PathType Leaf) {
        Remove-Item -LiteralPath $live -Force
    }
}
foreach ($entry in $before) {
    $live = Join-Path $target ([string]$entry.name)
    if ($entry.existed) {
        if (-not (Test-Path -LiteralPath $live -PathType Leaf) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $live).Hash -ne [string]$entry.sha256) {
            throw "Rollback verification failed: $($entry.name)"
        }
    } elseif (Test-Path -LiteralPath $live) {
        throw "Rollback failed to remove newly introduced file: $($entry.name)"
    }
}
$restoredReceipt = [ordered]@{
    schemaVersion=1
    action='restore-owned-fullscreen-zero'
    restoredAtUtc=[DateTime]::UtcNow.ToString('o')
    sourceReceipt=$receiptFile
    targetModsDirectory=$target
    reloadRequired=$true
}
$restoredPath = Join-Path (Split-Path -Parent $receiptFile) 'restore-receipt.json'
[IO.File]::WriteAllText($restoredPath, (($restoredReceipt | ConvertTo-Json -Depth 5) + "`r`n"), [Text.UTF8Encoding]::new($false))
[pscustomobject]@{Status='restored';Receipt=$restoredPath;ReloadRequired=$true}
