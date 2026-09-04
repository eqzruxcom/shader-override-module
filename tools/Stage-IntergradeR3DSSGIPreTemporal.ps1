[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][ValidateSet('Stage','Status','Restore')][string]$Action,
    [Parameter(Mandatory)][string]$TargetWin64Directory,
    [string]$PackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-pre-temporal-pack'),
    [string]$WorkingPackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-late-scene-pack'),
    [string]$BackupRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-pre-temporal-stage-backups'),
    [switch]$AllowExternalTarget,
    [switch]$AcknowledgeOfflineCandidate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$target = [IO.Path]::GetFullPath($TargetWin64Directory).TrimEnd('\')
$pack = [IO.Path]::GetFullPath($PackRoot).TrimEnd('\')
$working = [IO.Path]::GetFullPath($WorkingPackRoot).TrimEnd('\')
$backup = [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')
$packageId = 'agent2-r3d-ssgi-pre-temporal-c473-v1'
$af6Relative = 'ShaderFixes\af6cd28a0108a18a-ps.txt'
$expectedNames = @(
    'Agent2R3DSSGICompositeE2AA_ps.hlsl','Agent2R3DSSGIDenoise16_ps.hlsl','Agent2R3DSSGIDenoise2_ps.hlsl',
    'Agent2R3DSSGIDenoise4_ps.hlsl','Agent2R3DSSGIDenoise8_ps.hlsl','Agent2R3DSSGIFullscreen_vs.hlsl',
    'Agent2R3DSSGITest.ini','Agent2R3DSSGITraceE2AA_ps.hlsl'
)

function Get-Hash([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash }
function Write-Json([string]$Path,[object]$Value) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path)))
    [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 16)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
}
function Get-KeyClaims([string]$Mods,[string]$Pattern) {
    @(
        foreach($ini in @(Get-ChildItem -LiteralPath $Mods -File -Filter '*.ini'|Sort-Object Name)) {
            $n=0
            foreach($line in [IO.File]::ReadLines($ini.FullName)) {
                $n++
                if($line -notmatch '^\s*;' -and $line -match '^\s*key\s*=' -and $line -match $Pattern) {
                    [ordered]@{path=$ini.FullName;line=$n;text=$line.Trim()}
                }
            }
        }
    )
}
function Get-HashClaims([string]$Mods,[string]$Hash) {
    @(
        foreach($ini in @(Get-ChildItem -LiteralPath $Mods -File -Filter '*.ini'|Sort-Object Name)) {
            $n=0
            foreach($line in [IO.File]::ReadLines($ini.FullName)) {
                $n++
                if($line -match "(?i)^\s*hash\s*=\s*$Hash\s*$") {[ordered]@{path=$ini.FullName;line=$n}}
            }
        }
    )
}
function Test-Phase([object[]]$Records,[string]$Phase) {
    foreach($record in $Records) {
        $wanted=$record.$Phase
        $exists=Test-Path -LiteralPath $record.destination -PathType Leaf
        if([bool]$wanted.existed) {
            if(-not $exists -or (Get-Hash $record.destination) -ne [string]$wanted.sha256){return $false}
        } elseif($exists){return $false}
    }
    $true
}

$externalTarget = -not $target.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)
if($externalTarget) {
    if(-not $AllowExternalTarget){throw "External target requires -AllowExternalTarget: $target"}
    if(-not $target.EndsWith('\End\Binaries\Win64',[StringComparison]::OrdinalIgnoreCase)){throw "External target must be an exact FF7 Remake End\Binaries\Win64 directory: $target"}
}
if(-not $backup.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'BackupRoot must remain inside the workspace.'}
$mods=Join-Path $target 'Mods'
$fixes=Join-Path $target 'ShaderFixes'
foreach($directory in @($target,$mods,$fixes)){if(-not(Test-Path -LiteralPath $directory -PathType Container)){throw "Required target directory is missing: $directory"}}

