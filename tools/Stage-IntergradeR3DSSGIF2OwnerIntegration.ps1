[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Stage','Status','Restore')]
    [string]$Action,
    [string]$PackManifest = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-owner-integration-pack\manifest.json'),
    [Parameter(Mandatory)]
    [string]$TargetModsDirectory,
    [string]$BackupRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-stage-backups'),
    [switch]$AllowExternalTarget,
    [switch]$AllowExternalBackupRoot,
    [switch]$AcknowledgeOfflineCandidate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$agent2ExternalBackupRoot = [IO.Path]::GetFullPath('F:\Shader3Dmigoto\Agent 2').TrimEnd('\')
$packageId = 'agent2-r3d-ssgi-f2-owner-integration'
$expectedFiles = @(
    'Agent2R3DSSGICompositeE2AA_ps.hlsl',
    'Agent2R3DSSGIDenoise16_ps.hlsl',
    'Agent2R3DSSGIDenoise2_ps.hlsl',
    'Agent2R3DSSGIDenoise4_ps.hlsl',
    'Agent2R3DSSGIDenoise8_ps.hlsl',
    'Agent2R3DSSGITraceE2AA_ps.hlsl',
    'RebirthEffectsDX11.ini'
)

function Get-Hash([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Write-Json([string]$Path, [object]$Value) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))) | Out-Null
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 16) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

function Resolve-WorkspaceFile([string]$Path) {
    $full = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    } else {
        [IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
    }
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Pack file must remain inside the project workspace: $full"
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "Required pack file does not exist: $full"
    }
    $full
}

function Resolve-TargetDirectory([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        throw "Target Mods directory does not exist: $full"
    }
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        if (-not $AllowExternalTarget) { throw "External target requires -AllowExternalTarget: $full" }
        if (-not $full.EndsWith('\End\Binaries\Win64\Mods', [StringComparison]::OrdinalIgnoreCase)) {
            throw "External target must be an exact FF7 Remake Win64 Mods directory: $full"
        }
    }
    $full
}

