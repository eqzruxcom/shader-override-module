[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [switch]$AcknowledgeKnownMotionArtifacts,
    [switch]$Install
)
# Separate, user-authorized experiment. Does not replace or relax release gates.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $AcknowledgeKnownMotionArtifacts) {throw 'Explicit acknowledgement required: donor motion artifacts remain; this is not a quality-approved build.'}
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if(-not $output.StartsWith((Join-Path $repo 'artifacts/generated-runtime')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)) {throw 'Use a fresh directory strictly below artifacts/generated-runtime.'}
$utf8=[Text.UTF8Encoding]::new($false)
function Read-Json([string]$path) {Get-Content -LiteralPath $path -Raw | ConvertFrom-Json}
function Assert-Hash([string]$path,[string]$expected) {
    if($expected -notmatch '^[0-9a-fA-F]{64}$' -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected) {throw "Fingerprint mismatch: $path"}
}
function Assert-Sources($document) {foreach($source in $document.sources) {Assert-Hash (Join-Path $repo $source.path) $source.sha256}}
function Write-Json([string]$path,$document) {[IO.File]::WriteAllText($path,($document|ConvertTo-Json -Depth 12)+"`n",$utf8)}
$expectedHashes=@('c30cdc8365df9840','62b33a2d1e505241','5a9fbefe0ab6f815','0e97888f9a8767da','08bb8764f1840179')
$candidateRoot=Join-Path $repo 'artifacts/rebirth-contact-shared-repeat-candidate-20260831-v1'
$candidatePath=Join-Path $candidateRoot 'candidate.json'
$candidate=Read-Json $candidatePath
if($candidate.implementation -ne 'Rebirth' -or $candidate.reconstruction -ne 'SharedQuad' -or $candidate.sampleCount -ne 16 -or ($candidate.variants.shaderHash -join ',') -cne ($expectedHashes -join ',')) {throw 'Require the exact five-variant 16-sample shared donor candidate.'}
Assert-Sources $candidate
Assert-Hash (Join-Path $PSScriptRoot 'New-IntergradeContactShadowCandidate.ps1') $candidate.generatorSha256
Assert-Hash (Join-Path $repo 'artifacts/rebirth-contact-shared-boundary-20260831-v2/boundary.json') $candidate.sharedBoundarySha256
$evidence=@()
foreach($name in @('rebirth-contact-shared-single-interface-20260831-v3','rebirth-contact-shared-repeat-interface-20260831-v2')) {
    $path=Join-Path $repo "artifacts/$name/manifest.json"
    $check=Read-Json $path
    $iterations=if($name -match 'repeat'){8}else{1}
    if($check.result -ne 'passed-shared-interface-only' -or $check.creationChecks -ne 15 -or $check.groupsPassed -ne 1200 -or $check.laneCases -ne (307200*$iterations) -or $check.lightIterationsPerDispatch -ne $iterations -or $check.qualityGatePassed -ne $false) {throw 'Incomplete interface evidence.'}
    Assert-Hash $candidatePath $check.candidateManifestSha256
    Assert-Sources $check
    Assert-Hash (Join-Path $PSScriptRoot 'Test-RebirthSharedContactInterface.ps1') $check.scriptSha256
    Assert-Hash (Join-Path $check.testBuildDirectory 'manifest.json') $check.testManifestSha256
    Assert-Hash (Join-Path $check.testBuildDirectory 'ContactShadowWarpTest.exe') $check.runnerSha256
    foreach($v in $candidate.variants) {
        $row=@($check.variants|Where-Object shaderHash -eq $v.shaderHash)
        if($row.Count -ne 1 -or $row[0].candidateSha256 -ne $v.candidateSha256 -or $row[0].groupsPassed -ne 240) {throw 'Per-variant interface evidence mismatch.'}
        $fixture=if($iterations -eq 8){$v.repeatedFixture}else{$v.injectionFixture}
        Assert-Hash (Join-Path $candidateRoot $fixture) $row[0].fixtureSha256
    }
    $evidence+=@{path=$path;sha256=(Get-FileHash $path).Hash;scope=$check.result}
}
$capturePath=Join-Path $repo 'artifacts/rebirth-contact-capture-shared-comparison-20260831-v2/comparison.json'
$capture=Read-Json $capturePath
if($capture.result -ne 'passed-reconstruction-identity-only' -or $capture.lights.Count -ne 5 -or @($capture.lights|Where-Object {-not $_.shared.bitIdenticalToRecompute -or $_.shared.samplesVerified -ne 518400}).Count) {throw 'Missing matched capture equivalence.'}
foreach($entry in @($capture.rawManifest,$capture.quadManifest,$capture.sharedManifest)) {Assert-Hash $entry.path $entry.sha256; Assert-Sources (Read-Json $entry.path)}
foreach($entry in $capture.analysisInputs.PSObject.Properties.Value) {Assert-Hash $entry.path $entry.sha256}
foreach($entry in $capture.sources.PSObject.Properties) {Assert-Hash (Join-Path $PSScriptRoot $entry.Name) $entry.Value}
$evidence+=@{path=$capturePath;sha256=(Get-FileHash $capturePath).Hash;scope=$capture.result}
$motionPath=Join-Path $repo 'artifacts/rebirth-contact-experiment-motion16-20260831-v1/manifest.json'
$motion=Read-Json $motionPath
Assert-Sources $motion
if($motion.regressionDetected -ne $true -or $motion.samples -ne 16 -or $motion.framesPerScene -ne 96) {throw 'Expected disclosed motion evidence changed; reassess rather than silently clearing the failure.'}
$evidence+=@{path=$motionPath;sha256=(Get-FileHash $motionPath).Hash;scope='FAILED synthetic motion; explicitly acknowledged, not waived as passing'}
$gateHashes=@(foreach($name in @('Assert-IntergradeContactMotionGate.ps1','Assert-IntergradeContactSoftwareGate.ps1','Stage-IntergradeContactAllLights.ps1')) {@{path="tools/$name";sha256=(Get-FileHash (Join-Path $PSScriptRoot $name)).Hash}})
$priorGenerated=Join-Path $repo 'artifacts/generated-runtime/FF7RemakeIntergradeContactAllLights-live-v1'
$priorBaseline=Read-Json (Join-Path $priorGenerated 'live-reload-baseline.json')
$prior=Read-Json $priorBaseline.installReceipt
$live=[IO.Path]::GetFullPath($prior.targetRoot).TrimEnd('\')
$exe=Join-Path $live 'ff7remake_.exe'
$allowedPayload=@($expectedHashes|ForEach-Object {"ShaderFixes/$_-cs.txt"})+@('Mods/ContactShadows.ini')
if(@(Compare-Object ($allowedPayload|Sort-Object) ($prior.files.relativePath|Sort-Object)).Count) {throw 'Unexpected predecessor payload set.'}
function Assert-Predecessor {
    Assert-Hash $exe $prior.executable.sha256
    foreach($f in $prior.files) {Assert-Hash (Join-Path $live $f.relativePath) $f.installedSha256}
    foreach($f in $priorBaseline.protectedLiveFiles) {Assert-Hash (Join-Path $live $f.path) $f.sha256}
    $expected=@($allowedPayload)+@('Mods/ContactShadowCapture.ini','Mods/UE4EffectsGenerated.ini','ShaderFixes/41f1bf8b79d01319-ps.txt')
    $active=@(Get-ChildItem -LiteralPath (Join-Path $live 'Mods') -Recurse -File -Filter '*.ini')+@(Get-ChildItem -LiteralPath (Join-Path $live 'ShaderFixes') -Recurse -File)
    $actual=@($active|ForEach-Object {$_.FullName.Substring($live.Length+1).Replace('\','/')})
    if(@(Compare-Object ($expected|Sort-Object) ($actual|Sort-Object)).Count) {throw 'Unexpected live shader/INI files.'}
    $process=Get-Process -Id $priorBaseline.processId -ErrorAction Stop
    if($process.Path -ne $exe -or -not $process.Responding) {throw 'Expected game process unavailable; rebaseline before installation.'}
    if((Get-Item -LiteralPath $priorBaseline.logPath).Length -lt $priorBaseline.byteOffset) {throw 'Game log restarted.'}
}
Assert-Predecessor
if(-not $PSCmdlet.ShouldProcess($output,'Prepare acknowledged experimental donor package; failed motion gate remains failed; default OFF')) {return}
foreach($part in @('','ShaderFixes','Mods','validation','preinstall-backup')) {$null=New-Item -ItemType Directory -Path (Join-Path $output $part)}
$assembler=Join-Path $repo 'artifacts/shader-assembler-build/bin/cmd_Decompiler.exe'
$files=@()
$lines=[Collections.Generic.List[string]]::new()
foreach($line in @('; EXPERIMENTAL faithful Rebirth donor port for Remake DX11.',
    '; Known synthetic motion artifacts. NOT quality-approved or release-ready.',
    '; Home toggles donor OFF/ON. Native math retained when OFF; hardware cost unverified.',
    '; New non-persistent variable prevents inheriting the previous experiment state.',
    '[Constants]','global $ue4fx_rebirth_contact_experiment_v1 = 0','',
    '[KeyUE4FXContactHome]','key = no_modifiers VK_HOME','type = cycle','smart = true',
    '$ue4fx_rebirth_contact_experiment_v1 = 0, 1','')) {$lines.Add($line)}
foreach($v in $candidate.variants) {
    Assert-Hash (Join-Path $candidateRoot $v.binary) $v.candidateSha256
    $original=Join-Path $candidateRoot "validation/$($v.shaderHash)-original.bin"
    Assert-Hash $original $v.originalSha256
    if(-not $v.roundTripByteIdentical -or -not $v.maskedContributionIdentityLanes -or -not $v.sharedGroup -or $v.sharedMemoryBytes -ne 1024) {throw 'Candidate invariant missing.'}
    $relative="ShaderFixes/$($v.shaderHash)-cs.txt"
    Copy-Item -LiteralPath (Join-Path $candidateRoot $v.assembly) -Destination (Join-Path $output $relative)
    $check=Join-Path $output "validation/$($v.shaderHash)-payload.asm"
    Copy-Item -LiteralPath (Join-Path $output $relative) -Destination $check
    $messages=& $assembler -a --copy-reflection $original $check 2>&1
    if($LASTEXITCODE -ne 0) {throw "Payload assembly failed: $($v.shaderHash): $messages"}
    [IO.File]::WriteAllText(($check+'.log'),($messages|Out-String),$utf8)
    Assert-Hash ([IO.Path]::ChangeExtension($check,'.shdr')) $v.candidateSha256
    $files+=@{relativePath=$relative;sha256=(Get-FileHash (Join-Path $output $relative)).Hash}
    foreach($line in @("[ShaderOverrideUE4FXContact$($v.shaderHash)]","hash = $($v.shaderHash)",
        'x31 = $ue4fx_rebirth_contact_experiment_v1','y31 = -1','z31 = 1','w31 = 100','')) {$lines.Add($line)}
}
$relative='Mods/ContactShadows.ini'
[IO.File]::WriteAllText((Join-Path $output $relative),($lines -join "`r`n")+"`r`n",$utf8)
$files+=@{relativePath=$relative;sha256=(Get-FileHash (Join-Path $output $relative)).Hash}
$manifest=[ordered]@{
    schemaVersion=1;adapterId='FF7RemakeIntergradeContactShadows';mode='rebirth-donor-shared-experiment-v1'
    createdAtUtc=[DateTime]::UtcNow.ToString('o');licensedRegexDependency=$false;diagnosticOnly=$true
    runtimeEligible=$false;releaseEligible=$false;qualityGatePassed=$false;knownMotionArtifacts=$true
    experimentalTestAuthorized=$true;authorization='User confirmed disclosed experimental comparison with oka; no release approval'
    executable=$prior.executable;files=$files;evidence=$evidence;unchangedReleaseGates=$gateHashes
    candidateManifestSha256=(Get-FileHash $candidatePath).Hash;stagerSha256=(Get-FileHash $PSCommandPath).Hash
    implementation='Rebirth';reconstruction='SharedQuad';samples=16;selectedLight=-1;strength=1;rayLength=100
    key='Home';defaultEnabled=$false;predecessorReceipt=$priorBaseline.installReceipt
    protectedLiveFiles=$priorBaseline.protectedLiveFiles;liveTested=$false;performanceTested=$false
    limitations=@('Known synthetic false shadows, misses and motion variation','Native temporal phase and hardware cost unverified','OFF preserves native lighting math, not original shader execution cost','Home compares only this effect; other installed adjustments unchanged')
}
Write-Json (Join-Path $output 'runtime-manifest.json') $manifest
Copy-Item -LiteralPath (Join-Path $repo 'licenses/ShaderInjector-MIT.txt') -Destination (Join-Path $output 'ShaderInjector-MIT.txt')
if($Install -and $PSCmdlet.ShouldProcess($live,'Install acknowledged experimental donor with full predecessor backup; no automatic reload')) {
    Assert-Predecessor
    $installPath=Join-Path $output 'install-receipt.json'
    # Snapshot ALL overwritten files before the generic installer changes any one.
    foreach($f in $prior.files) {
        $backup=Join-Path $output ('preinstall-backup/'+$f.relativePath)
        $null=New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force
        Copy-Item -LiteralPath (Join-Path $live $f.relativePath) -Destination $backup
        Assert-Hash $backup $f.installedSha256
    }
    $offset=(Get-Item -LiteralPath $priorBaseline.logPath).Length
    $rollback=@{targetRoot=$live;predecessorReceipt=$priorBaseline.installReceipt;files=@(foreach($f in $prior.files){@{relativePath=$f.relativePath;originalSha256=$f.installedSha256;experimentalSha256=($files|Where-Object relativePath -eq $f.relativePath).sha256}})}
    Write-Json (Join-Path $output 'rollback-manifest.json') $rollback
    try {
        $gameRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $live))
        & (Join-Path $PSScriptRoot 'Install-UE4GeneratedRuntimeOverlay.ps1') -GeneratedRuntimeDirectory $output -GameRoot $gameRoot -InstallManifestPath $installPath
        foreach($f in $files) {Assert-Hash (Join-Path $live $f.relativePath) $f.sha256}
        foreach($f in $priorBaseline.protectedLiveFiles) {Assert-Hash (Join-Path $live $f.path) $f.sha256}
        foreach($f in $gateHashes) {Assert-Hash (Join-Path $repo $f.path) $f.sha256}
        $baseline=@{schemaVersion=1;mode=$manifest.mode;processId=$priorBaseline.processId;capturedAtUtc=[DateTime]::UtcNow.ToString('o');logPath=$priorBaseline.logPath;byteOffset=$offset;installReceipt=$installPath;expectedShaders=$expectedHashes;defaultEnabled=$false;key='Home';reloadRequired=$true;protectedLiveFiles=$priorBaseline.protectedLiveFiles}
        Write-Json (Join-Path $output 'live-reload-baseline.json') $baseline
    } catch {
        $failure=$_
        foreach($f in $rollback.files) {
            $destination=Join-Path $live $f.relativePath
            $backup=Join-Path $output ('preinstall-backup/'+$f.relativePath)
            Assert-Hash $backup $f.originalSha256
            if(Test-Path -LiteralPath $destination) {
                $current=(Get-FileHash -LiteralPath $destination).Hash
                if($current -ne $f.originalSha256 -and $current -ne $f.experimentalSha256) {throw "Install failed and concurrent change prevents automatic rollback: $destination. Original backup: $backup. Initial error: $failure"}
            }
            Copy-Item -LiteralPath $backup -Destination $destination -Force
            Assert-Hash $destination $f.originalSha256
        }
        throw $failure
    }
}
[pscustomobject]@{State='experimental-donor-package-prepared';Installed=[bool]$Install;Output=$output;Key='Home';Default='OFF';KnownMotionArtifacts=$true;QualityGatePassed=$false;ReloadSent=$false}
