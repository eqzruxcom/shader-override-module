[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$GameRoot='C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64',
    [switch]$InstallCaptureOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if(-not $output.StartsWith((Join-Path $repo 'artifacts')+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Output must be under workspace artifacts.'}
if(Test-Path -LiteralPath $output) {throw 'Output exists; preserve earlier evidence.'}
$game=(Resolve-Path -LiteralPath $GameRoot).Path.TrimEnd('\')
$expectedExe='25B54C345C94EE9F6C6876B9C7537A69E6B0EEF25F322207C32A8DDCEE816635'
if((Get-FileHash -LiteralPath (Join-Path $game 'ff7remake_.exe')).Hash -ne $expectedExe) {throw 'Unexpected game executable.'}
$source=Join-Path $repo 'src/Adapters/FF7RemakeIntergrade/ContactShadowCapture.ini'
$target=Join-Path $game 'Mods/ContactShadowCapture.ini'
if($InstallCaptureOnly -and (Test-Path -LiteralPath $target)) {throw 'Capture target already exists; do not overwrite.'}
$mainConfig=Get-Content -LiteralPath (Join-Path $game 'd3dx.ini') -Raw
foreach($pattern in @('(?m)^include_recursive\s*=\s*Mods\s*$','(?m)^analyse_options\s*=\s*mono\s*$',
    '(?m)^analyse_frame\s*=\s*no_modifiers VK_F8\s*$','(?m)^hunting\s*=\s*2\s*$',
    '(?m)^toggle_hunting\s*=\s*no_modifiers NO_VK_DECIMAL VK_NUMPAD0\s*$')) {
    if($mainConfig -notmatch $pattern) {throw "Capture precondition changed: $pattern"}
}
$text=Get-Content -LiteralPath $source -Raw
$hashes=@('c30cdc8365df9840','62b33a2d1e505241','5a9fbefe0ab6f815','0e97888f9a8767da','08bb8764f1840179')
foreach($hash in $hashes) {
    if(@([regex]::Matches($text,"(?m)^hash = $hash\s*$")).Count -ne 1) {throw 'Capture shader set mismatch.'}
}
foreach($line in ($text -split "`r?`n")) {
    $line=$line.Trim()
    if(-not $line -or $line.StartsWith(';')) {continue}
    if($line -notmatch '^\[(CommandListContactData|ShaderOverrideContact(C30|62B|5A9|0E9|08B))\]$|^hash = [0-9a-f]{16}$|^run = CommandListContactData$|^dump = (dump_cb buf desc cs-cb[0134]|dump_tex dds mono desc cs-t[1245]|buf desc cs-t1[012])$') {throw "Unexpected capture operation: $line"}
}
foreach($ini in @(Get-ChildItem -LiteralPath (Join-Path $game 'Mods') -Filter '*.ini' -Recurse -File)) {
    $other=Get-Content -LiteralPath $ini.FullName -Raw
    foreach($hash in $hashes) {if($other -match "(?im)^hash\s*=\s*$hash\s*$") {throw "Overlapping override: $($ini.FullName)"}}
}
$protected=@('d3dx.ini','d3d11.dll','Mods/UE4EffectsGenerated.ini','ShaderFixes/41f1bf8b79d01319-ps.txt')
$before=@(foreach($relative in $protected) {[ordered]@{path=$relative;sha256=(Get-FileHash -LiteralPath (Join-Path $game $relative)).Hash}})
$null=New-Item -ItemType Directory -Path $output
$utf8=[Text.UTF8Encoding]::new($false)
Copy-Item -LiteralPath $source -Destination (Join-Path $output 'ContactShadowCapture.ini')
# Preserve fresh geometry-disassembly evidence for the common view buffer.
$vs='f2f65b9971c21bde-vs'
$vsOriginal=Join-Path $game ('ShaderCache/'+$vs+'.bin')
$vsHash=(Get-FileHash -LiteralPath $vsOriginal).Hash
if($vsHash -ne 'EFFFA6ACB56BDABB07FFBD6AEE0E13E448EC6DED00533378063B3CDC740A90A8') {throw 'Geometry shader changed.'}
$binary=Join-Path $output ($vs+'.bin')
Copy-Item -LiteralPath $vsOriginal -Destination $binary
$fxc='C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
$asm=Join-Path $output ($vs+'.asm')
$messages=& $fxc /nologo /dumpbin /Fc $asm $binary 2>&1
if($LASTEXITCODE -ne 0) {throw 'Geometry disassembly failed.'}
[IO.File]::WriteAllText((Join-Path $output 'geometry-disassembly.log'),($messages|Out-String),$utf8)
$instructions=Get-Content -LiteralPath $asm -Raw
foreach($row in @(0,1,2,3,62)) {if($instructions -notmatch ('cb0\['+$row+'\]')) {throw "Missing geometry view row: $row"}}
$frame=Join-Path $repo 'artifacts/surface-lighting-study-20260830-v3/frame-log.txt'
$frameText=Get-Content -LiteralPath $frame -Raw
$bindingPattern='(?m)^000806 CSSetConstantBuffers\(StartSlot:1[^\r\n]+\r?\n\s+1: resource=0x0000027980873060 hash=a394978d'
$geometryPattern='(?m)^000813 VSSetConstantBuffers\(StartSlot:0[^\r\n]+\r?\n\s+0: resource=0x0000027980873060 hash=a394978d'
foreach($pattern in @($bindingPattern,$geometryPattern)) {if($frameText -notmatch $pattern) {throw 'Shared view-buffer evidence changed.'}}
$installed=$false
if($InstallCaptureOnly) {
    # No overwrite: this creates one new capture-only INI, never a replacement
    # shader, DLL, main config, or modification to the existing comparison.
    [IO.File]::Copy($source,$target,$false)
    $installed=$true
    if((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $target).Hash) {throw 'Capture install hash mismatch.'}
}
foreach($file in $before) {
    if((Get-FileHash -LiteralPath (Join-Path $game $file.path)).Hash -ne $file.sha256) {throw "Protected live file changed: $($file.path)"}
}
$report=[ordered]@{
    schemaVersion=1;generatedAtUtc=[DateTime]::UtcNow.ToString('o');purpose='One requested frame of contact-adapter binding evidence'
    installedCaptureOnly=$installed;installedContactEffect=$false;gameExecutableSha256=$expectedExe
    targetPath=$target;sourceSha256=(Get-FileHash -LiteralPath $source).Hash;unchangedLiveFiles=$before
    originalGeometrySha256=$vsHash;geometryAssemblySha256=(Get-FileHash -LiteralPath $asm).Hash
    bindingLogPath=$frame;bindingLogSha256=(Get-FileHash -LiteralPath $frame).Hash
    sharedViewResource='0x0000027980873060';geometryViewSlot='vs-cb0';lightingViewSlot='cs-cb1'
    captureKey='F8, with hunting enabled using existing Numpad0 toggle';holdsMultipleFrames=$false
    resources=@('cb0 dispatch','cb1 view','cb3 local-light directions/parameters','cb4 light position/radius/colour','t1 normal','t2 packed material','t4 or t5 depth','tile-list and per-tile light buffers')
    rollback='Move only Mods/ContactShadowCapture.ini out of Mods, preserving this receipt; reload config or restart afterward.'
    limitations=@('Capture INI syntax checked against local source, not yet parsed by running game','Synthetic adapter checks do not prove live constant values','Capture can briefly stall and write full-resolution textures; no broad all-frame resource dump')
}
[IO.File]::WriteAllText((Join-Path $output 'capture-preparation.json'),(($report|ConvertTo-Json -Depth 6)+"`n"),$utf8)
[pscustomobject]@{Result='contact-capture-prepared';InstalledCaptureOnly=$installed;ContactEffectInstalled=$false;Output=$output}