$manifestPath=Join-Path $pack 'manifest.json'
$workingManifestPath=Join-Path $working 'manifest.json'
foreach($path in @($manifestPath,$workingManifestPath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Required manifest is missing: $path"}}
$manifest=Get-Content -Raw -LiteralPath $manifestPath|ConvertFrom-Json
$workingManifest=Get-Content -Raw -LiteralPath $workingManifestPath|ConvertFrom-Json
if($manifest.schemaVersion -ne 1 -or $manifest.result -ne 'pass' -or $manifest.variant -ne 'pre-temporal-native-c473-input' -or
   [bool]$manifest.runtimeEligible -or [bool]$manifest.installed -or [bool]$manifest.validation.nativeTemporalReplacementIncluded -or
   [bool]$manifest.validation.nativeLateSceneReplacementIncluded -or -not [bool]$manifest.validation.feedbackSourceAbsent -or
   $manifest.hooks.temporalResolve -ne 'c473ab75b7519f7e-ps' -or $manifest.controls.F10 -ne 'native reload, unchanged'){
    throw 'Pre-temporal pack manifest failed its closed contract.'
}
if($workingManifest.schemaVersion -ne 1 -or $workingManifest.result -ne 'pass' -or $workingManifest.variant -ne 'late-scene-native-af6cd-writeback' -or -not [bool]$workingManifest.validation.feedbackSourceAbsent){
    throw 'Working late-scene predecessor manifest failed its closed contract.'
}

$candidate=@{}
foreach($entry in @($manifest.files)){
    $name=[string]$entry.name
    $source=Join-Path (Join-Path $pack 'Mods') $name
    if(-not(Test-Path -LiteralPath $source -PathType Leaf) -or (Get-Hash $source) -ne [string]$entry.sha256){throw "Pre-temporal payload is missing or drifted: $name"}
    $candidate[$name]=[ordered]@{source=$source;sha256=[string]$entry.sha256}
}
if((@($candidate.Keys|Sort-Object)-join '|') -ne (@($expectedNames|Sort-Object)-join '|')){throw 'Pre-temporal payload inventory changed.'}
$predecessor=@{}
foreach($entry in @($workingManifest.payloadFiles)){
    $relative=([string]$entry.relativePath).Replace('/','\')
    $predecessor[$relative]=[ordered]@{source=(Join-Path $working $relative);sha256=[string]$entry.sha256}
}
foreach($relative in @($expectedNames|ForEach-Object{'Mods\'+$_})+@($af6Relative)){
    if(-not $predecessor.ContainsKey($relative)){throw "Working predecessor inventory lacks $relative"}
    $record=$predecessor[$relative]
    if(-not(Test-Path -LiteralPath $record.source -PathType Leaf) -or (Get-Hash $record.source) -ne $record.sha256){throw "Working predecessor payload drifted: $relative"}
}

$candidateText=[IO.File]::ReadAllText((Join-Path $pack 'Mods\Agent2R3DSSGITest.ini'))
if([regex]::Matches($candidateText,'(?im)^\s*key\s*=.*(?<![A-Z0-9_])F2(?![A-Z0-9_]).*$').Count -ne 1 -or
   $candidateText -match '(?im)^\s*key\s*=.*(?:F10|VK_PRIOR|VK_NEXT).*$' -or
   [regex]::Matches($candidateText,'(?im)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$').Count -ne 1 -or
   [regex]::Matches($candidateText,'(?im)^\s*hash\s*=\s*c473ab75b7519f7e\s*$').Count -ne 1 -or
   $candidateText -match '(?im)^\s*hash\s*=\s*af6cd28a0108a18a\s*$'){throw 'Candidate key or hook claims changed.'}

$statePath=Join-Path $backup 'active-state.json'
if($Action -eq 'Status'){
    if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){[pscustomobject]@{Status='not-staged';Installed=$false;Target=$target;State=$statePath};return}
    $state=Get-Content -Raw -LiteralPath $statePath|ConvertFrom-Json
    if($state.packageId -ne $packageId -or -not[string]::Equals($state.target,$target,[StringComparison]::OrdinalIgnoreCase)){throw 'State belongs to another package or target.'}
    $status=if($state.status -eq 'staged' -and (Test-Phase @($state.files) 'after')){'staged'}elseif($state.status -eq 'restored' -and (Test-Phase @($state.files) 'before')){'restored'}else{'drifted'}
    [pscustomobject]@{Status=$status;Installed=($status -eq 'staged');Target=$target;State=$statePath;Files=@($state.files).Count};return
}

if($Action -eq 'Stage'){
    if(-not $AcknowledgeOfflineCandidate){throw 'Stage requires -AcknowledgeOfflineCandidate because live visual and timing gates remain open.'}
    if(Test-Path -LiteralPath $statePath){throw "A staging state already exists: $statePath"}
    foreach($name in $expectedNames){
        $relative='Mods\'+$name;$live=Join-Path $target $relative
        if(-not(Test-Path -LiteralPath $live -PathType Leaf) -or (Get-Hash $live) -ne $predecessor[$relative].sha256){throw "Live predecessor is not the exact accepted late-scene file: $relative"}
    }
    $af6=Join-Path $target $af6Relative
    if(-not(Test-Path -LiteralPath $af6 -PathType Leaf) -or (Get-Hash $af6) -ne $predecessor[$af6Relative].sha256){throw 'Live af6 replacement is not the exact accepted late-scene predecessor.'}
    $f2=@(Get-KeyClaims $mods '(?i)(?<![A-Z0-9_])(?:VK_)?F2(?![A-Z0-9_])')
    if($f2.Count -ne 1 -or -not $f2[0].path.EndsWith('\Agent2R3DSSGITest.ini',[StringComparison]::OrdinalIgnoreCase)){throw 'Live F2 ownership is not the exact accepted Agent2 claim.'}
    if(@(Get-HashClaims $mods 'c473ab75b7519f7e').Count -ne 0 -or @(Get-HashClaims $mods 'af6cd28a0108a18a').Count -ne 1){throw 'Live c473/af6 ownership is not the predecessor state.'}
    if($externalTarget){
        $contactAuthority=Join-Path $root 'artifacts\accepted-contact-family-rebuild-20260904-v1\ContactShadowFamily.ini'
        $liveContact=Join-Path $mods 'ContactShadows.ini'
        $contactSha='F86A81DEE319C6A6E98933D4AC99C0477B6E5D8B43E6F7D29272FDDA476B5478'
        if(-not(Test-Path -LiteralPath $contactAuthority -PathType Leaf) -or (Get-Hash $contactAuthority) -ne $contactSha){throw 'Automatic contact-family authority drifted.'}
        if(-not(Test-Path -LiteralPath $liveContact -PathType Leaf) -or (Get-Hash $liveContact) -ne $contactSha){throw 'Live automatic contact-family INI drifted.'}
        foreach($hash in @('08bb8764f1840179','0e97888f9a8767da','5a9fbefe0ab6f815','62b33a2d1e505241','c30cdc8365df9840')){
            $legacy=Join-Path $fixes ($hash+'-cs.txt')
            if(Test-Path -LiteralPath $legacy){throw "Legacy explicit contact replacement should remain disabled under the automatic family: $legacy"}
        }
    }
    if(-not $PSCmdlet.ShouldProcess($target,'Stage c473 pre-temporal SSGI and quarantine the accepted late-scene af6 replacement')){return}
    [void][IO.Directory]::CreateDirectory($backup)
    $snapshot=Join-Path $backup (Get-Date -Format 'yyyyMMdd-HHmmss-fff');[void][IO.Directory]::CreateDirectory($snapshot)
    $records=[Collections.Generic.List[object]]::new()
    foreach($name in $expectedNames){
        $destination=Join-Path $mods $name;$beforeBackup=Join-Path $snapshot ($name+'.before');[IO.File]::Copy($destination,$beforeBackup,$false)
        $records.Add([ordered]@{relativePath='Mods/'+$name;destination=$destination;source=$candidate[$name].source;before=[ordered]@{existed=$true;sha256=(Get-Hash $destination);backup=$beforeBackup};after=[ordered]@{existed=$true;sha256=$candidate[$name].sha256}})
    }
    $af6Backup=Join-Path $snapshot ((Split-Path -Leaf $af6)+'.before');[IO.File]::Copy($af6,$af6Backup,$false)
    $records.Add([ordered]@{relativePath=$af6Relative.Replace('\','/');destination=$af6;source=$null;before=[ordered]@{existed=$true;sha256=(Get-Hash $af6);backup=$af6Backup};after=[ordered]@{existed=$false;sha256=$null}})
    $state=[ordered]@{schemaVersion=1;packageId=$packageId;status='staging';target=$target;snapshot=$snapshot;packManifest=$manifestPath;files=@($records);af6Quarantined=$true};Write-Json $statePath $state
    try{
        foreach($name in $expectedNames){[IO.File]::Copy($candidate[$name].source,(Join-Path $mods $name),$true)}
        [IO.File]::Delete($af6)
        if(-not(Test-Phase @($records) 'after')){throw 'Post-stage payload verification failed.'}
        if(@(Get-HashClaims $mods 'c473ab75b7519f7e').Count -ne 1 -or @(Get-HashClaims $mods 'af6cd28a0108a18a').Count -ne 0){throw 'Post-stage hook ownership is invalid.'}
        $state.status='staged';Write-Json $statePath $state
    }catch{
        $failure=$_
        foreach($record in $records){[IO.File]::Copy($record.before.backup,$record.destination,$true)}
        $state.status=if(Test-Phase @($records) 'before'){'automatic-rollback-after-stage-failure'}else{'automatic-rollback-incomplete'};Write-Json $statePath $state
        if($state.status -eq 'automatic-rollback-incomplete'){throw "Stage failed and rollback was incomplete: $statePath"};throw $failure
    }
    [pscustomobject]@{Status='staged';Installed=$true;Files=$records.Count;Af6Quarantined=$true;ReloadRequired=$true;RuntimeEligible=$false;State=$statePath};return
}

if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){throw "No staging state exists: $statePath"}
$state=Get-Content -Raw -LiteralPath $statePath|ConvertFrom-Json
if($state.packageId -ne $packageId -or $state.status -ne 'staged' -or -not[string]::Equals($state.target,$target,[StringComparison]::OrdinalIgnoreCase)){throw 'Only this package exact staged state can be restored.'}
if(-not(Test-Phase @($state.files) 'after')){throw 'Restore refused because staged files drifted.'}
foreach($record in @($state.files)){if(-not(Test-Path -LiteralPath $record.before.backup -PathType Leaf) -or (Get-Hash $record.before.backup) -ne [string]$record.before.sha256){throw "Restore backup drifted: $($record.relativePath)"}}
if(-not $PSCmdlet.ShouldProcess($target,'Restore exact accepted late-scene SSGI predecessor, including af6')){return}
foreach($record in @($state.files)){[IO.File]::Copy($record.before.backup,$record.destination,$true)}
if(-not(Test-Phase @($state.files) 'before')){throw 'Post-restore verification failed.'}
$state.status='restored';$state|Add-Member -NotePropertyName restoredAtUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force;Write-Json $statePath $state
[pscustomobject]@{Status='restored';Installed=$false;Files=@($state.files).Count;Af6Restored=$true;ReloadRequired=$true;State=$statePath}

