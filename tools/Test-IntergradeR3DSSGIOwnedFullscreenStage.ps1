[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$matrixMods = Join-Path $workspace 'artifacts\agent2-r3d-ssgi-f2-isolation-matrix\06-zero-composite-no-depth\Mods'
$testRoot = Join-Path $workspace 'artifacts\tests\owned-fullscreen-stage'
$target = Join-Path $testRoot 'Mods'
$backup = Join-Path $testRoot 'Backups'
if (Test-Path -LiteralPath $testRoot -PathType Container) { [IO.Directory]::Delete($testRoot, $true) }
[IO.Directory]::CreateDirectory($target) | Out-Null
foreach ($file in Get-ChildItem -LiteralPath $matrixMods -File) {
    [IO.File]::Copy($file.FullName, (Join-Path $target $file.Name), $false)
}
$before = @(Get-ChildItem -LiteralPath $target -File | Sort-Object Name | ForEach-Object {
    [ordered]@{name=$_.Name;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash}
})

$stageScript = Join-Path $PSScriptRoot 'Stage-IntergradeR3DSSGIOwnedFullscreenZero.ps1'
$restoreScript = Join-Path $PSScriptRoot 'Restore-IntergradeR3DSSGIOwnedFullscreenZero.ps1'
$stage = & $stageScript -TargetModsDirectory $target -BackupRoot $backup -AcknowledgeDiagnosticOnly -Confirm:$false
if ($stage.Status -ne 'staged' -or -not $stage.ReloadRequired) { throw 'Diagnostic stage did not report a staged/reload-required result.' }
if (-not (Test-Path -LiteralPath (Join-Path $target 'Agent2R3DSSGIFullscreen_vs.hlsl') -PathType Leaf)) {
    throw 'Diagnostic stage did not install the fullscreen vertex shader.'
}
$ini = Get-Content -Raw -LiteralPath (Join-Path $target 'Agent2R3DSSGITest.ini')
if ($ini -notmatch '(?im)^\s*draw\s*=\s*3\s*,\s*0\s*$' -or
    $ini -match '(?im)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F10(?![A-Z0-9_]).*$') {
    throw 'Staged INI does not own Draw(3,0), or it binds F10.'
}

$restore = & $restoreScript -ReceiptPath $stage.Receipt -Confirm:$false
if ($restore.Status -ne 'restored' -or -not $restore.ReloadRequired) { throw 'Rollback did not report a restored/reload-required result.' }
$after = @(Get-ChildItem -LiteralPath $target -File | Sort-Object Name | ForEach-Object {
    [ordered]@{name=$_.Name;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash}
})
if (($before | ConvertTo-Json -Depth 4 -Compress) -ne ($after | ConvertTo-Json -Depth 4 -Compress)) {
    throw 'Rollback did not reproduce the exact pre-stage file set.'
}

[pscustomobject]@{
    Result='pass'
    Stage='guarded'
    Rollback='exact'
    FilesRestored=$after.Count
    F10='unbound'
}
