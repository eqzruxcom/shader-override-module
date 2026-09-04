[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory)
# Read-only with respect to the game. Preserve a qualified visual milestone,
# not a passing quality gate or an inference about screenshot toggle states.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$checkpointRoot=Join-Path $repo 'artifacts/checkpoints'
if(-not $output.StartsWith($checkpointRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)) {throw 'Use a fresh directory strictly below artifacts/checkpoints.'}
$package=Join-Path $repo 'artifacts/generated-runtime/FF7RemakeIntergradeRebirthContact-experiment-live-v1'
$runtime=Get-Content -LiteralPath (Join-Path $package 'runtime-manifest.json') -Raw|ConvertFrom-Json
$receipt=Get-Content -LiteralPath (Join-Path $package 'install-receipt.json') -Raw|ConvertFrom-Json
$live=$receipt.targetRoot
$allow=@('ShaderFixes/c30cdc8365df9840-cs.txt','ShaderFixes/62b33a2d1e505241-cs.txt','ShaderFixes/5a9fbefe0ab6f815-cs.txt','ShaderFixes/0e97888f9a8767da-cs.txt','ShaderFixes/08bb8764f1840179-cs.txt','Mods/ContactShadows.ini')
if(@(Compare-Object ($allow|Sort-Object) ($runtime.files.relativePath|Sort-Object)).Count -or @(Compare-Object ($allow|Sort-Object) ($receipt.files.relativePath|Sort-Object)).Count) {throw 'Unexpected payload.'}
function Assert-Hash([string]$path,[string]$expected) {
    if($expected -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected) {throw "Hash mismatch: $path"}
}
Assert-Hash (Join-Path $package 'runtime-manifest.json') $receipt.sourceManifestSha256
foreach($file in $runtime.files) {
    $installed=@($receipt.files|Where-Object relativePath -eq $file.relativePath)
    if($installed.Count -ne 1 -or $installed[0].installedSha256 -ne $file.sha256) {throw 'Receipt mismatch.'}
    Assert-Hash (Join-Path $package $file.relativePath) $file.sha256
    Assert-Hash (Join-Path $live $file.relativePath) $file.sha256
}
foreach($file in $runtime.protectedLiveFiles) {Assert-Hash (Join-Path $live $file.path) $file.sha256}
$queue=[Collections.Generic.List[object]]::new()
function Queue-Copy([string]$source,[string]$relative,[string]$kind,[string]$note='') {
    $queue.Add([pscustomobject]@{source=$source;relativePath=$relative;kind=$kind;note=$note;sha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash})
}
foreach($file in $runtime.files) {Queue-Copy (Join-Path $package $file.relativePath) ('payload/'+$file.relativePath) 'installed-payload'}
foreach($name in @('runtime-manifest.json','install-receipt.json','live-reload-baseline.json','contact-live-status.json','rollback-manifest.json','ShaderInjector-MIT.txt')) {Queue-Copy (Join-Path $package $name) ('receipts/'+$name) 'historical-receipt'}
foreach($file in $receipt.files) {
    $source=Join-Path $package ('preinstall-backup/'+$file.relativePath)
    Assert-Hash $source $file.originalSha256
    Queue-Copy $source ('predecessor/'+$file.relativePath) 'pre-experiment-backup'
}
$sources=@('tools/New-IntergradeContactShadowCandidate.ps1','tools/Stage-IntergradeRebirthContactExperiment.ps1','tools/Restore-IntergradeRebirthContactExperiment.ps1','tools/import_rebirth_contact_source.py','src/Effects/Lighting/ContactShadowCommon.hlsl','src/Effects/Lighting/RebirthContactShadows.hlsl','src/Adapters/FF7RemakeIntergrade/ContactShadowKernel_ps.hlsl','src/Adapters/FF7RemakeIntergrade/RebirthContactShadowKernel_ps.hlsl','src/Adapters/FF7RemakeIntergrade/RebirthContactInputMapping.hlsl','src/Adapters/FF7RemakeIntergrade/RebirthContactShared.hlsl','src/Adapters/FF7RemakeIntergrade/RebirthContactSharedKernel_cs.hlsl','src/ThirdParty/ShaderInjector/RebirthContactRay.hlsl','src/ThirdParty/ShaderInjector/RebirthContactNoise.hlsl','src/ThirdParty/ShaderInjector/RebirthContactReconstruction.hlsl','src/ThirdParty/ShaderInjector/LICENSE.txt','src/ThirdParty/ShaderInjector/provenance.json')
foreach($path in $sources) {Queue-Copy (Join-Path $repo $path) ('source/'+$path) 'current-source-snapshot'}
foreach($evidence in $runtime.evidence) {Assert-Hash $evidence.path $evidence.sha256; Queue-Copy $evidence.path ('evidence/'+(Split-Path (Split-Path $evidence.path -Parent) -Leaf)+'-'+(Split-Path $evidence.path -Leaf)) 'validation-receipt' $evidence.scope}
$screens=@(
    @('127604a5-1830-4471-8121-46ece77f44f4','01-initial-comparison-a','Initial pair. ON/OFF order not supplied.'),
    @('38416228-a7e5-45bd-b1de-f134038e7795','02-initial-comparison-b','Initial pair. ON/OFF order not supplied.'),
    @('65c1be9b-28e5-4b13-8191-0e2ee074bced','03-sword-tip','User identifies hard added shadow beside native soft shadow.'),
    @('807caba9-342b-4f38-ab4f-caea4471b99c','04-sword-tip-side','User identifies hard added shadow beside native soft shadow.'),
    @('55ec83c6-89ea-4827-9be0-b8e7d7732106','05-sword-edge','Further sword-edge example. State not inferred.'),
    @('d1ef4335-5213-4597-91ac-8063a0f25003','06-cone-edge','User identifies hard sharp shadow at cone left of Cloud. State not inferred.')
)
foreach($screen in $screens) {Queue-Copy ('C:/Users/EQZITARA/AppData/Local/Temp/codex-clipboard-'+$screen[0]+'.png') ('screenshots/'+$screen[1]+'.png') 'original-user-screenshot' $screen[2]}
# Complete all source/hash checks before creating output. No overwrite or delete.
$null=New-Item -ItemType Directory -Path $output
foreach($copy in $queue) {
    $target=Join-Path $output $copy.relativePath
    $null=New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force
    Copy-Item -LiteralPath $copy.source -Destination $target
    Assert-Hash $target $copy.sha256
    Assert-Hash $copy.source $copy.sha256
}
foreach($file in $runtime.files) {Assert-Hash (Join-Path $live $file.relativePath) $file.sha256}
foreach($file in $runtime.protectedLiveFiles) {Assert-Hash (Join-Path $live $file.path) $file.sha256}
$manifest=[ordered]@{
    schemaVersion=1;createdAtUtc=[DateTime]::UtcNow.ToString('o');status='user-reported-working-in-most-cases-with-hard-shadow-flaw';
    sourcePackage=$package;scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;
    livePayloadVerified=$true;gameFilesModified=$false;qualityGatePassed=$false;releaseEligible=$false;
    userReports=@('its stable','the vague shadow is already existing shadow','the hard one is your contact shadow','that said it looks working in most cases','can we "soften" it?','the shadow if "hard" and sharp');
    interpretation='Working prototype, not clean approval. User attributes soft shadow to native game, hard shadow to added contacts. Sword and scenery cone examples.';
    screenshotOnOffOrder='unknown';motionEvidence='user report only; screenshots cannot establish temporal stability';
    limitations=@('Preserves known failing synthetic motion evidence','No native penumbra matching or performance proof','No claim of full shader coverage','Current ON/OFF state not read');
    files=@($queue.ToArray())
}
$utf8=[Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $output 'checkpoint.json'),($manifest|ConvertTo-Json -Depth 8)+"`n",$utf8)
[pscustomobject]@{checkpoint=$output;files=$queue.Count;screenshots=$screens.Count;liveFilesChanged=$false;releaseEligible=$false}|ConvertTo-Json
