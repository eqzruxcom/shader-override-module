[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Stage','Status','Restore')]
    [string]$Action,
    [string]$PackManifest = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-rebirth-fallback-consumer-f2-owner-integration-pack\manifest.json'),
    [Parameter(Mandatory)]
    [string]$TargetModsDirectory,
    [string]$BackupRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-ao-f2-stage-backups'),
    [switch]$AllowExternalTarget,
    [switch]$AllowExternalBackupRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$agent2ExternalBackupRoot = 'F:\Shader3Dmigoto\Agent 2'

function Resolve-WorkspaceFile([string]$Path) {
    $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $repoRoot $Path)) }
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Pack file must remain inside the project workspace: $full" }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Required pack file does not exist: $full" }
    $full
}
function Resolve-TargetDirectory([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw "Target Mods directory does not exist: $full" }
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
        $allowed = [IO.Path]::GetFullPath($agent2ExternalBackupRoot).TrimEnd('\')
        if (-not ($full.Equals($allowed, [StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase))) {
            throw "External backup root must remain under $agent2ExternalBackupRoot"
        }
    }
    $full
}
function Get-Hash([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash }
function Write-Json([string]$Path, [object]$Value) {
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 16) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}
function Get-Claims([string]$Root) {
    $f2 = [Collections.Generic.List[object]]::new()
    $e2aa = [Collections.Generic.List[object]]::new()
    foreach ($ini in Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ini' | Sort-Object FullName) {
        $lineNumber = 0
        foreach ($line in Get-Content -LiteralPath $ini.FullName) {
            $lineNumber++
            if ($line -match '^\s*;') { continue }
            if ($line -match '(?i)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F2(?![A-Z0-9_]).*$') {
                $f2.Add([ordered]@{path=$ini.FullName;line=$lineNumber;text=$line.Trim()})
            }
            if ($line -match '(?i)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$') {
                $e2aa.Add([ordered]@{path=$ini.FullName;line=$lineNumber;text=$line.Trim()})
            }
        }
    }
    [ordered]@{ F2=@($f2); E2aa=@($e2aa) }
}

$manifestFull = Resolve-WorkspaceFile $PackManifest
$manifest = Get-Content -Raw -LiteralPath $manifestFull | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.effect -ne 'rebirth-native-ssao-fallback-consumer-f2-owner-integration' -or
    $manifest.shaderHash -ne 'e2aa1c8cb39e0a55' -or $manifest.status -ne 'offline-owner-integration-preview-not-installed' -or
    $manifest.runtimeEligible -ne $false -or $manifest.installationPerformed -ne $false) {
    throw 'Pack manifest is not the reviewed offline owner-integration contract.'
}
$packIni = Resolve-WorkspaceFile $manifest.patchedIni
$packShader = Resolve-WorkspaceFile $manifest.shader
if ((Get-Hash $packIni) -ne $manifest.patchedIniSha256) { throw 'Pack INI hash does not match its manifest.' }
if ((Get-Hash $packShader) -ne $manifest.shaderSha256) { throw 'Pack shader hash does not match its manifest.' }

$targetRoot = Resolve-TargetDirectory $TargetModsDirectory
$backupFull = Resolve-BackupDirectory $BackupRoot
$statePath = Join-Path $backupFull 'active-state.json'
$ownerDestination = Join-Path $targetRoot 'RebirthEffectsDX11.ini'
$shaderDestination = Join-Path $targetRoot ([IO.Path]::GetFileName($packShader))

if ($Action -eq 'Status') {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        [pscustomobject]@{ Status='not-staged'; Target=$targetRoot; State=$statePath; Installed=$false }
        return
    }
    $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    if (-not [string]::Equals($state.targetRoot, $targetRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'State target does not match requested target.' }
    $ownerHash = if (Test-Path -LiteralPath $ownerDestination -PathType Leaf) { Get-Hash $ownerDestination } else { $null }
    $shaderHash = if (Test-Path -LiteralPath $shaderDestination -PathType Leaf) { Get-Hash $shaderDestination } else { $null }
    $matchesInstalled = $ownerHash -eq $state.installed.ownerSha256 -and $shaderHash -eq $state.installed.shaderSha256
    $matchesRestored = $ownerHash -eq $state.before.ownerSha256 -and (
        ($state.before.shaderExisted -and $shaderHash -eq $state.before.shaderSha256) -or
        (-not $state.before.shaderExisted -and $null -eq $shaderHash)
    )
    $status = if ($state.status -eq 'staged' -and $matchesInstalled) { 'staged' } elseif ($state.status -eq 'restored' -and $matchesRestored) { 'restored' } else { 'drifted' }
    [pscustomobject]@{ Status=$status; Target=$targetRoot; State=$statePath; Installed=($status -eq 'staged'); OwnerSha256=$ownerHash; ShaderSha256=$shaderHash }
    return
}

