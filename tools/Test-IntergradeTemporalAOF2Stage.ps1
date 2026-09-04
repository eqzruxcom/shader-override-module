[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-temporal-power-f2-stage-test')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$stager = Join-Path $repoRoot 'tools\Stage-IntergradeTemporalAOF2TestPack.ps1'
$packManifest = Join-Path $repoRoot 'artifacts\ao-temporal-power-f2-test-pack\Balanced\manifest.json'
$runRoot = Join-Path $OutputDirectory ([Guid]::NewGuid().ToString('N'))
$projectMods = Join-Path $runRoot 'fake-project\Mods'
$liveMods = Join-Path $runRoot 'fake-game\End\Binaries\Win64\Mods'
$stateRoot = Join-Path $runRoot 'state'
New-Item -ItemType Directory -Path $projectMods,$liveMods -Force | Out-Null

$projectUnrelated = Join-Path $projectMods 'Unrelated.ini'
$liveUnrelated = Join-Path $liveMods 'Unrelated.ini'
[IO.File]::WriteAllText($projectUnrelated, "[UnrelatedProject]`r`nvalue = 1`r`n", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($liveUnrelated, "[UnrelatedLive]`r`nvalue = 2`r`n", [Text.UTF8Encoding]::new($false))
$projectUnrelatedSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $projectUnrelated).Hash
$liveUnrelatedSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $liveUnrelated).Hash

$initialStatus = & $stager -Action Status -ProjectModsPath $projectMods -LiveModsPath $liveMods -StateRoot $stateRoot -AllowWorkspaceTestTargets
if ($initialStatus.Status -ne 'not-staged' -or $initialStatus.Installed -ne $false) { throw 'Initial F2 stage status is invalid.' }

$stage = & $stager -Action Stage -PackManifestPath $packManifest -ProjectModsPath $projectMods -LiveModsPath $liveMods -StateRoot $stateRoot -AllowWorkspaceTestTargets -Confirm:$false
if (-not $stage.Staged -or $stage.Preset -ne 'Balanced' -or $stage.Key -ne 'F2' -or $stage.F1Claimed -ne $false -or @($stage.Targets).Count -ne 4) {
    throw 'F2 fake-root stage result is invalid.'
}
$status = & $stager -Action Status -ProjectModsPath $projectMods -LiveModsPath $liveMods -StateRoot $stateRoot -AllowWorkspaceTestTargets
if ($status.Status -ne 'staged' -or -not $status.Installed) { throw 'F2 staged status is invalid.' }

$projectIni = Join-Path $projectMods 'IntergradeTemporalAOF2Test.ini'
$projectShader = Join-Path $projectMods 'RemakeTemporalAOPower125_ps.hlsl'
$liveIni = Join-Path $liveMods 'IntergradeTemporalAOF2Test.ini'
$liveShader = Join-Path $liveMods 'RemakeTemporalAOPower125_ps.hlsl'
foreach ($pair in @(@($projectIni,$liveIni),@($projectShader,$liveShader))) {
    if (-not (Test-Path -LiteralPath $pair[0] -PathType Leaf) -or -not (Test-Path -LiteralPath $pair[1] -PathType Leaf)) { throw 'A staged target is missing.' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $pair[0]).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $pair[1]).Hash) { throw 'Project/live staged files differ.' }
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $projectUnrelated).Hash -ne $projectUnrelatedSha -or (Get-FileHash -Algorithm SHA256 -LiteralPath $liveUnrelated).Hash -ne $liveUnrelatedSha) {
    throw 'Staging changed an unrelated file.'
}

[IO.File]::AppendAllText($liveIni, "; drift`r`n", [Text.UTF8Encoding]::new($false))
$driftRejected = $false
try {
    & $stager -Action Restore -ProjectModsPath $projectMods -LiveModsPath $liveMods -StateRoot $stateRoot -AllowWorkspaceTestTargets -Confirm:$false | Out-Null
} catch {
    if ($_.Exception.Message -notmatch 'Refusing restore because a staged target changed') { throw }
    $driftRejected = $true
}
if (-not $driftRejected) { throw 'Restore accepted a drifted live target.' }
Copy-Item -LiteralPath $projectIni -Destination $liveIni -Force

$restore = & $stager -Action Restore -ProjectModsPath $projectMods -LiveModsPath $liveMods -StateRoot $stateRoot -AllowWorkspaceTestTargets -Confirm:$false
if (-not $restore.Restored) { throw 'F2 fake-root restore did not complete.' }
foreach ($path in @($projectIni,$projectShader,$liveIni,$liveShader)) {
    if (Test-Path -LiteralPath $path) { throw "Restore left a tool-created target behind: $path" }
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $projectUnrelated).Hash -ne $projectUnrelatedSha -or (Get-FileHash -Algorithm SHA256 -LiteralPath $liveUnrelated).Hash -ne $liveUnrelatedSha) {
    throw 'Restore changed an unrelated file.'
}

foreach ($conflictType in @('F2','AOHash')) {
    $conflictRoot = Join-Path $runRoot "conflict-$conflictType"
    $conflictProject = Join-Path $conflictRoot 'project\Mods'
    $conflictLive = Join-Path $conflictRoot 'game\End\Binaries\Win64\Mods'
    $conflictState = Join-Path $conflictRoot 'state'
    New-Item -ItemType Directory -Path $conflictProject,$conflictLive -Force | Out-Null
    $conflictText = if ($conflictType -eq 'F2') { "[KeyConflict]`r`nkey = no_modifiers F2`r`n" } else { "[ShaderOverrideConflict]`r`nhash = a77b589dce5822d6`r`n" }
    [IO.File]::WriteAllText((Join-Path $conflictProject 'Conflict.ini'), $conflictText, [Text.UTF8Encoding]::new($false))
    $rejected = $false
    try {
        & $stager -Action Stage -PackManifestPath $packManifest -ProjectModsPath $conflictProject -LiveModsPath $conflictLive -StateRoot $conflictState -AllowWorkspaceTestTargets -Confirm:$false | Out-Null
    } catch {
        if ($_.Exception.Message -notmatch 'Refusing stage because F2 or the AO hash is already active') { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw "Stage accepted $conflictType conflict." }
    if (@(Get-ChildItem -LiteralPath $conflictLive -File).Count -ne 0 -or (Test-Path -LiteralPath (Join-Path $conflictState 'state.json'))) {
        throw "Rejected $conflictType stage changed target state."
    }
}

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    preset = 'Balanced'
    F1Claimed = $false
    F2Staged = $true
    fakeProjectAndLiveMatch = $true
    unrelatedFilesPreserved = $true
    driftedRestoreRejected = $true
    cleanRestoreVerified = $true
    conflictsRejected = @('F2 binding','a77b589dce5822d6 override')
    realGameDirectoryTouched = $false
}
$reportPath = Join-Path $runRoot 'report.json'
[IO.File]::WriteAllText($reportPath, (($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Output 'Intergrade temporal-AO F2 fake-root stage/restore tests passed.'
Write-Output "Report: $reportPath"
