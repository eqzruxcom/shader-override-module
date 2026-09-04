[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Status','Stage','Restore')]
    [string]$Action = 'Status',
    [string]$PackManifestPath,
    [string]$ProjectModsPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime\Intergrade\Mods'),
    [string]$LiveModsPath = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\Mods',
    [string]$StateRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'backups\temporal-ao-f2-stage'),
    [switch]$AllowWorkspaceTestTargets
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$stateRootFull = [IO.Path]::GetFullPath($StateRoot)
if (-not $stateRootFull.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "State root must remain inside the workspace: $stateRootFull" }
$statePath = Join-Path $stateRootFull 'state.json'

function Resolve-WorkspaceFile([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Pack file must remain inside the workspace: $full" }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Required pack file is missing: $full" }
    $full
}

function Resolve-TargetDirectory([string]$Path, [string]$Role) {
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw "$Role directory is missing: $full" }
    if ($Role -eq 'Project Mods' -and -not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Project Mods must remain inside the workspace: $full"
    }
    if ($Role -eq 'Live Mods') {
        if ($AllowWorkspaceTestTargets) {
            if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Workspace test target escaped the workspace: $full" }
        } elseif (-not $full.EndsWith('\End\Binaries\Win64\Mods', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Live Mods must end with End\Binaries\Win64\Mods: $full"
        }
    }
    $full
}

