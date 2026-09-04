[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Stage','Status','Restore')]
    [string]$Action,
    [string]$PackManifest = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-rebirth-fallback-consumer-f2-test-pack\manifest.json'),
    [Parameter(Mandatory)]
    [string]$TargetModsDirectory,
    [string]$BackupRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-ao-f2-standalone-backups'),
    [switch]$AllowExternalTarget,
    [switch]$AllowExternalBackupRoot,
    [switch]$AllowRunningGame
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
    $external = -not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)
    if ($external) {
        if (-not $AllowExternalTarget) { throw "External target requires -AllowExternalTarget: $full" }
        if (-not $full.EndsWith('\End\Binaries\Win64\Mods', [StringComparison]::OrdinalIgnoreCase)) { throw "External target must be an exact FF7 Remake Win64 Mods directory: $full" }
    }
    [ordered]@{ Path=$full; External=$external }
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
            if ($line -match '(?i)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F2(?![A-Z0-9_]).*$') { $f2.Add([ordered]@{path=$ini.FullName;line=$lineNumber;text=$line.Trim()}) }
            if ($line -match '(?i)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$') { $e2aa.Add([ordered]@{path=$ini.FullName;line=$lineNumber;text=$line.Trim()}) }
        }
    }
    [ordered]@{ F2=@($f2); E2aa=@($e2aa) }
}

$manifestFull = Resolve-WorkspaceFile $PackManifest
$manifest = Get-Content -Raw -LiteralPath $manifestFull | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.effect -ne 'rebirth-native-ssao-fallback-consumer-f2-test' -or
    $manifest.shaderHash -ne 'e2aa1c8cb39e0a55' -or $manifest.status -ne 'offline-staging-pack-not-installed' -or
    $manifest.runtimeEligible -ne $false -or $manifest.installationPerformed -ne $false) {
    throw 'Pack manifest is not the reviewed standalone F2 contract.'
}
$packIni = Resolve-WorkspaceFile $manifest.ini
$packShader = Resolve-WorkspaceFile $manifest.shader
if ((Get-Hash $packIni) -ne $manifest.iniSha256 -or (Get-Hash $packShader) -ne $manifest.shaderSha256) { throw 'Standalone pack artifact hash mismatch.' }

$target = Resolve-TargetDirectory $TargetModsDirectory
$targetRoot = $target.Path
$backupFull = Resolve-BackupDirectory $BackupRoot
$statePath = Join-Path $backupFull 'active-state.json'
$iniDestination = Join-Path $targetRoot ([IO.Path]::GetFileName($packIni))
$shaderDestination = Join-Path $targetRoot ([IO.Path]::GetFileName($packShader))

if ($Action -eq 'Status') {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        [pscustomobject]@{Status='not-staged';Target=$targetRoot;State=$statePath;Installed=$false}
        return
    }
    $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    if (-not [string]::Equals($state.targetRoot,$targetRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'State target does not match requested target.' }
    $iniHash = if(Test-Path -LiteralPath $iniDestination -PathType Leaf){Get-Hash $iniDestination}else{$null}
    $shaderHash = if(Test-Path -LiteralPath $shaderDestination -PathType Leaf){Get-Hash $shaderDestination}else{$null}
    $installed = $iniHash -eq $state.installed.iniSha256 -and $shaderHash -eq $state.installed.shaderSha256
    $restored = (($state.before.iniExisted -and $iniHash -eq $state.before.iniSha256) -or (-not $state.before.iniExisted -and $null -eq $iniHash)) -and
        (($state.before.shaderExisted -and $shaderHash -eq $state.before.shaderSha256) -or (-not $state.before.shaderExisted -and $null -eq $shaderHash))
    $status = if($state.status -eq 'staged' -and $installed){'staged'}elseif($state.status -eq 'restored' -and $restored){'restored'}else{'drifted'}
    [pscustomobject]@{Status=$status;Target=$targetRoot;State=$statePath;Installed=($status -eq 'staged');IniSha256=$iniHash;ShaderSha256=$shaderHash}
    return
}

