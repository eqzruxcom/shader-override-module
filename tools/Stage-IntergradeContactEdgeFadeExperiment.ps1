[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$OutputDirectory,[switch]$Install)
# Bounded LEFT-only experiment; normal release/software/motion gates unchanged.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$fork=Join-Path $repo 'artifacts/contact-edge-fade-development-20260831-v1'
$candidateRoot=Join-Path $fork 'artifacts/fade-candidate-v2'
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if(-not $output.StartsWith((Join-Path $repo 'artifacts/generated-runtime')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Use a fresh generated-runtime child.'}
$utf8=[Text.UTF8Encoding]::new($false)
function Read-Json([string]$path){Get-Content -LiteralPath $path -Raw|ConvertFrom-Json}
function Write-Json([string]$path,$document){[IO.File]::WriteAllText($path,($document|ConvertTo-Json -Depth 12)+"`n",$utf8)}
function Assert-Hash([string]$path,[string]$sha){if($sha -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath $path).Hash -ne $sha){throw "Fingerprint mismatch: $path"}}
function Scoped-Path([string]$root,[string]$relative){
    if([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)'){throw 'Unsafe relative path'}
    $path=[IO.Path]::GetFullPath((Join-Path $root $relative))
    if(-not $path.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Path escaped scope'}
    return $path
}
function Assert-Sources([string]$root,$document){foreach($source in $document.sources){Assert-Hash (Scoped-Path $root $source.path) $source.sha256}}
$hashes=@('c30cdc8365df9840','62b33a2d1e505241','5a9fbefe0ab6f815','0e97888f9a8767da','08bb8764f1840179')
$candidatePath=Join-Path $candidateRoot 'candidate.json'
$candidate=Read-Json $candidatePath
if($candidate.implementation -ne 'Rebirth' -or $candidate.reconstruction -ne 'SharedQuad' -or $candidate.sampleCount -ne 16 -or ($candidate.variants.shaderHash -join ',') -cne ($hashes -join ',')){throw 'Wrong candidate'}
Assert-Sources $fork $candidate
Assert-Hash (Join-Path $fork 'tools/New-IntergradeContactShadowCandidate.ps1') $candidate.generatorSha256
Assert-Hash (Join-Path $fork 'artifacts/rebirth-contact-shared-boundary-20260831-v2/boundary.json') $candidate.sharedBoundarySha256
$evidence=@()
foreach($percent in @(0,1,9)){
    $path=Join-Path $fork "artifacts/fade-interface-$percent-v3/manifest.json"
    $check=Read-Json $path
    $iterations=if($percent -eq 9){8}else{1}
    if($check.result -ne 'passed-shared-interface-only' -or $check.groupsPassed -ne 1200 -or $check.creationChecks -ne 15 -or $check.laneCases -ne 307200*$iterations -or $check.lightIterationsPerDispatch -ne $iterations -or $check.edgePercent -ne $percent -or -not $check.leftOnly -or $check.qualityGatePassed -ne $false){throw 'Incomplete native integration evidence'}
    Assert-Hash $candidatePath $check.candidateManifestSha256
    Assert-Sources $fork $check
    Assert-Hash (Join-Path $fork 'tools/Test-RebirthSharedContactInterface.ps1') $check.scriptSha256
    Assert-Hash (Join-Path $check.testBuildDirectory 'manifest.json') $check.testManifestSha256
    Assert-Hash (Join-Path $check.testBuildDirectory 'ContactShadowWarpTest.exe') $check.runnerSha256
    foreach($variant in $candidate.variants){
        $row=@($check.variants|Where-Object shaderHash -eq $variant.shaderHash)
        if($row.Count -ne 1 -or $row[0].candidateSha256 -ne $variant.candidateSha256 -or $row[0].groupsPassed -ne 240){throw 'Wrong per-variant evidence'}
        $fixture=if($percent -eq 9){$variant.repeatedFixture}else{$variant.injectionFixture}
        Assert-Hash (Scoped-Path $candidateRoot $fixture) $row[0].fixtureSha256
    }
    $evidence+=@{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash;scope=$check.result;edgePercent=$percent}
}
$mathPath=Join-Path $repo 'artifacts/contact-edge-fade-tests-20260831-v3/manifest.json'
$math=Read-Json $mathPath
if($math.status -ne 'passed-left-only-math-and-analytic-ray' -or $math.zeroWidthExactRays -ne 512 -or $math.mathChecks -ne 576 -or $math.rayChecksPerBranch -ne 5120){throw 'Missing left-only numeric evidence'}
foreach($source in $math.sources){
    if($source.root -ne $repo -and $source.root -ne $fork){throw 'Wrong numeric source root'}
    Assert-Hash (Scoped-Path $source.root $source.path) $source.sha256
}
Assert-Hash (Join-Path $repo 'tools/Test-ContactEdgeFade.ps1') $math.scriptSha256
$capturePath=Join-Path $repo 'artifacts/contact-edge-fade-capture-comparison-20260831-v2/manifest.json'
$capture=Read-Json $capturePath
if($capture.status -ne 'passed-captured-visibility-comparison' -or $capture.zeroWidthBitIdenticalFiles -ne 20 -or $capture.qualityGatePassed -ne $false){throw 'Missing captured comparison'}
Assert-Hash (Join-Path $repo 'tools/Compare-ContactEdgeFadeCapture.py') $capture.scriptSha256
foreach($item in $capture.evidence){
    $evidencePath=Scoped-Path $repo $item.path
    if(-not $evidencePath.StartsWith($fork+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Capture evidence escaped fork'}
    Assert-Hash $evidencePath $item.sha256
}
foreach($percent in @(0,1,9)){Assert-Sources $fork (Read-Json (Join-Path $fork "artifacts/fade-capture-$percent-v2/manifest.json"))}
foreach($path in @($mathPath,$capturePath)){$evidence+=@{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash;scope='Offline only; not live quality'}}
$priorRoot=Join-Path $repo 'artifacts/generated-runtime/FF7RemakeIntergradeRebirthContact-experiment-live-v1'
$baseline=Read-Json (Join-Path $priorRoot 'live-reload-baseline.json')
$prior=Read-Json $baseline.installReceipt
$live=[IO.Path]::GetFullPath($prior.targetRoot).TrimEnd('\')
if($live -cne 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64'){throw 'Wrong game root'}
$allowed=@($hashes|ForEach-Object {"ShaderFixes/$_-cs.txt"})+@('Mods/ContactShadows.ini')
if($prior.files.Count -ne 6 -or @(Compare-Object ($allowed|Sort-Object) ($prior.files.relativePath|Sort-Object)).Count){throw 'Unexpected predecessor payload'}
function Assert-Predecessor {
    Assert-Hash (Join-Path $live 'ff7remake_.exe') $prior.executable.sha256
    foreach($file in $prior.files){Assert-Hash (Scoped-Path $live $file.relativePath) $file.installedSha256}
    foreach($file in $baseline.protectedLiveFiles){Assert-Hash (Scoped-Path $live $file.path) $file.sha256}
    $expected=$allowed+@('Mods/UE4EffectsGenerated.ini','Mods/ContactShadowCapture.ini','ShaderFixes/41f1bf8b79d01319-ps.txt')
    $active=@(Get-ChildItem -LiteralPath (Join-Path $live 'Mods') -File -Recurse -Filter '*.ini')+@(Get-ChildItem -LiteralPath (Join-Path $live 'ShaderFixes') -File -Recurse)
    $actual=@($active|ForEach-Object {$_.FullName.Substring($live.Length+1).Replace('\','/')})
    if(@(Compare-Object ($expected|Sort-Object) ($actual|Sort-Object)).Count){throw 'Other active files appeared; reassess'}
    # Inspect live numeric keys and the chosen slot outside our replaced INI.
    foreach($path in @((Join-Path $live 'd3dx.ini'),(Join-Path $live 'Mods/UE4EffectsGenerated.ini'),(Join-Path $live 'Mods/ContactShadowCapture.ini'))){
        $text=Get-Content -LiteralPath $path -Raw
        if($text -match '(?im)^\s*[xyzw]29\s*=' -or $text -match '(?im)^\s*key\s*=\s*(?:no_modifiers\s+)?(?:VK_)?[0-9]\s*$'){throw 'Numeric key or row29 conflict'}
    }
    $game=Get-Process -Id $baseline.processId -ErrorAction Stop
    if($game.Path -ne $prior.executable.path -or -not $game.Responding){throw 'Expected game process unavailable'}
}
Assert-Predecessor
if(-not $PSCmdlet.ShouldProcess($output,'Prepare reversible LEFT-edge fade experiment, starting at zero percent')){return}
foreach($part in @('','ShaderFixes','Mods','validation','preinstall-backup')){$null=New-Item -ItemType Directory -Path (Join-Path $output $part)}
$files=@()
$assembler=Join-Path $repo 'artifacts/shader-assembler-build/bin/cmd_Decompiler.exe'
foreach($variant in $candidate.variants){
    if(-not $variant.roundTripByteIdentical -or -not $variant.maskedContributionIdentityLanes -or -not $variant.sharedGroup -or $variant.sharedMemoryBytes -ne 1024){throw 'Native preservation invariant missing'}
    $original=Join-Path $candidateRoot "validation/$($variant.shaderHash)-original.bin"
    Assert-Hash $original $variant.originalSha256
    Assert-Hash (Scoped-Path $candidateRoot $variant.binary) $variant.candidateSha256
    $relative="ShaderFixes/$($variant.shaderHash)-cs.txt"
    Copy-Item -LiteralPath (Scoped-Path $candidateRoot $variant.assembly) -Destination (Join-Path $output $relative)
    $roundtrip=Join-Path $output "validation/$($variant.shaderHash)-payload.asm"
    Copy-Item -LiteralPath (Join-Path $output $relative) -Destination $roundtrip
    $messages=& $assembler -a --copy-reflection $original $roundtrip 2>&1
    if($LASTEXITCODE -ne 0){throw 'Payload assembly failed'}
    Assert-Hash ([IO.Path]::ChangeExtension($roundtrip,'.shdr')) $variant.candidateSha256
    $files+=@{relativePath=$relative;sha256=(Get-FileHash -LiteralPath (Join-Path $output $relative)).Hash}
}
$lines=@('; LEFT-only edge fade; experimental, not release-ready.',
    '; Starts with working donor contact shadows ON and fade 0%.',
    '; 0 = no fade, 1..9 = 1%..9% of viewport width. Digits also enable contact.',
    '; Home toggles all added contact shadows. No native shadows, crop or FOV changed.',
    '[Constants]','global $ue4fx_contact_edge_v1 = 1','global $ue4fx_contact_edge_width_v1 = 0','',
    '[KeyUE4FXContactHome]','key = no_modifiers VK_HOME','type = cycle','smart = true',
    '$ue4fx_contact_edge_v1 = 0, 1','')
foreach($percent in 0..9){
    $value=([double]$percent/100).ToString('0.00',[Globalization.CultureInfo]::InvariantCulture)
    $lines+=@("[KeyUE4FXContactEdge$percent]","key = no_modifiers $percent",'$ue4fx_contact_edge_v1 = 1',('$ue4fx_contact_edge_width_v1 = '+$value),'')
}
foreach($hash in $hashes){$lines+=@("[ShaderOverrideUE4FXContact$hash]","hash = $hash",'x29 = $ue4fx_contact_edge_width_v1','x31 = $ue4fx_contact_edge_v1','y31 = -1','z31 = 1','w31 = 100','')}
[IO.File]::WriteAllText((Join-Path $output 'Mods/ContactShadows.ini'),($lines -join "`r`n")+"`r`n",$utf8)
$controlText=Get-Content -LiteralPath (Join-Path $output 'Mods/ContactShadows.ini') -Raw
foreach($percent in 0..9){
    $section=[regex]::Match($controlText,'(?ms)^\[KeyUE4FXContactEdge'+$percent+'\]\r?\n(.*?)(?=^\[|\z)')
    $expectedWidth=([double]$percent/100).ToString('0.00',[Globalization.CultureInfo]::InvariantCulture)
    if(-not $section.Success -or $section.Groups[1].Value -notmatch ('(?m)^key = no_modifiers '+$percent+'\r?$') -or
        $section.Groups[1].Value -notmatch ('(?m)^\$ue4fx_contact_edge_width_v1 = '+[regex]::Escape($expectedWidth)+'\r?$') -or
        $section.Groups[1].Value -notmatch '(?m)^\$ue4fx_contact_edge_v1 = 1\r?$'){throw 'Direct numeric preset mismatch'}
}
if(([regex]::Matches($controlText,'(?m)^x29 = \$ue4fx_contact_edge_width_v1\r?$')).Count -ne 5 -or
    $controlText -notmatch '(?m)^global \$ue4fx_contact_edge_width_v1 = 0\r?$'){throw 'Wrong fade binding or initial width'}
$files+=@{relativePath='Mods/ContactShadows.ini';sha256=(Get-FileHash -LiteralPath (Join-Path $output 'Mods/ContactShadows.ini')).Hash}
$gates=@(foreach($name in @('Assert-IntergradeContactMotionGate.ps1','Assert-IntergradeContactSoftwareGate.ps1','Stage-IntergradeContactAllLights.ps1')){@{path="tools/$name";sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash}})
$manifest=@{schemaVersion=1;adapterId='FF7RemakeIntergradeContactShadows';mode='rebirth-contact-left-edge-fade-experiment-v1';licensedRegexDependency=$false;diagnosticOnly=$true;runtimeEligible=$false;releaseEligible=$false;qualityGatePassed=$false;knownMotionArtifacts=$true;authorization='User requested subtle left-edge changes, 0=0% and direct 1..9 percentages';implementation='Rebirth';reconstruction='SharedQuad';samples=16;executable=$prior.executable;files=$files;evidence=$evidence;candidateManifestSha256=(Get-FileHash -LiteralPath $candidatePath).Hash;stagerSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;unchangedReleaseGates=$gates;protectedLiveFiles=$baseline.protectedLiveFiles;key='Home';defaultEnabled=$true;defaultFadePercent=0;leftOnly=$true;softnessIncluded=$false;overscanIncluded=$false;liveTested=$false;performanceTested=$false;predecessorReceipt=$baseline.installReceipt;limitations=@('Only added contact visibility fades; no offscreen geometry recovered','Original donor clipping retained; rejected viewport experiment not included','Old synthetic motion failures remain; new fade not motion-quality approved','OFF preserves native math, not original execution cost','A left-edge blocker can cast onto a receiver farther inside the screen')}
Write-Json (Join-Path $output 'runtime-manifest.json') $manifest
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
if($Install -and $PSCmdlet.ShouldProcess($live,'Install five contact shaders plus their numeric/Home INI; no reload or keys')){
    Assert-Predecessor
    $offset=(Get-Item -LiteralPath $baseline.logPath).Length
    $installPath=Join-Path $output 'install-receipt.json'
    try {
        & (Join-Path $PSScriptRoot 'Install-UE4GeneratedRuntimeOverlay.ps1') -GeneratedRuntimeDirectory $output -GameRoot (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $live))) -InstallManifestPath $installPath
        foreach($file in $files){Assert-Hash (Scoped-Path $live $file.relativePath) $file.sha256}
        foreach($file in $baseline.protectedLiveFiles){Assert-Hash (Scoped-Path $live $file.path) $file.sha256}
        foreach($file in $gates){Assert-Hash (Scoped-Path $repo $file.path) $file.sha256}
        Write-Json (Join-Path $output 'live-reload-baseline.json') @{schemaVersion=1;mode=$manifest.mode;processId=$baseline.processId;capturedAtUtc=[DateTime]::UtcNow.ToString('o');logPath=$baseline.logPath;byteOffset=$offset;installReceipt=$installPath;expectedShaders=$hashes;defaultEnabled=$true;defaultFadePercent=0;key='Home';reloadRequired=$true;protectedLiveFiles=$baseline.protectedLiveFiles}
        $installed=$true
    } catch {
        $failure=$_
        foreach($file in $rollback.files){
            Assert-Hash (Join-Path $output ('preinstall-backup/'+$file.relativePath)) $file.originalSha256
            $current=(Get-FileHash -LiteralPath (Scoped-Path $live $file.relativePath)).Hash
            if($current -ne $file.originalSha256 -and $current -ne $file.experimentalSha256){throw "Unrelated edit prevents rollback: $($file.relativePath). Backups: $output. Initial failure: $failure"}
        }
        foreach($file in $rollback.files){Copy-Item -LiteralPath (Join-Path $output ('preinstall-backup/'+$file.relativePath)) -Destination (Scoped-Path $live $file.relativePath) -Force;Assert-Hash (Scoped-Path $live $file.relativePath) $file.originalSha256}
        throw $failure
    }
}
[pscustomobject]@{State='left-edge-fade-prepared';Installed=$installed;Output=$output;Default='Contact ON, fade 0%';Keys='0=0%, 1..9=1%..9%, Home=contact toggle';ReloadSent=$false}
