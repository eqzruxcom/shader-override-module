[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$OutputDirectory,[switch]$Install)
# Bounded refinement experiment. Does not relax the normal release/motion gates.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$fork=Join-Path $repo 'artifacts/contact-viewport-development-20260831-v1'
$candidateRoot=Join-Path $fork 'artifacts/viewport-candidate'
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if(-not $output.StartsWith((Join-Path $repo 'artifacts/generated-runtime')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Use a fresh generated-runtime child directory.'}
$utf8=[Text.UTF8Encoding]::new($false)
function Read-Json([string]$path){Get-Content -LiteralPath $path -Raw|ConvertFrom-Json}
function Write-Json([string]$path,$document){[IO.File]::WriteAllText($path,($document|ConvertTo-Json -Depth 12)+"`n",$utf8)}
function Assert-Hash([string]$path,[string]$expected){if($expected -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath $path).Hash -ne $expected){throw "Fingerprint mismatch: $path"}}
function Scoped-Path([string]$root,[string]$relative){
    if([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)'){throw 'Unsafe relative path.'}
    $path=[IO.Path]::GetFullPath((Join-Path $root $relative))
    if(-not $path.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Path escaped scope.'}
    return $path
}
function Assert-Sources([string]$root,$document){foreach($source in $document.sources){Assert-Hash (Scoped-Path $root $source.path) $source.sha256}}
$candidatePath=Join-Path $candidateRoot 'candidate.json'
$candidate=Read-Json $candidatePath
$hashes=@('c30cdc8365df9840','62b33a2d1e505241','5a9fbefe0ab6f815','0e97888f9a8767da','08bb8764f1840179')
if($candidate.implementation -ne 'Rebirth' -or $candidate.reconstruction -ne 'SharedQuad' -or $candidate.sampleCount -ne 16 -or ($candidate.variants.shaderHash -join ',') -cne ($hashes -join ',')){throw 'Unexpected five-variant candidate.'}
Assert-Sources $fork $candidate
Assert-Hash (Join-Path $fork 'tools/New-IntergradeContactShadowCandidate.ps1') $candidate.generatorSha256
Assert-Hash (Join-Path $fork 'artifacts/rebirth-contact-shared-boundary-20260831-v2/boundary.json') $candidate.sharedBoundarySha256
$evidence=@()
foreach($kind in @('single','repeat')){
    $path=Join-Path $fork "artifacts/viewport-interface-$kind/manifest.json"
    $check=Read-Json $path
    $iterations=if($kind -eq 'single'){1}else{8}
    if($check.result -ne 'passed-shared-interface-only' -or $check.groupsPassed -ne 1200 -or $check.creationChecks -ne 15 -or $check.laneCases -ne 307200*$iterations -or $check.lightIterationsPerDispatch -ne $iterations -or $check.qualityGatePassed -ne $false){throw 'Incomplete assembled interface evidence.'}
    Assert-Hash $candidatePath $check.candidateManifestSha256
    Assert-Sources $fork $check
    Assert-Hash (Join-Path $fork 'tools/Test-RebirthSharedContactInterface.ps1') $check.scriptSha256
    Assert-Hash (Join-Path $check.testBuildDirectory 'manifest.json') $check.testManifestSha256
    Assert-Hash (Join-Path $check.testBuildDirectory 'ContactShadowWarpTest.exe') $check.runnerSha256
    foreach($variant in $candidate.variants){
        $row=@($check.variants|Where-Object shaderHash -eq $variant.shaderHash)
        if($row.Count -ne 1 -or $row[0].candidateSha256 -ne $variant.candidateSha256 -or $row[0].groupsPassed -ne 240){throw 'Per-variant evidence mismatch.'}
        $fixture=if($kind -eq 'single'){$variant.injectionFixture}else{$variant.repeatedFixture}
        Assert-Hash (Scoped-Path $candidateRoot $fixture) $row[0].fixtureSha256
    }
    $evidence+=@{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash;scope=$check.result}
}
$rayPath=Join-Path $repo 'artifacts/contact-viewport-ray-20260831-v2/manifest.json'
$ray=Read-Json $rayPath
if($ray.status -ne 'passed-analytic-full-ray-comparison' -or $ray.profiles.Count -ne 6){throw 'Missing edge-entry regression.'}
Assert-Hash (Join-Path $repo 'tools/Test-ContactViewportRay.ps1') $ray.scriptSha256
foreach($profile in $ray.profiles){
    $expectedRoot=if($profile.profile -eq 'baseline'){$repo}elseif($profile.profile -eq 'viewport'){$fork}else{throw 'Unknown edge profile.'}
    if($profile.root -ne $expectedRoot -or $profile.checks -ne 256){throw 'Wrong edge fixture root or count.'}
    Assert-Sources $expectedRoot $profile
}
$evidence+=@{path=$rayPath;sha256=(Get-FileHash -LiteralPath $rayPath).Hash;scope=$ray.status}
$replayRoot=Join-Path $fork 'artifacts/viewport-capture-shared'
$replay=Read-Json (Join-Path $replayRoot 'manifest.json')
$oldReplayRoot=Join-Path $repo 'artifacts/rebirth-contact-capture-shared-20260831-v2'
$oldReplay=Read-Json (Join-Path $oldReplayRoot 'manifest.json')
Assert-Sources $fork $replay
Assert-Sources $repo $oldReplay
if($replay.reconstruction -ne 'SharedQuad' -or $replay.results.Count -ne 10 -or $replay.sampleLayout -ne 'SparseCompleteQuads'){throw 'Wrong captured replay.'}
foreach($key in $replay.boundInputKeys){
    if($replay.inputHashes.$key -ne $oldReplay.inputHashes.$key){throw 'Replay inputs differ.'}
    Assert-Hash (Join-Path $replay.captureDirectory $replay.inputFiles.$key) $replay.inputHashes.$key
}
$replayComparisons=@(foreach($file in $replay.outputs|Where-Object path -match '^light-.*\.(f32|u8)$'){
    Assert-Hash (Scoped-Path $replayRoot $file.path) $file.sha256
    $old=@($oldReplay.outputs|Where-Object path -eq $file.path)
    if($old.Count -ne 1 -or $old[0].sha256 -ne $file.sha256){throw 'Saved-frame behavior changed; review before installation.'}
    Assert-Hash (Scoped-Path $oldReplayRoot $file.path) $file.sha256
    @{path=$file.path;bitIdentical=$true;sha256=$file.sha256}
})
if($replayComparisons.Count -ne 20){throw 'Incomplete saved-frame comparison.'}
$motionRoot=Join-Path $fork 'artifacts/viewport-motion16-v2'
$motion=Read-Json (Join-Path $motionRoot 'manifest.json')
Assert-Sources $fork $motion
if(-not $motion.regressionDetected -or $motion.samples -ne 16 -or $motion.framesPerScene -ne 96){throw 'Expected disclosed motion result changed.'}
$oldMotion=Join-Path $repo 'artifacts/rebirth-contact-experiment-motion16-20260831-v1/visibility.f32'
Assert-Hash (Join-Path $motionRoot 'visibility.f32') (Get-FileHash -LiteralPath $oldMotion).Hash
foreach($path in @((Join-Path $replayRoot 'manifest.json'),(Join-Path $motionRoot 'manifest.json'))){$evidence+=@{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash;scope='Regression comparison; not a visual-quality pass'}}
$predecessorRoot=Join-Path $repo 'artifacts/generated-runtime/FF7RemakeIntergradeRebirthContact-experiment-live-v1'
$baseline=Read-Json (Join-Path $predecessorRoot 'live-reload-baseline.json')
$prior=Read-Json $baseline.installReceipt
$live=[IO.Path]::GetFullPath($prior.targetRoot).TrimEnd('\')
if($live -cne 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64'){throw 'Unexpected game root.'}
$allowed=@($hashes|ForEach-Object {"ShaderFixes/$_-cs.txt"})+@('Mods/ContactShadows.ini')
if($prior.files.Count -ne 6 -or @(Compare-Object ($allowed|Sort-Object) ($prior.files.relativePath|Sort-Object)).Count){throw 'Unexpected predecessor payload.'}
function Assert-Predecessor {
    Assert-Hash (Join-Path $live 'ff7remake_.exe') $prior.executable.sha256
    foreach($file in $prior.files){Assert-Hash (Scoped-Path $live $file.relativePath) $file.installedSha256}
    foreach($file in $baseline.protectedLiveFiles){Assert-Hash (Scoped-Path $live $file.path) $file.sha256}
    $expected=@($allowed)+@('Mods/UE4EffectsGenerated.ini','Mods/ContactShadowCapture.ini','ShaderFixes/41f1bf8b79d01319-ps.txt')
    $active=@(Get-ChildItem -LiteralPath (Join-Path $live 'Mods') -File -Recurse -Filter '*.ini')+@(Get-ChildItem -LiteralPath (Join-Path $live 'ShaderFixes') -File -Recurse)
    $actual=@($active|ForEach-Object {$_.FullName.Substring($live.Length+1).Replace('\','/')})
    if(@(Compare-Object ($expected|Sort-Object) ($actual|Sort-Object)).Count){throw 'Other shader/INI files appeared; reassess.'}
    $game=Get-Process -Id $baseline.processId -ErrorAction Stop
    if($game.Path -ne $prior.executable.path -or -not $game.Responding){throw 'Expected game process unavailable.'}
}
Assert-Predecessor
if(-not $PSCmdlet.ShouldProcess($output,'Prepare viewport-only contact experiment with exact baseline rollback')){return}
foreach($part in @('','ShaderFixes','Mods','validation','preinstall-backup')){$null=New-Item -ItemType Directory -Path (Join-Path $output $part)}
$files=@()
$assembler=Join-Path $repo 'artifacts/shader-assembler-build/bin/cmd_Decompiler.exe'
foreach($variant in $candidate.variants){
    if(-not $variant.roundTripByteIdentical -or -not $variant.maskedContributionIdentityLanes -or -not $variant.sharedGroup -or $variant.sharedMemoryBytes -ne 1024){throw 'Candidate safety invariant missing.'}
    $original=Join-Path $candidateRoot "validation/$($variant.shaderHash)-original.bin"
    Assert-Hash $original $variant.originalSha256
    Assert-Hash (Scoped-Path $candidateRoot $variant.binary) $variant.candidateSha256
    $relative="ShaderFixes/$($variant.shaderHash)-cs.txt"
    Copy-Item -LiteralPath (Scoped-Path $candidateRoot $variant.assembly) -Destination (Join-Path $output $relative)
    $roundTrip=Join-Path $output "validation/$($variant.shaderHash)-payload.asm"
    Copy-Item -LiteralPath (Join-Path $output $relative) -Destination $roundTrip
    $messages=& $assembler -a --copy-reflection $original $roundTrip 2>&1
    if($LASTEXITCODE -ne 0){throw "Payload assembly failed: $($variant.shaderHash)"}
    Assert-Hash ([IO.Path]::ChangeExtension($roundTrip,'.shdr')) $variant.candidateSha256
    $files+=@{relativePath=$relative;sha256=(Get-FileHash -LiteralPath (Join-Path $output $relative)).Hash}
}
$lines=@('; Viewport-only contact refinement. Softness NOT included. Experimental, not release-ready.',
    '; Home OFF/ON; fresh nonpersistent state defaults OFF. Other keys unchanged.',
    '[Constants]','global $ue4fx_contact_viewport_v1 = 0','',
    '[KeyUE4FXContactHome]','key = no_modifiers VK_HOME','type = cycle','smart = true',
    '$ue4fx_contact_viewport_v1 = 0, 1','')
foreach($hash in $hashes){$lines+=@("[ShaderOverrideUE4FXContact$hash]","hash = $hash",'x31 = $ue4fx_contact_viewport_v1','y31 = -1','z31 = 1','w31 = 100','')}
[IO.File]::WriteAllText((Join-Path $output 'Mods/ContactShadows.ini'),($lines -join "`r`n")+"`r`n",$utf8)
$files+=@{relativePath='Mods/ContactShadows.ini';sha256=(Get-FileHash -LiteralPath (Join-Path $output 'Mods/ContactShadows.ini')).Hash}
$gateHashes=@(foreach($name in @('Assert-IntergradeContactMotionGate.ps1','Assert-IntergradeContactSoftwareGate.ps1','Stage-IntergradeContactAllLights.ps1')){@{path="tools/$name";sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash}})
$manifest=@{schemaVersion=1;adapterId='FF7RemakeIntergradeContactShadows';mode='rebirth-contact-viewport-experiment-v1';licensedRegexDependency=$false;diagnosticOnly=$true;runtimeEligible=$false;releaseEligible=$false;qualityGatePassed=$false;knownMotionArtifacts=$true;authorization='User requested work on hard-contact and screen-edge issues; bounded refinement only';implementation='Rebirth';reconstruction='SharedQuad';samples=16;executable=$prior.executable;files=$files;evidence=$evidence;candidateManifestSha256=(Get-FileHash -LiteralPath $candidatePath).Hash;stagerSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;unchangedReleaseGates=$gateHashes;protectedLiveFiles=$baseline.protectedLiveFiles;key='Home';defaultEnabled=$false;softnessIncluded=$false;liveTested=$false;performanceTested=$false;predecessorReceipt=$baseline.installReceipt;limitations=@('Targeted analytic edge fix; exact video cause unconfirmed','Old synthetic motion failures remain','OFF preserves native math, not original execution cost','No native shadow replacement or offscreen geometry recovery')}
Write-Json (Join-Path $output 'runtime-manifest.json') $manifest
Write-Json (Join-Path $output 'captured-output-comparison.json') @{files=$replayComparisons;scope='One saved frame, sparse quads, not the current video'}
Copy-Item -LiteralPath (Join-Path $repo 'licenses/ShaderInjector-MIT.txt') -Destination (Join-Path $output 'ShaderInjector-MIT.txt')
Assert-Predecessor
foreach($file in $prior.files){
    $backup=Join-Path $output ('preinstall-backup/'+$file.relativePath)
    $null=New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force
    Copy-Item -LiteralPath (Scoped-Path $live $file.relativePath) -Destination $backup
    Assert-Hash $backup $file.installedSha256
}
$rollback=@{targetRoot=$live;predecessorReceipt=$baseline.installReceipt;files=@(foreach($file in $prior.files){@{relativePath=$file.relativePath;originalSha256=$file.installedSha256;experimentalSha256=($files|Where-Object relativePath -eq $file.relativePath).sha256}})}
Write-Json (Join-Path $output 'rollback-manifest.json') $rollback
$installed=$false
if($Install -and $PSCmdlet.ShouldProcess($live,'Install only five contact replacements and their Home INI; no reload or keys sent')){
    Assert-Predecessor
    $offset=(Get-Item -LiteralPath $baseline.logPath).Length
    $installPath=Join-Path $output 'install-receipt.json'
    try {
        & (Join-Path $PSScriptRoot 'Install-UE4GeneratedRuntimeOverlay.ps1') -GeneratedRuntimeDirectory $output -GameRoot (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $live))) -InstallManifestPath $installPath
        foreach($file in $files){Assert-Hash (Scoped-Path $live $file.relativePath) $file.sha256}
        foreach($file in $baseline.protectedLiveFiles){Assert-Hash (Scoped-Path $live $file.path) $file.sha256}
        foreach($file in $gateHashes){Assert-Hash (Scoped-Path $repo $file.path) $file.sha256}
        Write-Json (Join-Path $output 'live-reload-baseline.json') @{schemaVersion=1;mode=$manifest.mode;processId=$baseline.processId;capturedAtUtc=[DateTime]::UtcNow.ToString('o');logPath=$baseline.logPath;byteOffset=$offset;installReceipt=$installPath;expectedShaders=$hashes;defaultEnabled=$false;key='Home';reloadRequired=$true;protectedLiveFiles=$baseline.protectedLiveFiles}
        $installed=$true
    } catch {
        $failure=$_
        # Verify the WHOLE rollback before changing anything; preserve unrelated edits.
        foreach($file in $rollback.files){
            Assert-Hash (Join-Path $output ('preinstall-backup/'+$file.relativePath)) $file.originalSha256
            $current=(Get-FileHash -LiteralPath (Scoped-Path $live $file.relativePath)).Hash
            if($current -ne $file.originalSha256 -and $current -ne $file.experimentalSha256){throw "Concurrent change prevents rollback: $($file.relativePath). Backups: $output. Initial failure: $failure"}
        }
        foreach($file in $rollback.files){Copy-Item -LiteralPath (Join-Path $output ('preinstall-backup/'+$file.relativePath)) -Destination (Scoped-Path $live $file.relativePath) -Force;Assert-Hash (Scoped-Path $live $file.relativePath) $file.originalSha256}
        throw $failure
    }
}
[pscustomobject]@{State='viewport-only-experiment-prepared';Installed=$installed;Output=$output;Key='Home';Default='OFF';SoftnessIncluded=$false;ReloadSent=$false}