function Resolve-BackupDirectory([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        if (-not $AllowExternalBackupRoot) { throw "External backup root requires -AllowExternalBackupRoot: $full" }
        if (-not ($full.Equals($agent2ExternalBackupRoot, [StringComparison]::OrdinalIgnoreCase) -or
            $full.StartsWith($agent2ExternalBackupRoot + '\', [StringComparison]::OrdinalIgnoreCase))) {
            throw "External backup root must remain under $agent2ExternalBackupRoot"
        }
    }
    $full
}

function Get-Claims([string]$Root) {
    $claims = [ordered]@{
        F1 = [Collections.Generic.List[object]]::new()
        F2 = [Collections.Generic.List[object]]::new()
        F3 = [Collections.Generic.List[object]]::new()
        E2aa = [Collections.Generic.List[object]]::new()
    }
    foreach ($ini in Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ini' | Sort-Object FullName) {
        $lineNumber = 0
        foreach ($line in Get-Content -LiteralPath $ini.FullName) {
            $lineNumber++
            if ($line -match '^\s*;') { continue }
            foreach ($key in @('F1','F2','F3')) {
                if ($line -match "(?i)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?$key(?![A-Z0-9_]).*$") {
                    $claims[$key].Add([ordered]@{path=$ini.FullName; line=$lineNumber; text=$line.Trim()})
                }
            }
            if ($line -match '(?i)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$') {
                $claims.E2aa.Add([ordered]@{path=$ini.FullName; line=$lineNumber; text=$line.Trim()})
            }
        }
    }
    $claims
}

function Assert-PreStageClaims([string]$Root, [string]$OwnerPath) {
    $claims = Get-Claims $Root
    if ($claims.F1.Count -ne 0) { throw "Target already claims reserved F1: $($claims.F1 | ConvertTo-Json -Compress)" }
    if ($claims.F2.Count -ne 0) { throw "Target already claims F2: $($claims.F2 | ConvertTo-Json -Compress)" }
    if ($claims.F3.Count -ne 1) { throw "Target must preserve exactly one existing F3 claim: $($claims.F3 | ConvertTo-Json -Compress)" }
    if ($claims.E2aa.Count -ne 1 -or -not [string]::Equals($claims.E2aa[0].path, $OwnerPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Target must have exactly one e2aa owner in RebirthEffectsDX11.ini: $($claims.E2aa | ConvertTo-Json -Compress)"
    }
}

function Assert-StagedClaims([string]$Root, [string]$OwnerPath) {
    $claims = Get-Claims $Root
    if ($claims.F1.Count -ne 0 -or $claims.F2.Count -ne 1 -or $claims.F3.Count -ne 1) {
        throw "Post-stage key ownership is invalid: $($claims | ConvertTo-Json -Depth 6 -Compress)"
    }
    if ($claims.E2aa.Count -ne 1 -or -not [string]::Equals($claims.E2aa[0].path, $OwnerPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Post-stage e2aa ownership is invalid.'
    }
}

function Test-InstalledState([object[]]$Records) {
    foreach ($record in $Records) {
        if (-not (Test-Path -LiteralPath $record.destination -PathType Leaf)) { return $false }
        if ((Get-Hash $record.destination) -ne [string]$record.installedSha256) { return $false }
    }
    $true
}

function Test-RestoredState([object[]]$Records) {
    foreach ($record in $Records) {
        $exists = Test-Path -LiteralPath $record.destination -PathType Leaf
        if ([bool]$record.before.existed) {
            if (-not $exists -or (Get-Hash $record.destination) -ne [string]$record.before.sha256) { return $false }
        } elseif ($exists) {
            return $false
        }
    }
    $true
}

$manifestFull = Resolve-WorkspaceFile $PackManifest
$manifest = Get-Content -Raw -LiteralPath $manifestFull | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.result -ne 'pass' -or
    $manifest.classification -ne 'offline-f2-owner-integration-candidate' -or
    $manifest.target.shader -ne 'e2aa1c8cb39e0a55' -or $manifest.target.event -ne 1096 -or
    $manifest.target.ownerIniSha256 -ne 'EFA15E2A820D6CEE6A919AD3B14B736A8ED428B9C779693FF832479B2CC40ECD' -or
    $manifest.controls.F1 -ne 'reserved future global switch' -or
    $manifest.controls.F2 -ne 'this SSGI candidate off/on' -or
    $manifest.controls.F3 -ne 'preserved rolling A/B' -or
    $manifest.policy.exactOwnerRequired -ne $true -or $manifest.policy.runtimeEligible -ne $false -or
    $manifest.policy.installed -ne $false -or $manifest.policy.gameFilesTouched -ne $false -or
    $manifest.policy.liveCaptureRequired -ne $true) {
    throw 'Pack manifest is not the reviewed fail-closed R3D SSGI contract.'
}

$packRoot = [IO.Path]::GetDirectoryName($manifestFull)
$payloads = [Collections.Generic.List[object]]::new()
foreach ($file in @($manifest.files)) {
    $relative = ([string]$file.path).Replace('/', '\')
    if ($relative -notmatch '^Mods\\[^\\]+$') { throw "Pack payload is not a direct Mods file: $relative" }
    $name = [IO.Path]::GetFileName($relative)
    $source = [IO.Path]::GetFullPath((Join-Path $packRoot $relative))
    if (-not $source.StartsWith($packRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Pack payload is missing or escaped its root: $relative"
    }
    if ((Get-Hash $source) -ne [string]$file.sha256) { throw "Pack payload hash mismatch: $relative" }
    $payloads.Add([ordered]@{name=$name; source=$source; sha256=[string]$file.sha256})
}
$actualNames = @($payloads | ForEach-Object {$_.name} | Sort-Object)
if ($actualNames.Count -ne $expectedFiles.Count -or @((Compare-Object $expectedFiles $actualNames)).Count) {
    throw "Pack payload inventory is not the exact reviewed seven-file set: $($actualNames -join ', ')"
}

$targetRoot = Resolve-TargetDirectory $TargetModsDirectory
$backupFull = Resolve-BackupDirectory $BackupRoot
$statePath = Join-Path $backupFull 'active-state.json'
$ownerDestination = Join-Path $targetRoot 'RebirthEffectsDX11.ini'

if ($Action -eq 'Status') {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        [pscustomobject]@{Status='not-staged'; Target=$targetRoot; State=$statePath; Installed=$false}
        return
    }
    $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    if ($state.packageId -ne $packageId -or -not [string]::Equals($state.targetRoot, $targetRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Staging state does not match this package and target.'
    }
    $status = if ($state.status -eq 'staged' -and (Test-InstalledState @($state.files))) {
        'staged'
    } elseif ($state.status -eq 'restored' -and (Test-RestoredState @($state.files))) {
        'restored'
    } else {
        'drifted'
    }
    [pscustomobject]@{Status=$status; Target=$targetRoot; State=$statePath; Installed=($status -eq 'staged'); Files=@($state.files).Count}
    return
}

if ($Action -eq 'Stage') {
    if (-not $AcknowledgeOfflineCandidate) {
        throw 'Stage requires -AcknowledgeOfflineCandidate; live capture and GPU timing remain unverified.'
    }
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $existing = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
        throw "A staging state already exists with status '$($existing.status)': $statePath"
    }
    if (-not (Test-Path -LiteralPath $ownerDestination -PathType Leaf)) { throw "Target owner INI is missing: $ownerDestination" }
    $ownerBeforeHash = Get-Hash $ownerDestination
    if ($ownerBeforeHash -ne [string]$manifest.target.ownerIniSha256) {
        throw "Target owner SHA changed. Expected $($manifest.target.ownerIniSha256), found $ownerBeforeHash"
    }
    Assert-PreStageClaims $targetRoot $ownerDestination
    if (-not $PSCmdlet.ShouldProcess($targetRoot, 'Stage the seven-file offline R3D SSGI F2 candidate with exact rollback')) { return }

    [IO.Directory]::CreateDirectory($backupFull) | Out-Null
    $snapshotRoot = Join-Path $backupFull (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
    [IO.Directory]::CreateDirectory($snapshotRoot) | Out-Null
    $records = [Collections.Generic.List[object]]::new()
    foreach ($payload in $payloads) {
        $destination = Join-Path $targetRoot $payload.name
        $existed = Test-Path -LiteralPath $destination -PathType Leaf
        $beforeSha = if ($existed) { Get-Hash $destination } else { $null }
        $backup = if ($existed) { Join-Path $snapshotRoot ($payload.name + '.before') } else { $null }
        if ($existed) {
            [IO.File]::Copy($destination, $backup, $false)
            if ((Get-Hash $backup) -ne $beforeSha) { throw "Backup hash mismatch: $($payload.name)" }
        }
        $records.Add([ordered]@{
            relativePath = $payload.name
            source = $payload.source
            destination = $destination
            installedSha256 = $payload.sha256
            before = [ordered]@{existed=$existed; sha256=$beforeSha; backup=$backup}
        })
    }
    $state = [ordered]@{
        schemaVersion = 1
        packageId = $packageId
        status = 'staging'
        stagedAtUtc = [DateTime]::UtcNow.ToString('o')
        targetRoot = $targetRoot
        packManifest = $manifestFull
        packManifestSha256 = Get-Hash $manifestFull
        snapshotRoot = $snapshotRoot
        files = @($records)
    }
    Write-Json $statePath $state
    try {
        foreach ($record in $records) {
            [IO.File]::Copy($record.source, $record.destination, $true)
            if ((Get-Hash $record.destination) -ne $record.installedSha256) {
                throw "Post-stage hash mismatch: $($record.relativePath)"
            }
        }
        Assert-StagedClaims $targetRoot $ownerDestination
        $state.status = 'staged'
        Write-Json $statePath $state
    } catch {
        $failure = $_
        foreach ($record in $records) {
            if ([bool]$record.before.existed) {
                [IO.File]::Copy($record.before.backup, $record.destination, $true)
            } elseif (Test-Path -LiteralPath $record.destination -PathType Leaf) {
                [IO.File]::Delete($record.destination)
            }
        }
        $state.status = if (Test-RestoredState @($records)) {
            'automatic-rollback-after-stage-failure'
        } else {
            'automatic-rollback-incomplete'
        }
        Write-Json $statePath $state
        if ($state.status -eq 'automatic-rollback-incomplete') {
            throw "Stage failed and exact automatic rollback could not be verified. State: $statePath. Initial failure: $($failure.Exception.Message)"
        }
        throw $failure
    }
    [pscustomobject]@{Status='staged'; Target=$targetRoot; State=$statePath; Backup=$snapshotRoot; Installed=$true; Files=$records.Count; ReloadRequired=$true; RuntimeEligible=$false}
    return
}

if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw "No staging state exists to restore: $statePath" }
$restoreState = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
if ($restoreState.packageId -ne $packageId -or $restoreState.status -ne 'staged') {
    throw "Only this package's staged state can be restored; current status is '$($restoreState.status)'."
}
if (-not [string]::Equals($restoreState.targetRoot, $targetRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'State target does not match requested target.'
}
if (-not (Test-InstalledState @($restoreState.files))) {
    throw 'Restore refused because a staged destination drifted after installation.'
}
foreach ($record in @($restoreState.files)) {
    if ([bool]$record.before.existed) {
        if (-not (Test-Path -LiteralPath $record.before.backup -PathType Leaf) -or
            (Get-Hash $record.before.backup) -ne [string]$record.before.sha256) {
            throw "Restore backup is invalid: $($record.relativePath)"
        }
    }
}
if (-not $PSCmdlet.ShouldProcess($targetRoot, 'Restore all seven R3D SSGI destinations to their exact pre-stage state')) { return }
try {
    foreach ($record in @($restoreState.files)) {
        if ([bool]$record.before.existed) {
            [IO.File]::Copy($record.before.backup, $record.destination, $true)
        } else {
            [IO.File]::Delete($record.destination)
        }
    }
    if (-not (Test-RestoredState @($restoreState.files))) { throw 'Post-restore state verification failed.' }
    Assert-PreStageClaims $targetRoot $ownerDestination
    $restoreState.status = 'restored'
    $restoreState | Add-Member -NotePropertyName restoredAtUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    Write-Json $statePath $restoreState
} catch {
    $failure = $_
    foreach ($record in @($restoreState.files)) {
        [IO.File]::Copy($record.source, $record.destination, $true)
    }
    if (-not (Test-InstalledState @($restoreState.files))) {
        $restoreState.status = 'restore-failure-recovery-incomplete'
        Write-Json $statePath $restoreState
        throw "Restore failed and the staged state could not be re-established exactly. State: $statePath. Initial failure: $($failure.Exception.Message)"
    }
    throw $failure
}
[pscustomobject]@{Status='restored'; Target=$targetRoot; State=$statePath; Backup=$restoreState.snapshotRoot; Installed=$false; Files=@($restoreState.files).Count; ReloadRequired=$true}