if ($Action -eq 'Stage') {
    if ($target.External -and -not $AllowRunningGame -and @(Get-Process -Name 'ff7remake_' -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'External stage refused while FF7 Remake is running. Close the game or pass -AllowRunningGame after explicit review.'
    }
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $existing = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
        throw "A standalone staging state already exists with status '$($existing.status)': $statePath"
    }
    $claims = Get-Claims $targetRoot
    if ($claims.F2.Count -ne 0 -or $claims.E2aa.Count -ne 0) { throw "Standalone stage requires zero existing F2 and e2aa claims: $($claims | ConvertTo-Json -Compress)" }
    New-Item -ItemType Directory -Path $backupFull -Force | Out-Null
    $snapshotRoot = Join-Path $backupFull (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
    New-Item -ItemType Directory -Path $snapshotRoot -Force | Out-Null
    $iniExisted = Test-Path -LiteralPath $iniDestination -PathType Leaf
    $shaderExisted = Test-Path -LiteralPath $shaderDestination -PathType Leaf
    $iniBeforeHash = if($iniExisted){Get-Hash $iniDestination}else{$null}
    $shaderBeforeHash = if($shaderExisted){Get-Hash $shaderDestination}else{$null}
    $iniBackup = if($iniExisted){Join-Path $snapshotRoot 'test.ini.before'}else{$null}
    $shaderBackup = if($shaderExisted){Join-Path $snapshotRoot 'candidate.hlsl.before'}else{$null}
    if($iniExisted){Copy-Item -LiteralPath $iniDestination -Destination $iniBackup}
    if($shaderExisted){Copy-Item -LiteralPath $shaderDestination -Destination $shaderBackup}
    $state = [ordered]@{
        schemaVersion=1;status='staging';stagedAt=(Get-Date).ToUniversalTime().ToString('o');targetRoot=$targetRoot
        packManifest=$manifestFull;packManifestSha256=Get-Hash $manifestFull;snapshotRoot=$snapshotRoot
        destinations=[ordered]@{ini=$iniDestination;shader=$shaderDestination}
        backups=[ordered]@{ini=$iniBackup;shader=$shaderBackup}
        before=[ordered]@{iniExisted=$iniExisted;iniSha256=$iniBeforeHash;shaderExisted=$shaderExisted;shaderSha256=$shaderBeforeHash}
        installed=[ordered]@{iniSha256=$manifest.iniSha256;shaderSha256=$manifest.shaderSha256}
    }
    try {
        Copy-Item -LiteralPath $packIni -Destination $iniDestination -Force
        Copy-Item -LiteralPath $packShader -Destination $shaderDestination -Force
        if((Get-Hash $iniDestination) -ne $state.installed.iniSha256 -or (Get-Hash $shaderDestination) -ne $state.installed.shaderSha256){throw 'Post-stage hash verification failed.'}
        $post = Get-Claims $targetRoot
        if($post.F2.Count -ne 1 -or $post.E2aa.Count -ne 1){throw 'Post-stage standalone ownership verification failed.'}
        $state.status='staged'
        Write-Json $statePath $state
    } catch {
        if($iniExisted){Copy-Item -LiteralPath $iniBackup -Destination $iniDestination -Force}elseif(Test-Path -LiteralPath $iniDestination){Remove-Item -LiteralPath $iniDestination -Force}
        if($shaderExisted){Copy-Item -LiteralPath $shaderBackup -Destination $shaderDestination -Force}elseif(Test-Path -LiteralPath $shaderDestination){Remove-Item -LiteralPath $shaderDestination -Force}
        throw
    }
    [pscustomobject]@{Status='staged';Target=$targetRoot;State=$statePath;Backup=$snapshotRoot;Installed=$true;IniSha256=Get-Hash $iniDestination;ShaderSha256=Get-Hash $shaderDestination}
    return
}

if(-not (Test-Path -LiteralPath $statePath -PathType Leaf)){throw "No standalone staging state exists to restore: $statePath"}
$restoreState=Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
if($restoreState.status -ne 'staged'){throw "Only a staged state can be restored; current status is '$($restoreState.status)'."}
if(-not [string]::Equals($restoreState.targetRoot,$targetRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'State target does not match requested target.'}
if((Get-Hash $iniDestination) -ne $restoreState.installed.iniSha256 -or (Get-Hash $shaderDestination) -ne $restoreState.installed.shaderSha256){throw 'Restore refused because a staged destination drifted after installation.'}
if($restoreState.before.iniExisted -and (Get-Hash $restoreState.backups.ini) -ne $restoreState.before.iniSha256){throw 'INI backup hash is invalid.'}
if($restoreState.before.shaderExisted -and (Get-Hash $restoreState.backups.shader) -ne $restoreState.before.shaderSha256){throw 'Shader backup hash is invalid.'}
if($restoreState.before.iniExisted){Copy-Item -LiteralPath $restoreState.backups.ini -Destination $iniDestination -Force}else{Remove-Item -LiteralPath $iniDestination -Force}
if($restoreState.before.shaderExisted){Copy-Item -LiteralPath $restoreState.backups.shader -Destination $shaderDestination -Force}else{Remove-Item -LiteralPath $shaderDestination -Force}
$restoreState.status='restored'
$restoreState | Add-Member -NotePropertyName restoredAt -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('o')) -Force
Write-Json $statePath $restoreState
[pscustomobject]@{Status='restored';Target=$targetRoot;State=$statePath;Backup=$restoreState.snapshotRoot;Installed=$false}