function Get-Sha256([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Get-State {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
}

function Write-State([object]$State) {
    New-Item -ItemType Directory -Path $stateRootFull -Force | Out-Null
    [IO.File]::WriteAllText($statePath, (($State | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

function Find-Conflicts([string[]]$Roots) {
    @(
        foreach ($root in $Roots) {
            foreach ($iniFile in Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ini') {
                $lineNumber = 0
                foreach ($line in Get-Content -LiteralPath $iniFile.FullName) {
                    $lineNumber++
                    if ($line -match '^\s*;') { continue }
                    if ($line -match '(?i)(?<![A-Z0-9_])(?:VK_)?F2(?![A-Z0-9_])' -or $line -match '(?i)^\s*hash\s*=\s*a77b589dce5822d6\s*$') {
                        [pscustomobject]@{path=$iniFile.FullName;line=$lineNumber;text=$line.Trim()}
                    }
                }
            }
        }
    )
}

$existingState = Get-State
if ($Action -eq 'Status') {
    if ($null -eq $existingState) {
        [pscustomobject]@{Action='Status';Status='not-staged';StatePath=$statePath;Installed=$false}
        return
    }
    $installed = $existingState.status -eq 'staged'
    if ($installed) {
        foreach ($target in $existingState.targets) {
            if (-not (Test-Path -LiteralPath $target.path -PathType Leaf) -or (Get-Sha256 $target.path) -ne $target.stagedSha256) { $installed = $false }
        }
    }
    [pscustomobject]@{Action='Status';Status=$existingState.status;Preset=$existingState.preset;StatePath=$statePath;Installed=$installed;StagedAtUtc=$existingState.stagedAtUtc}
    return
}

if ($Action -eq 'Restore') {
    if ($null -eq $existingState -or $existingState.status -ne 'staged') { throw "No active F2 AO stage was found: $statePath" }
    foreach ($target in $existingState.targets) {
        if (-not (Test-Path -LiteralPath $target.path -PathType Leaf)) { throw "Refusing restore because a staged target is missing: $($target.path)" }
        $actual = Get-Sha256 $target.path
        if ($actual -ne $target.stagedSha256) { throw "Refusing restore because a staged target changed: $($target.path)" }
    }
    if (-not $PSCmdlet.ShouldProcess(($existingState.targets.path -join ', '), 'Restore files from before the F2 AO stage')) {
        [pscustomobject]@{Action='Restore';Restored=$false;WhatIf=$true;StatePath=$statePath}
        return
    }
    foreach ($target in $existingState.targets) {
        if ($target.existedBefore) {
            if (-not (Test-Path -LiteralPath $target.backupPath -PathType Leaf)) { throw "Backup is missing: $($target.backupPath)" }
            Copy-Item -LiteralPath $target.backupPath -Destination $target.path -Force
        } else {
            Remove-Item -LiteralPath $target.path -Force
        }
    }
    $existingState.status = 'restored'
    $existingState | Add-Member -NotePropertyName restoredAtUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    Write-State $existingState
    [pscustomobject]@{Action='Restore';Restored=$true;StatePath=$statePath;Targets=@($existingState.targets.path)}
    return
}

if ([string]::IsNullOrWhiteSpace($PackManifestPath)) { throw '-PackManifestPath is required for Stage.' }
if ($null -ne $existingState -and $existingState.status -eq 'staged') { throw 'An F2 AO pack is already staged. Restore it before staging another.' }

$manifestFull = Resolve-WorkspaceFile $PackManifestPath
$manifest = Get-Content -Raw -LiteralPath $manifestFull | ConvertFrom-Json
if ($manifest.status -ne 'offline-staging-pack-not-installed' -or $manifest.runtimeEligible -ne $false -or $manifest.installationPerformed -ne $false) {
    throw 'Pack manifest is not an approved offline F2 staging input.'
}
if ($manifest.shaderHash -ne 'a77b589dce5822d6' -or $manifest.keyContract.F1 -ne 'not claimed; future global mod on/off' -or
    $manifest.keyContract.F2 -ne 'binary native/candidate test toggle' -or $manifest.keyContract.defaultState -ne 0) {
    throw 'Pack manifest identity or key contract is invalid.'
}

$iniSource = Resolve-WorkspaceFile (Join-Path $repoRoot ($manifest.ini -replace '/', '\'))
$shaderSource = Resolve-WorkspaceFile (Join-Path $repoRoot ($manifest.shader -replace '/', '\'))
if ((Get-Sha256 $iniSource) -ne $manifest.iniSha256 -or (Get-Sha256 $shaderSource) -ne $manifest.shaderSha256) { throw 'Pack source hash mismatch.' }
$projectModsFull = Resolve-TargetDirectory $ProjectModsPath 'Project Mods'
$liveModsFull = Resolve-TargetDirectory $LiveModsPath 'Live Mods'
if ($projectModsFull -eq $liveModsFull) { throw 'Project Mods and Live Mods must be different directories.' }
$conflicts = @(Find-Conflicts @($projectModsFull,$liveModsFull))
if ($conflicts.Count -ne 0) { throw "Refusing stage because F2 or the AO hash is already active: $($conflicts | ConvertTo-Json -Compress)" }

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$backupRoot = Join-Path $stateRootFull $timestamp
$targetSpecs = @(
    [ordered]@{role='project-ini';source=$iniSource;path=(Join-Path $projectModsFull ([IO.Path]::GetFileName($iniSource)))},
    [ordered]@{role='project-shader';source=$shaderSource;path=(Join-Path $projectModsFull ([IO.Path]::GetFileName($shaderSource)))},
    [ordered]@{role='live-ini';source=$iniSource;path=(Join-Path $liveModsFull ([IO.Path]::GetFileName($iniSource)))},
    [ordered]@{role='live-shader';source=$shaderSource;path=(Join-Path $liveModsFull ([IO.Path]::GetFileName($shaderSource)))}
)

if (-not $PSCmdlet.ShouldProcess(($targetSpecs.path -join ', '), "Stage $($manifest.preset) temporal-AO F2 test pack")) {
    [pscustomobject]@{Action='Stage';Staged=$false;WhatIf=$true;Preset=$manifest.preset;StatePath=$statePath}
    return
}

New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
$targets = [Collections.Generic.List[object]]::new()
foreach ($spec in $targetSpecs) {
    $existed = Test-Path -LiteralPath $spec.path -PathType Leaf
    $backupPath = Join-Path $backupRoot ($spec.role + '.before')
    $beforeSha = $null
    if ($existed) {
        $beforeSha = Get-Sha256 $spec.path
        Copy-Item -LiteralPath $spec.path -Destination $backupPath
    }
    Copy-Item -LiteralPath $spec.source -Destination $spec.path -Force
    $stagedSha = Get-Sha256 $spec.path
    $expectedSha = Get-Sha256 $spec.source
    if ($stagedSha -ne $expectedSha) { throw "Staged hash mismatch: $($spec.path)" }
    $targets.Add([ordered]@{role=$spec.role;path=$spec.path;existedBefore=$existed;beforeSha256=$beforeSha;backupPath=if($existed){$backupPath}else{$null};stagedSha256=$stagedSha})
}

$state = [ordered]@{
    schemaVersion = 1
    status = 'staged'
    preset = $manifest.preset
    power = $manifest.power
    packManifest = $manifestFull
    packManifestSha256 = Get-Sha256 $manifestFull
    key = 'F2'
    F1Claimed = $false
    offPath = 'native game shader fallthrough'
    targets = @($targets)
    backupRoot = $backupRoot
    stagedAtUtc = [DateTime]::UtcNow.ToString('o')
    reloadRequired = $true
}
Write-State $state
[pscustomobject]@{Action='Stage';Staged=$true;Preset=$manifest.preset;Power=$manifest.power;Key='F2';F1Claimed=$false;StatePath=$statePath;BackupRoot=$backupRoot;ReloadRequired=$true;Targets=@($targets.path)}
