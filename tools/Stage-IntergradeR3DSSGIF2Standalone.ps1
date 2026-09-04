[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Stage','Status','Restore')]
    [string]$Action,
    [string]$PackManifest = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-standalone-pack\manifest.json'),
    [Parameter(Mandatory)]
    [string]$TargetModsDirectory,
    [string]$BackupRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-standalone-stage-backups'),
    [switch]$AllowExternalTarget,
    [switch]$AllowExternalBackupRoot,
    [switch]$AcknowledgeOfflineCandidate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$allowedExternalBackup = [IO.Path]::GetFullPath('F:\Shader3Dmigoto\Agent 2').TrimEnd('\')
$packageId = 'agent2-r3d-ssgi-f2-standalone'
$expectedPayloadNames = @(
    'Agent2R3DSSGICompositeE2AA_ps.hlsl',
    'Agent2R3DSSGIDenoise16_ps.hlsl',
    'Agent2R3DSSGIDenoise2_ps.hlsl',
    'Agent2R3DSSGIDenoise4_ps.hlsl',
    'Agent2R3DSSGIDenoise8_ps.hlsl',
    'Agent2R3DSSGITest.ini',
    'Agent2R3DSSGITraceE2AA_ps.hlsl'
)

function Get-Hash([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Write-Json([string]$Path, [object]$Value) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))) | Out-Null
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 16) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

function Resolve-WorkspaceFile([string]$Path) {
    $full = if ([IO.Path]::IsPathRooted($Path)) {[IO.Path]::GetFullPath($Path)} else {[IO.Path]::GetFullPath((Join-Path $root $Path))}
    if (-not $full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Pack manifest escaped the workspace: $full" }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Pack manifest is missing: $full" }
    $full
}

function Resolve-Target([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw "Target Mods directory is missing: $full" }
    if (-not $full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        if (-not $AllowExternalTarget) { throw "External target requires -AllowExternalTarget: $full" }
        if (-not $full.EndsWith('\End\Binaries\Win64\Mods', [StringComparison]::OrdinalIgnoreCase)) {
            throw "External target must be an exact FF7 Remake Win64 Mods directory: $full"
        }
    }
    $full
}

