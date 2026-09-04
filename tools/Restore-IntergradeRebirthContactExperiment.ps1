[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$GeneratedRuntimeDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$package=(Resolve-Path -LiteralPath $GeneratedRuntimeDirectory).Path.TrimEnd('\')
if(-not $package.StartsWith((Join-Path $repo 'artifacts/generated-runtime')+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Rollback package must be below workspace artifacts/generated-runtime.'}
$manifest=Get-Content (Join-Path $package 'runtime-manifest.json') -Raw|ConvertFrom-Json
$rollback=Get-Content (Join-Path $package 'rollback-manifest.json') -Raw|ConvertFrom-Json
$prior=Get-Content -LiteralPath $rollback.predecessorReceipt -Raw|ConvertFrom-Json
if($manifest.mode -ne 'rebirth-donor-shared-experiment-v1' -or $manifest.qualityGatePassed -ne $false -or $manifest.experimentalTestAuthorized -ne $true -or $rollback.targetRoot -ne $prior.targetRoot) {throw 'Not an acknowledged donor experiment rollback.'}
$live=[IO.Path]::GetFullPath($prior.targetRoot).TrimEnd('\')
function Assert-Hash([string]$path,[string]$sha) {if($sha -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $sha) {throw "Fingerprint mismatch: $path"}}
Assert-Hash (Join-Path $live 'ff7remake_.exe') $prior.executable.sha256
$allowed=@('c30cdc8365df9840','62b33a2d1e505241','5a9fbefe0ab6f815','0e97888f9a8767da','08bb8764f1840179')|ForEach-Object {"ShaderFixes/$_-cs.txt"}
$allowed+=@('Mods/ContactShadows.ini')
if(@(Compare-Object ($allowed|Sort-Object) ($rollback.files.relativePath|Sort-Object)).Count -or $rollback.files.Count -ne 6) {throw 'Unexpected rollback file set.'}
foreach($f in $manifest.protectedLiveFiles) {Assert-Hash (Join-Path $live $f.path) $f.sha256}
# Check the entire transaction before copying. Never overwrite unrelated edits.
foreach($f in $rollback.files) {
    $priorEntry=@($prior.files|Where-Object relativePath -eq $f.relativePath)
    $packageEntry=@($manifest.files|Where-Object relativePath -eq $f.relativePath)
    if($priorEntry.Count -ne 1 -or $packageEntry.Count -ne 1 -or $priorEntry[0].installedSha256 -ne $f.originalSha256 -or $packageEntry[0].sha256 -ne $f.experimentalSha256) {throw 'Rollback receipts disagree.'}
    Assert-Hash (Join-Path $package ('preinstall-backup/'+$f.relativePath)) $f.originalSha256
    Assert-Hash (Join-Path $package $f.relativePath) $f.experimentalSha256
    $current=(Get-FileHash -LiteralPath (Join-Path $live $f.relativePath)).Hash
    if($current -ne $f.originalSha256 -and $current -ne $f.experimentalSha256) {throw "Live file was edited after installation: $($f.relativePath). Refusing to overwrite it."}
}
if(-not $PSCmdlet.ShouldProcess($live,'Restore the six backed-up predecessor shader/INI files; leave other files untouched; reload manually')) {return}
foreach($f in $rollback.files) {
    Copy-Item -LiteralPath (Join-Path $package ('preinstall-backup/'+$f.relativePath)) -Destination (Join-Path $live $f.relativePath) -Force
    Assert-Hash (Join-Path $live $f.relativePath) $f.originalSha256
}
foreach($f in $manifest.protectedLiveFiles) {Assert-Hash (Join-Path $live $f.path) $f.sha256}
$report=@{state='predecessor-files-restored';restoredAtUtc=[DateTime]::UtcNow.ToString('o');files=6;reloadRequired=$true;reloadSent=$false;visualResult='Unverified until manual reload';predecessorReceipt=$rollback.predecessorReceipt}
$receipt=Join-Path $package ('restore-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')+'.json')
[IO.File]::WriteAllText($receipt,($report|ConvertTo-Json -Depth 5)+"`n",[Text.UTF8Encoding]::new($false))
[pscustomobject]$report
