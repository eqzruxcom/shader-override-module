[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-rebirth-fallback-consumer-f2-owner-stage-test'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$stager = Join-Path $repoRoot 'tools\Stage-IntergradeRebirthFallbackAOF2OwnerIntegration.ps1'
$projectRuntime = Join-Path $repoRoot 'runtime\Intergrade\Mods'
$runRoot = Join-Path $OutputDirectory ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

function Get-TreeHashes([string]$Root) {
    $map = [ordered]@{}
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName) {
        $map[$file.FullName.Substring($Root.Length + 1)] = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
    }
    $map
}
function Assert-MapsEqual([Collections.IDictionary]$A, [Collections.IDictionary]$B, [string]$Context) {
    if (($A.Keys -join "`n") -cne ($B.Keys -join "`n")) { throw "$Context inventory changed." }
    foreach ($key in $A.Keys) { if ($A[$key] -ne $B[$key]) { throw "$Context changed: $key" } }
}
function New-Fixture([string]$Name) {
    $root = Join-Path $runRoot $Name
    $mods = Join-Path $root 'Mods'
    New-Item -ItemType Directory -Path $mods -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $projectRuntime -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $mods -Recurse -Force
    }
    [ordered]@{ Root=$root; Mods=$mods; Backups=(Join-Path $root 'backups') }
}

$projectBefore = Get-TreeHashes $projectRuntime
$fixture = New-Fixture 'clean'
$fixtureBefore = Get-TreeHashes $fixture.Mods
$preStatus = & $stager -Action Status -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups
if ($preStatus.Status -ne 'not-staged' -or $preStatus.Installed -ne $false) { throw 'Pre-stage status is invalid.' }
$stage = & $stager -Action Stage -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups
if ($stage.Status -ne 'staged' -or $stage.Installed -ne $true) { throw 'Clean fixture did not stage.' }
$stagedStatus = & $stager -Action Status -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups
if ($stagedStatus.Status -ne 'staged' -or $stagedStatus.Installed -ne $true) { throw 'Staged status verification failed.' }

$stagedOwner = Join-Path $fixture.Mods 'RebirthEffectsDX11.ini'
$stagedShader = Join-Path $fixture.Mods 'RebirthFallbackAOConsumer_ps.hlsl'
$installedOwnerText = [IO.File]::ReadAllText($stagedOwner)
if ([regex]::Matches($installedOwnerText, '(?im)^\s*key\s*=\s*no_modifiers\s+F2\s*$').Count -ne 1) { throw 'Staged fixture does not claim F2 exactly once.' }
if ([regex]::Matches($installedOwnerText, '(?im)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$').Count -ne 1) { throw 'Staged fixture does not own e2aa exactly once.' }
if (-not (Test-Path -LiteralPath $stagedShader -PathType Leaf)) { throw 'Staged shader is missing.' }

[IO.File]::AppendAllText($stagedOwner, "; drift test`r`n", [Text.UTF8Encoding]::new($false))
$driftStatus = & $stager -Action Status -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups
if ($driftStatus.Status -ne 'drifted') { throw 'Status did not detect staged owner drift.' }
$restoreRejected = $false
try { & $stager -Action Restore -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups | Out-Null } catch { $restoreRejected = $_.Exception.Message -match 'drifted' }
if (-not $restoreRejected) { throw 'Restore did not reject staged drift.' }
Copy-Item -LiteralPath 'artifacts\ao-rebirth-fallback-consumer-f2-owner-integration-pack\Mods\RebirthEffectsDX11.ini' -Destination $stagedOwner -Force
$restore = & $stager -Action Restore -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups
if ($restore.Status -ne 'restored' -or $restore.Installed -ne $false) { throw 'Clean restore failed.' }
$restoredStatus = & $stager -Action Status -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups
if ($restoredStatus.Status -ne 'restored') { throw 'Restored status verification failed.' }
$fixtureAfter = Get-TreeHashes $fixture.Mods
Assert-MapsEqual $fixtureBefore $fixtureAfter 'Fixture after restore'

$negativeResults = [Collections.Generic.List[string]]::new()
foreach ($caseName in @('f2-conflict','duplicate-owner','owner-drift')) {
    $negative = New-Fixture $caseName
    if ($caseName -eq 'f2-conflict') {
        [IO.File]::WriteAllText((Join-Path $negative.Mods 'Conflict.ini'), "[KeyConflict]`r`nkey = no_modifiers F2`r`n", [Text.UTF8Encoding]::new($false))
    } elseif ($caseName -eq 'duplicate-owner') {
        [IO.File]::WriteAllText((Join-Path $negative.Mods 'Conflict.ini'), "[ShaderOverrideConflict]`r`nhash = e2aa1c8cb39e0a55`r`n", [Text.UTF8Encoding]::new($false))
    } else {
        [IO.File]::AppendAllText((Join-Path $negative.Mods 'RebirthEffectsDX11.ini'), "; changed`r`n", [Text.UTF8Encoding]::new($false))
    }
    $beforeNegative = Get-TreeHashes $negative.Mods
    $rejected = $false
    try { & $stager -Action Stage -TargetModsDirectory $negative.Mods -BackupRoot $negative.Backups | Out-Null } catch {
        $rejected = $_.Exception.Message -match 'F2|exactly one e2aa|owner SHA changed'
    }
    if (-not $rejected) { throw "Stage accepted negative case: $caseName" }
    if (Test-Path -LiteralPath $negative.Backups) { throw "Rejected stage created a backup/state directory: $caseName" }
    Assert-MapsEqual $beforeNegative (Get-TreeHashes $negative.Mods) "Rejected case $caseName"
    $negativeResults.Add($caseName)
}

$externalRejected = $false
try { & $stager -Action Status -TargetModsDirectory 'C:\Windows' -BackupRoot (Join-Path $runRoot 'external-guard') | Out-Null } catch {
    $externalRejected = $_.Exception.Message -match 'External target requires'
}
if (-not $externalRejected) { throw 'External target guard did not fail closed.' }

$projectAfter = Get-TreeHashes $projectRuntime
Assert-MapsEqual $projectBefore $projectAfter 'Project runtime'
$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    actions = @('Status not-staged','Stage','Status staged','Status drifted','Restore drift rejection','Restore','Status restored')
    negativeStageCases = @($negativeResults)
    externalTargetGuard = 'pass'
    backupHashVerification = 'pass'
    postStageHashVerification = 'pass'
    projectRuntimeUnchanged = $true
    liveGameDirectoryTouched = $false
}
$reportPath = Join-Path $runRoot 'report.json'
[IO.File]::WriteAllText($reportPath, (($report | ConvertTo-Json -Depth 10) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Output 'Intergrade Rebirth fallback-AO F2 owner Stage/Status/Restore tests passed.'
Write-Output "Report: $reportPath"
