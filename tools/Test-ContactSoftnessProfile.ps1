[CmdletBinding()]
param([Parameter(Mandatory)][string]$FloatCheckBuildDirectory,[Parameter(Mandatory)][string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(-not $output.StartsWith((Join-Path $repo 'artifacts')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Use a fresh artifacts directory.'}
$build=(Resolve-Path -LiteralPath $FloatCheckBuildDirectory).Path
$runner=Join-Path $build 'RunShaderFloatChecks.exe'
$buildReceipt=Get-Content -LiteralPath (Join-Path $build 'manifest.json') -Raw|ConvertFrom-Json
if((Get-FileHash -LiteralPath $runner).Hash -ne $buildReceipt.runnerSha256){throw 'Runner fingerprint changed.'}
$sources=@(foreach($path in @('src/Effects/Lighting/RebirthContactSoftness.hlsl','src/Effects/Lighting/RebirthContactShadows.hlsl','src/Effects/Lighting/ContactShadowCommon.hlsl','src/ThirdParty/ShaderInjector/RebirthContactRay.hlsl','src/ThirdParty/ShaderInjector/RebirthContactNoise.hlsl','src/Tests/ContactSoftnessProfile_cs.hlsl','tools/Test-ContactSoftnessProfile.ps1')){@{path=$path;sha256=(Get-FileHash -LiteralPath (Join-Path $repo $path)).Hash}})
$null=New-Item -ItemType Directory -Path $output
$utf8=[Text.UTF8Encoding]::new($false)
$fxc='C:/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64/fxc.exe'
$binary=Join-Path $output 'profiles.cso'
$messages=& $fxc /nologo /Ges /Gis /WX /O3 /T cs_5_0 /E main /Fo $binary (Join-Path $repo 'src/Tests/ContactSoftnessProfile_cs.hlsl') 2>&1
$code=$LASTEXITCODE
[IO.File]::WriteAllText((Join-Path $output 'compile.log'),($messages|Out-String),$utf8)
if($code -ne 0){throw 'Softness fixture compile failed.'}
$messages=& $runner $binary 2048 2>&1
$code=$LASTEXITCODE
[IO.File]::WriteAllText((Join-Path $output 'checks.log'),($messages|Out-String),$utf8)
if($code -ne 0){throw 'Softness fixture numeric checks failed.'}
$values=@{}
foreach($line in $messages){if($line -match '^PASS (\d+) actual=([^ ]+) '){$values[[int]$Matches[1]]=[double]::Parse($Matches[2],[Globalization.CultureInfo]::InvariantCulture)}}
if($values.Count -ne 2048){throw 'Incomplete readback.'}
$profiles=@(foreach($profile in 0..1){
    $hard=@();$soft=@()
    foreach($point in 0..255){$index=($profile*256+$point)*4;$hard+=$values[$index];$soft+=$values[$index+1]}
    if($hard[0] -ne 1 -or $soft[0] -ne 1 -or $hard[255] -ge .15 -or [Math]::Abs($soft[255]-$hard[255]) -gt .02){throw 'Lit or solid-shadow interior was weakened.'}
    $hardIntermediate=0;$softIntermediate=0;$nonMonotonic=0
    foreach($point in 0..255){
        $normalizedHard=($hard[$point]-$hard[255])/(1-$hard[255]);$normalizedSoft=($soft[$point]-$soft[255])/(1-$soft[255])
        if($normalizedHard -gt .05 -and $normalizedHard -lt .95){$hardIntermediate++}
        if($normalizedSoft -gt .05 -and $normalizedSoft -lt .95){$softIntermediate++}
        if($point -gt 0 -and $soft[$point] -gt $soft[$point-1]+1e-5){$nonMonotonic++}
    }
    if($hardIntermediate -ne 0 -or $softIntermediate -lt 2 -or $nonMonotonic -ne 0){throw 'Did not produce a monotonic soft transition from the hard edge.'}
    @{blockerDistance=$(if($profile -eq 0){1}else{3});hardInterior=$hard[255];softInterior=$soft[255];hardTransitionPoints=$hardIntermediate;softTransitionPoints=$softIntermediate;nonMonotonicSteps=$nonMonotonic}
})
if($profiles[1].softTransitionPoints -le $profiles[0].softTransitionPoints){throw 'Transition did not widen with blocker separation.'}
foreach($source in $sources){if((Get-FileHash -LiteralPath (Join-Path $repo $source.path)).Hash -ne $source.sha256){throw 'Source changed during check.'}}
$manifest=@{status='passed-analytic-soft-edge-profile-only';profiles=$profiles;numericChecks=2048;sources=$sources;binarySha256=(Get-FileHash -LiteralPath $binary).Hash;runnerSha256=(Get-FileHash -LiteralPath $runner).Hash;gameModified=$false;runtimeEligible=$false;limitations=@('Eight donor rays per traced receiver; GPU cost unmeasured','Finite sampling may still show steps or motion noise','Virtual emitter radius, not a verified native light binding','Synthetic depth-edge profiles, not FF7 visuals or full area-light truth')}
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),($manifest|ConvertTo-Json -Depth 8)+"`n",$utf8)
$profiles|ConvertTo-Json
Write-Output 'Softness profile passed. Not installed; not a motion/performance approval.'