if ($Action -eq 'Stage') {
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $existingState = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
        throw "A staging state already exists with status '$($existingState.status)': $statePath"
    }
    if (-not (Test-Path -LiteralPath $ownerDestination -PathType Leaf)) { throw "Target owner INI is missing: $ownerDestination" }
    $ownerBeforeHash = Get-Hash $ownerDestination
    if ($ownerBeforeHash -ne $manifest.existingOwner.exactSha256) {
        throw "Target owner SHA changed. Expected $($manifest.existingOwner.exactSha256), found $ownerBeforeHash"
    }
    $claims = Get-Claims $targetRoot
    if ($claims.F2.Count -ne 0) { throw "Target already claims F2: $($claims.F2 | ConvertTo-Json -Compress)" }
    if ($claims.E2aa.Count -ne 1 -or -not [string]::Equals($claims.E2aa[0].path, $ownerDestination, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Target must have exactly one e2aa owner in RebirthEffectsDX11.ini: $($claims.E2aa | ConvertTo-Json -Compress)"
    }

    New-Item -ItemType Directory -Path $backupFull -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $snapshotRoot = Join-Path $backupFull $stamp
    New-Item -ItemType Directory -Path $snapshotRoot -Force | Out-Null
    $ownerBackup = Join-Path $snapshotRoot 'RebirthEffectsDX11.ini.before'
    $shaderBackup = Join-Path $snapshotRoot 'RebirthFallbackAOConsumer_ps.hlsl.before'
    Copy-Item -LiteralPath $ownerDestination -Destination $ownerBackup
    $shaderExisted = Test-Path -LiteralPath $shaderDestination -PathType Leaf
    $shaderBeforeHash = $null
    if ($shaderExisted) {
        $shaderBeforeHash = Get-Hash $shaderDestination
        Copy-Item -LiteralPath $shaderDestination -Destination $shaderBackup
    }
    $state = [ordered]@{
        schemaVersion = 1
        status = 'staging'
        stagedAt = (Get-Date).ToUniversalTime().ToString('o')
        targetRoot = $targetRoot
        packManifest = $manifestFull
        packManifestSha256 = Get-Hash $manifestFull
        snapshotRoot = $snapshotRoot
        destinations = [ordered]@{ owner=$ownerDestination; shader=$shaderDestination }
        backups = [ordered]@{ owner=$ownerBackup; shader=if($shaderExisted){$shaderBackup}else{$null} }
        before = [ordered]@{ ownerSha256=$ownerBeforeHash; shaderExisted=$shaderExisted; shaderSha256=$shaderBeforeHash }
        installed = [ordered]@{ ownerSha256=$manifest.patchedIniSha256; shaderSha256=$manifest.shaderSha256 }
    }
    try {
        Copy-Item -LiteralPath $packIni -Destination $ownerDestination -Force
        Copy-Item -LiteralPath $packShader -Destination $shaderDestination -Force
        if ((Get-Hash $ownerDestination) -ne $state.installed.ownerSha256 -or (Get-Hash $shaderDestination) -ne $state.installed.shaderSha256) {
            throw 'Post-stage hash verification failed.'
        }
        $postClaims = Get-Claims $targetRoot
        if ($postClaims.F2.Count -ne 1 -or $postClaims.E2aa.Count -ne 1) { throw 'Post-stage F2/e2aa ownership verification failed.' }
        $state.status = 'staged'
        Write-Json $statePath $state
    } catch {
        Copy-Item -LiteralPath $ownerBackup -Destination $ownerDestination -Force
        if ($shaderExisted) { Copy-Item -LiteralPath $shaderBackup -Destination $shaderDestination -Force }
        elseif (Test-Path -LiteralPath $shaderDestination -PathType Leaf) { Remove-Item -LiteralPath $shaderDestination -Force }
        throw
    }
    [pscustomobject]@{ Status='staged'; Target=$targetRoot; State=$statePath; Backup=$snapshotRoot; Installed=$true; OwnerSha256=Get-Hash $ownerDestination; ShaderSha256=Get-Hash $shaderDestination }
    return
}

if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw "No staging state exists to restore: $statePath" }
$restoreState = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
if ($restoreState.status -ne 'staged') { throw "Only a staged state can be restored; current status is '$($restoreState.status)'." }
if (-not [string]::Equals($restoreState.targetRoot, $targetRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'State target does not match requested target.' }
if ((Get-Hash $ownerDestination) -ne $restoreState.installed.ownerSha256 -or (Get-Hash $shaderDestination) -ne $restoreState.installed.shaderSha256) {
    throw 'Restore refused because a staged destination drifted after installation.'
}
if ((Get-Hash $restoreState.backups.owner) -ne $restoreState.before.ownerSha256) { throw 'Owner backup hash is invalid.' }
if ($restoreState.before.shaderExisted -and (Get-Hash $restoreState.backups.shader) -ne $restoreState.before.shaderSha256) { throw 'Shader backup hash is invalid.' }

Copy-Item -LiteralPath $restoreState.backups.owner -Destination $ownerDestination -Force
if ($restoreState.before.shaderExisted) {
    Copy-Item -LiteralPath $restoreState.backups.shader -Destination $shaderDestination -Force
} else {
    Remove-Item -LiteralPath $shaderDestination -Force
}
if ((Get-Hash $ownerDestination) -ne $restoreState.before.ownerSha256) { throw 'Restored owner hash verification failed.' }
if ($restoreState.before.shaderExisted) {
    if ((Get-Hash $shaderDestination) -ne $restoreState.before.shaderSha256) { throw 'Restored shader hash verification failed.' }
} elseif (Test-Path -LiteralPath $shaderDestination -PathType Leaf) {
    throw 'New staged shader still exists after restore.'
}
$restoreState.status = 'restored'
$restoreState | Add-Member -NotePropertyName restoredAt -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('o')) -Force
Write-Json $statePath $restoreState
[pscustomobject]@{ Status='restored'; Target=$targetRoot; State=$statePath; Backup=$restoreState.snapshotRoot; Installed=$false; OwnerSha256=Get-Hash $ownerDestination }
