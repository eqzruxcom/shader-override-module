[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][ValidateSet('Stage','Status','Restore')][string]$Action,
    [Parameter(Mandatory)][string]$TargetWin64Directory,
    [string]$PackRoot=(Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\intergrade-lighting-ownership-capture-pack-20260904-v1'),
    [string]$BackupRoot=(Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\intergrade-lighting-ownership-capture-stage-backups'),
    [switch]$AllowExternalTarget,
    [switch]$AcknowledgeCaptureOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$target=[IO.Path]::GetFullPath($TargetWin64Directory).TrimEnd('\')
$pack=[IO.Path]::GetFullPath($PackRoot).TrimEnd('\')
$backup=[IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')
$external=-not $target.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)
if($external){
    if(-not $AllowExternalTarget){throw "External target requires -AllowExternalTarget: $target"}
    if(-not $target.EndsWith('\End\Binaries\Win64',[StringComparison]::OrdinalIgnoreCase)){throw 'External target must be an exact FF7 Remake End\Binaries\Win64 directory.'}
}
if(-not $backup.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'BackupRoot must remain inside the workspace.'}
$mods=Join-Path $target 'Mods'
if(-not(Test-Path -LiteralPath $mods -PathType Container)){throw "Target Mods directory is missing: $mods"}

$manifestPath=Join-Path $pack 'manifest.json'
$source=Join-Path $pack 'Mods\IntergradeLightingOwnershipCapture.ini'
foreach($path in @($manifestPath,$source)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Capture-pack file is missing: $path"}}
$manifest=Get-Content -Raw -LiteralPath $manifestPath|ConvertFrom-Json
if($manifest.schemaVersion -ne 1 -or $manifest.result -ne 'pass' -or $manifest.packId -ne 'ff7-remake-lighting-ownership-capture-v1' -or
   [bool]$manifest.runtimeEligible -or [bool]$manifest.installed -or @($manifest.targets).Count -ne 2 -or
   (@($manifest.targets.hash|Sort-Object)-join ',') -ne 'aadc1c2374853914,adb544f9a11d6c7e') {throw 'Capture-pack manifest failed its closed contract.'}
$file=@($manifest.files|Where-Object path -eq 'Mods/IntergradeLightingOwnershipCapture.ini')
if($file.Count -ne 1 -or (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash -ne [string]$file[0].sha256){throw 'Capture-pack payload checksum is invalid.'}
$ini=[IO.File]::ReadAllText($source)
if($ini -match '(?im)^\s*(?:key|handling|run|draw|dispatch)\s*=' -or [regex]::Matches($ini,'(?im)^\s*analyse_options\s*=\s*dump_rt dump_tex dump_cb mono desc\s*$').Count -ne 2){throw 'Capture-only INI gained rendering or key behavior.'}

if($external){
    $d3dx=Join-Path $target 'd3dx.ini'
    if(-not(Test-Path -LiteralPath $d3dx -PathType Leaf)){throw "Live d3dx.ini is missing: $d3dx"}
    $d3dxText=[IO.File]::ReadAllText($d3dx)
    if($d3dxText -notmatch '(?im)^\s*include_recursive\s*=\s*Mods\s*$' -or $d3dxText -notmatch '(?im)^\s*analyse_frame\s*=.*(?<![A-Z0-9_])(?:VK_)?F8(?![A-Z0-9_]).*$') {throw 'Live d3dx.ini lacks the required Mods include or existing F8 frame-analysis trigger.'}
}

$destination=Join-Path $mods 'IntergradeLightingOwnershipCapture.ini'
$statePath=Join-Path $backup 'active-state.json'
function Write-State([object]$State){[void][IO.Directory]::CreateDirectory($backup);[IO.File]::WriteAllText($statePath,($State|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))}

if($Action -eq 'Status'){
    if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){
        $status=if(Test-Path -LiteralPath $destination -PathType Leaf){'unmanaged-present'}else{'not-staged'}
        [pscustomobject]@{Status=$status;Installed=$false;Target=$destination;State=$statePath};return
    }
    $state=Get-Content -Raw -LiteralPath $statePath|ConvertFrom-Json
    if($state.packageId -ne 'ff7-remake-lighting-ownership-capture-v1' -or -not[string]::Equals($state.destination,$destination,[StringComparison]::OrdinalIgnoreCase)){throw 'Capture staging state belongs to another target.'}
    $present=Test-Path -LiteralPath $destination -PathType Leaf
    $exact=$present -and (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash -eq [string]$state.installedSha256
    $status=if($state.status -eq 'staged' -and $exact){'staged'}elseif($state.status -eq 'restored' -and -not $present){'restored'}else{'drifted'}
    [pscustomobject]@{Status=$status;Installed=($status -eq 'staged');Target=$destination;State=$statePath};return
}

if($Action -eq 'Stage'){
    if(-not $AcknowledgeCaptureOnly){throw 'Stage requires -AcknowledgeCaptureOnly; this pack is for a deliberate F8 frame capture.'}
    if(Test-Path -LiteralPath $statePath){throw "A capture staging state already exists: $statePath"}
    if(Test-Path -LiteralPath $destination){throw "Refusing to overwrite unmanaged capture INI: $destination"}
    if(-not $PSCmdlet.ShouldProcess($destination,'Stage read-only lighting ownership frame-analysis triggers')){return}
    $state=[ordered]@{schemaVersion=1;packageId='ff7-remake-lighting-ownership-capture-v1';status='staging';destination=$destination;installedSha256=[string]$file[0].sha256;beforeExisted=$false;stagedAtUtc=[DateTime]::UtcNow.ToString('o')}
    Write-State $state
    try{
        [IO.File]::Copy($source,$destination,$false)
        if((Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash -ne $state.installedSha256){throw 'Post-stage checksum mismatch.'}
        $state.status='staged';Write-State $state
    }catch{
        if(Test-Path -LiteralPath $destination){[IO.File]::Delete($destination)}
        $state.status=if(-not(Test-Path -LiteralPath $destination)){'automatic-rollback-after-stage-failure'}else{'automatic-rollback-incomplete'};Write-State $state
        throw
    }
    [pscustomobject]@{Status='staged';Installed=$true;RenderingMutated=$false;KeysAdded=0;ReloadRequired=$true;State=$statePath};return
}

if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){throw "No capture staging state exists: $statePath"}
$state=Get-Content -Raw -LiteralPath $statePath|ConvertFrom-Json
if($state.packageId -ne 'ff7-remake-lighting-ownership-capture-v1' -or $state.status -ne 'staged' -or -not[string]::Equals($state.destination,$destination,[StringComparison]::OrdinalIgnoreCase)){throw 'Only the exact managed staged capture INI can be restored.'}
if(-not(Test-Path -LiteralPath $destination -PathType Leaf) -or (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash -ne [string]$state.installedSha256){throw 'Restore refused because the staged capture INI drifted.'}
if(-not $PSCmdlet.ShouldProcess($destination,'Remove the managed capture-only INI')){return}
[IO.File]::Delete($destination)
if(Test-Path -LiteralPath $destination){throw 'Capture INI removal could not be verified.'}
$state.status='restored';$state|Add-Member -NotePropertyName restoredAtUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force;Write-State $state
[pscustomobject]@{Status='restored';Installed=$false;RenderingMutated=$false;ReloadRequired=$true;State=$statePath}