function Resolve-Backup([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not $full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        if (-not $AllowExternalBackupRoot) { throw "External backup root requires -AllowExternalBackupRoot: $full" }
        if (-not ($full.Equals($allowedExternalBackup, [StringComparison]::OrdinalIgnoreCase) -or
            $full.StartsWith($allowedExternalBackup + '\', [StringComparison]::OrdinalIgnoreCase))) {
            throw "External backup root must remain under $allowedExternalBackup"
        }
    }
    $full
}

function Get-Claims([string]$Path) {
    $claims = [ordered]@{
        F1 = [Collections.Generic.List[object]]::new()
        F2 = [Collections.Generic.List[object]]::new()
        F3 = [Collections.Generic.List[object]]::new()
        E2aa = [Collections.Generic.List[object]]::new()
    }
    foreach ($ini in Get-ChildItem -LiteralPath $Path -Recurse -File -Filter '*.ini' | Sort-Object FullName) {
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

function Assert-Fingerprints([string]$Path, [object]$Baseline) {
    if (Test-Path -LiteralPath (Join-Path $Path 'RebirthEffectsDX11.ini') -PathType Leaf) {
        throw 'Active Rebirth owner appeared; standalone topology no longer applies.'
    }
    foreach ($item in @($Baseline.disabledRebirthOwner, $Baseline.generatedIni)) {
        $file = Join-Path $Path ([string]$item.name)
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Live baseline file is missing: $file" }
        $actual = Get-Hash $file
        if ($actual -ne [string]$item.sha256) { throw "Live baseline fingerprint drifted: $($item.name). Expected $($item.sha256), found $actual" }
    }
}

function Assert-Baseline([string]$Path, [object]$Baseline) {
    Assert-Fingerprints $Path $Baseline
    $claims = Get-Claims $Path
    foreach ($name in @('F1','F2','F3','E2aa')) {
        if ($claims[$name].Count -ne 0) { throw "Standalone baseline requires zero $name claims: $($claims[$name] | ConvertTo-Json -Compress)" }
    }
    $agent2 = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Filter 'Agent2R3DSSGI*')
    if ($agent2.Count -ne 0) { throw "Standalone baseline already contains Agent 2 files: $($agent2.FullName -join ', ')" }
}

function Assert-Staged([string]$Path, [object]$Baseline, [string]$IniPath) {
    Assert-Fingerprints $Path $Baseline
    $claims = Get-Claims $Path
    if ($claims.F1.Count -ne 0 -or $claims.F2.Count -ne 1 -or $claims.F3.Count -ne 0 -or $claims.E2aa.Count -ne 1) {
        throw "Standalone staged claims are invalid: $($claims | ConvertTo-Json -Depth 6 -Compress)"
    }
    if (-not [string]::Equals($claims.F2[0].path, $IniPath, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($claims.E2aa[0].path, $IniPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Standalone F2 and e2aa claims are not owned by Agent2R3DSSGITest.ini.'
    }
}

function Test-InstalledFiles([object[]]$Files) {
    foreach ($file in $Files) {
        if (-not (Test-Path -LiteralPath $file.destination -PathType Leaf) -or
            (Get-Hash $file.destination) -ne [string]$file.sha256) { return $false }
    }
    $true
}

function Test-RemovedFiles([object[]]$Files) {
    foreach ($file in $Files) {
        if (Test-Path -LiteralPath $file.destination -PathType Leaf) { return $false }
    }
    $true
}

$manifestFull = Resolve-WorkspaceFile $PackManifest
$packRoot = [IO.Path]::GetDirectoryName($manifestFull)
$manifest = Get-Content -Raw -LiteralPath $manifestFull | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.result -ne 'pass' -or
    $manifest.classification -ne 'offline-f2-standalone-live-topology-candidate' -or
    $manifest.target.shader -ne 'e2aa1c8cb39e0a55' -or $manifest.target.activeOwnerRequired -ne $false -or
    $manifest.baseline.activeRebirthOwnerPresent -ne $false -or
    $manifest.controls.F1 -ne 'reserved and unbound' -or
    $manifest.controls.F2 -ne 'standalone SSGI candidate off/on' -or
    $manifest.controls.F3 -ne 'current live unbound state preserved' -or
    $manifest.policy.exactLiveBaselineRequired -ne $true -or
    $manifest.policy.activatesDisabledOwner -ne $false -or
    $manifest.policy.runtimeEligible -ne $false -or $manifest.policy.installed -ne $false -or
    $manifest.policy.gameFilesTouched -ne $false) {
    throw 'Pack manifest is not the reviewed standalone live-topology contract.'
}

$payloads = [Collections.Generic.List[object]]::new()
foreach ($entry in @($manifest.files)) {
    $relative = ([string]$entry.path).Replace('/', '\')
    if ($relative -notmatch '^Mods\\[^\\]+$') { throw "Unsafe standalone payload path: $relative" }
    $name = [IO.Path]::GetFileName($relative)
    $source = [IO.Path]::GetFullPath((Join-Path $packRoot $relative))
    if (-not $source.StartsWith($packRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $source -PathType Leaf) -or
        (Get-Hash $source) -ne [string]$entry.sha256) {
        throw "Standalone payload validation failed: $relative"
    }
    $payloads.Add([ordered]@{name=$name; source=$source; sha256=[string]$entry.sha256})
}
$actualNames = @($payloads | ForEach-Object {$_.name} | Sort-Object)
if ($actualNames.Count -ne $expectedPayloadNames.Count -or @((Compare-Object $expectedPayloadNames $actualNames)).Count) {
    throw "Standalone payload inventory is not the exact seven-file set: $($actualNames -join ', ')"
}

$target = Resolve-Target $TargetModsDirectory
$backup = Resolve-Backup $BackupRoot
$statePath = Join-Path $backup 'active-state.json'
$standaloneIni = Join-Path $target 'Agent2R3DSSGITest.ini'

if ($Action -eq 'Status') {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        Assert-Baseline $target $manifest.baseline
        [pscustomobject]@{Status='not-staged'; Target=$target; State=$statePath; Installed=$false; Baseline='exact'}
        return
    }
    $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    if ($state.packageId -ne $packageId -or -not [string]::Equals($state.targetRoot, $target, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Standalone state does not match this package and target.'
    }
    $status = if ($state.status -eq 'staged' -and (Test-InstalledFiles @($state.files))) {
        try { Assert-Staged $target $manifest.baseline $standaloneIni; 'staged' } catch { 'drifted' }
    } elseif ($state.status -eq 'restored' -and (Test-RemovedFiles @($state.files))) {
        try { Assert-Baseline $target $manifest.baseline; 'restored' } catch { 'drifted' }
    } else {
        'drifted'
    }
    [pscustomobject]@{Status=$status; Target=$target; State=$statePath; Installed=($status -eq 'staged'); Files=@($state.files).Count}
    return
}

if ($Action -eq 'Stage') {
    if (-not $AcknowledgeOfflineCandidate) {
        throw 'Stage requires -AcknowledgeOfflineCandidate; live parse, visuals, and GPU timing remain unverified.'
    }
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $existing = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
        throw "A standalone staging state already exists with status '$($existing.status)': $statePath"
    }
    Assert-Baseline $target $manifest.baseline
    if (-not $PSCmdlet.ShouldProcess($target, 'Stage seven new standalone Agent 2 SSGI files with exact removal rollback')) { return }

    [IO.Directory]::CreateDirectory($backup) | Out-Null
    $snapshot = Join-Path $backup (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
    [IO.Directory]::CreateDirectory($snapshot) | Out-Null
    $baselineBackups = [Collections.Generic.List[object]]::new()
    foreach ($item in @($manifest.baseline.disabledRebirthOwner, $manifest.baseline.generatedIni)) {
        $source = Join-Path $target ([string]$item.name)
        $destination = Join-Path $snapshot ([string]$item.name)
        [IO.File]::Copy($source, $destination, $false)
        if ((Get-Hash $destination) -ne [string]$item.sha256) { throw "Baseline evidence backup failed: $($item.name)" }
        $baselineBackups.Add([ordered]@{name=[string]$item.name; path=$destination; sha256=[string]$item.sha256})
    }
    $records = @($payloads | ForEach-Object {
        [ordered]@{relativePath=$_.name; source=$_.source; destination=(Join-Path $target $_.name); sha256=$_.sha256}
    })
    $state = [ordered]@{
        schemaVersion = 1
        packageId = $packageId
        status = 'staging'
        stagedAtUtc = [DateTime]::UtcNow.ToString('o')
        targetRoot = $target
        packManifest = $manifestFull
        packManifestSha256 = Get-Hash $manifestFull
        snapshotRoot = $snapshot
        baselineBackups = @($baselineBackups)
        files = @($records)
    }
    Write-Json $statePath $state
    try {
        foreach ($record in $records) {
            [IO.File]::Copy($record.source, $record.destination, $false)
            if ((Get-Hash $record.destination) -ne $record.sha256) { throw "Post-stage hash mismatch: $($record.relativePath)" }
        }
        Assert-Staged $target $manifest.baseline $standaloneIni
        $state.status = 'staged'
        Write-Json $statePath $state
    } catch {
        $failure = $_
        foreach ($record in $records) {
            if (Test-Path -LiteralPath $record.destination -PathType Leaf) { [IO.File]::Delete($record.destination) }
        }
        $state.status = if (Test-RemovedFiles @($records)) {'automatic-rollback-after-stage-failure'} else {'automatic-rollback-incomplete'}
        Write-Json $statePath $state
        if ($state.status -eq 'automatic-rollback-incomplete') {
            throw "Standalone Stage failed and exact cleanup could not be verified. State: $statePath. Initial failure: $($failure.Exception.Message)"
        }
        throw $failure
    }
    [pscustomobject]@{Status='staged'; Target=$target; State=$statePath; Backup=$snapshot; Installed=$true; Files=$records.Count; ReloadRequired=$true; RuntimeEligible=$false}
    return
}

if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw "No standalone staging state exists to restore: $statePath" }
$restoreState = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
if ($restoreState.packageId -ne $packageId -or $restoreState.status -ne 'staged') {
    throw "Only this package's staged state can be restored; current status is '$($restoreState.status)'."
}
if (-not [string]::Equals($restoreState.targetRoot, $target, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Standalone state target does not match the requested target.'
}
if (-not (Test-InstalledFiles @($restoreState.files))) {
    throw 'Restore refused because a standalone staged file drifted.'
}
Assert-Staged $target $manifest.baseline $standaloneIni
foreach ($item in @($restoreState.baselineBackups)) {
    if (-not (Test-Path -LiteralPath $item.path -PathType Leaf) -or (Get-Hash $item.path) -ne [string]$item.sha256) {
        throw "Baseline evidence backup is invalid: $($item.name)"
    }
}
if (-not $PSCmdlet.ShouldProcess($target, 'Remove the seven exact standalone Agent 2 files and return to the fingerprinted baseline')) { return }
try {
    foreach ($record in @($restoreState.files)) { [IO.File]::Delete($record.destination) }
    if (-not (Test-RemovedFiles @($restoreState.files))) { throw 'Standalone files remain after Restore.' }
    Assert-Baseline $target $manifest.baseline
    $restoreState.status = 'restored'
    $restoreState | Add-Member -NotePropertyName restoredAtUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    Write-Json $statePath $restoreState
} catch {
    $failure = $_
    foreach ($record in @($restoreState.files)) { [IO.File]::Copy($record.source, $record.destination, $true) }
    if (-not (Test-InstalledFiles @($restoreState.files))) {
        $restoreState.status = 'restore-failure-recovery-incomplete'
        Write-Json $statePath $restoreState
        throw "Standalone Restore failed and the staged state could not be re-established exactly. State: $statePath. Initial failure: $($failure.Exception.Message)"
    }
    throw $failure
}
[pscustomobject]@{Status='restored'; Target=$target; State=$statePath; Backup=$restoreState.snapshotRoot; Installed=$false; Files=@($restoreState.files).Count; ReloadRequired=$true}
