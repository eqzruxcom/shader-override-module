[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$GeneratedRuntimeDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$package=(Resolve-Path -LiteralPath $GeneratedRuntimeDirectory).Path.TrimEnd('\')
if(-not $package.StartsWith((Join-Path $repo 'artifacts/generated-runtime')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected rollback package scope.'}
$manifest=Get-Content -LiteralPath (Join-Path $package 'runtime-manifest.json') -Raw|ConvertFrom-Json
$rollback=Get-Content -LiteralPath (Join-Path $package 'rollback-manifest.json') -Raw|ConvertFrom-Json
$prior=Get-Content -LiteralPath $rollback.predecessorReceipt -Raw|ConvertFrom-Json
if($manifest.mode -ne 'rebirth-contact-left-edge-fade-experiment-v1' -or $manifest.qualityGatePassed -ne $false -or $rollback.targetRoot -ne $prior.targetRoot){throw 'Wrong experiment receipt.'}
$live=[IO.Path]::GetFullPath($prior.targetRoot).TrimEnd('\')
if($live -cne 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64'){throw 'Wrong game root.'}
function Assert-Hash([string]$path,[string]$sha){if($sha -notmatch '^[0-9a-fA-F]{64}$' -or (Get-FileHash -LiteralPath $path).Hash -ne $sha){throw "Fingerprint mismatch: $path"}}
$allowed=@('c30cdc8365df9840','62b33a2d1e505241','5a9fbefe0ab6f815','0e97888f9a8767da','08bb8764f1840179')|ForEach-Object {"ShaderFixes/$_-cs.txt"}
$allowed+=@('Mods/ContactShadows.ini')
if($rollback.files.Count -ne 6 -or @(Compare-Object ($allowed|Sort-Object) ($rollback.files.relativePath|Sort-Object)).Count){throw 'Unexpected rollback payload.'}
Assert-Hash (Join-Path $live 'ff7remake_.exe') $prior.executable.sha256
foreach($file in $manifest.protectedLiveFiles){Assert-Hash (Join-Path $live $file.path) $file.sha256}
foreach($file in $rollback.files){
    $before=@($prior.files|Where-Object relativePath -eq $file.relativePath)
    $after=@($manifest.files|Where-Object relativePath -eq $file.relativePath)
    if($before.Count -ne 1 -or $after.Count -ne 1 -or $before[0].installedSha256 -ne $file.originalSha256 -or $after[0].sha256 -ne $file.experimentalSha256){throw 'Rollback receipts disagree.'}
    Assert-Hash (Join-Path $package ('preinstall-backup/'+$file.relativePath)) $file.originalSha256
    Assert-Hash (Join-Path $package $file.relativePath) $file.experimentalSha256
    $current=(Get-FileHash -LiteralPath (Join-Path $live $file.relativePath)).Hash
    if($current -ne $file.originalSha256 -and $current -ne $file.experimentalSha256){throw 'Unrelated live edit: rollback refused.'}
}
if(-not $PSCmdlet.ShouldProcess($live,'Restore the six backed-up working-baseline files, without deleting anything or reloading')){return}
foreach($file in $rollback.files){Copy-Item -LiteralPath (Join-Path $package ('preinstall-backup/'+$file.relativePath)) -Destination (Join-Path $live $file.relativePath) -Force;Assert-Hash (Join-Path $live $file.relativePath) $file.originalSha256}
foreach($file in $manifest.protectedLiveFiles){Assert-Hash (Join-Path $live $file.path) $file.sha256}
$receipt=@{state='working-baseline-files-restored';restoredAtUtc=[DateTime]::UtcNow.ToString('o');reloadRequired=$true;reloadSent=$false;files=6;predecessorReceipt=$rollback.predecessorReceipt}
[IO.File]::WriteAllText((Join-Path $package ('restore-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')+'.json')),($receipt|ConvertTo-Json)+"`n",[Text.UTF8Encoding]::new($false))
[pscustomobject]$receipt
