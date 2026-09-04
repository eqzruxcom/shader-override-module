[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [Parameter(Mandatory)]
    [string]$TargetModsDirectory,
    [string]$PackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-zero-pack'),
    [string]$MatrixRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-isolation-matrix'),
    [string]$BackupRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-runtime-backups'),
    [string]$BaselineOutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\agent2-r3d-ssgi-owned-fullscreen-reload-baseline.json'),
    [switch]$AllowExternalTarget,
    [switch]$AcknowledgeDiagnosticOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $AcknowledgeDiagnosticOnly) { throw 'Pass -AcknowledgeDiagnosticOnly to stage this deliberately.' }
if (-not $PSCmdlet.ShouldProcess($TargetModsDirectory, 'Stage owned-fullscreen zero-output pack and capture an atomic pre-F10 baseline')) { return }

$stageArgs = @{
    TargetModsDirectory=$TargetModsDirectory
    PackRoot=$PackRoot
    MatrixRoot=$MatrixRoot
    BackupRoot=$BackupRoot
    AcknowledgeDiagnosticOnly=$true
    Confirm=$false
}
if ($AllowExternalTarget) { $stageArgs.AllowExternalTarget=$true }
$stage = & (Join-Path $PSScriptRoot 'Stage-IntergradeR3DSSGIOwnedFullscreenZero.ps1') @stageArgs
$receipt = if ($null -ne $stage.PSObject.Properties['Receipt']) { [string]$stage.Receipt } else { $null }
try {
    $baselineArgs = @{
        TargetModsDirectory=$TargetModsDirectory
        PackRoot=$PackRoot
        OutputPath=$BaselineOutputPath
    }
    if ($AllowExternalTarget) { $baselineArgs.AllowExternalTarget=$true }
    $baseline = & (Join-Path $PSScriptRoot 'New-IntergradeR3DSSGIOwnedFullscreenReloadBaseline.ps1') @baselineArgs
} catch {
    $baselineError = $_
    if ($receipt) {
        $restoreArgs = @{ReceiptPath=$receipt;Confirm=$false}
        if ($AllowExternalTarget) { $restoreArgs.AllowExternalTarget=$true }
        try { $null = & (Join-Path $PSScriptRoot 'Restore-IntergradeR3DSSGIOwnedFullscreenZero.ps1') @restoreArgs }
        catch { throw "Baseline capture failed and automatic rollback also failed. Baseline: $baselineError Rollback: $_" }
        throw "Baseline capture failed; the newly staged files were restored automatically. Cause: $baselineError"
    }
    throw
}

[pscustomobject]@{
    Status='staged-and-baselined'
    StageStatus=[string]$stage.Status
    Receipt=$receipt
    Baseline=[string]$baseline.Output
    ProcessId=[int]$baseline.ProcessId
    LogOffset=[long]$baseline.LogOffset
    LiveFiles=[int]$baseline.LiveFiles
    ProtectedFiles=[int]$baseline.ProtectedFiles
    F10='unchanged; user reload required'
}
