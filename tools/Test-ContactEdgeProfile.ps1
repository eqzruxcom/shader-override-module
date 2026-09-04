[CmdletBinding()]
param([Parameter(Mandatory)][string]$RefinementDirectory,[Parameter(Mandatory)][string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$fork=(Resolve-Path -LiteralPath $RefinementDirectory).Path
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(-not $output.StartsWith((Join-Path $repo 'artifacts')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Use a fresh artifacts child'}
$build=Join-Path $repo 'artifacts/contact-viewport-clip-20260831-v3'
$prior=Get-Content -LiteralPath (Join-Path $build 'manifest.json') -Raw|ConvertFrom-Json
$runner=Join-Path $build 'RunShaderFloatChecks.exe'
if($prior.status -ne 'passed-math-only' -or (Get-FileHash -LiteralPath $runner).Hash -ne $prior.runnerSha256){throw 'Unverified runner'}
$null=New-Item -ItemType Directory -Path $output
$utf8=[Text.UTF8Encoding]::new($false)
$fxc='C:/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64/fxc.exe'
$sourcePaths=@('src/Tests/ContactEdgeProfileCases_cs.hlsl','src/Tests/ContactEdgeProfileRay_cs.hlsl','src/Effects/Lighting/ContactEdgeFade.hlsl','src/Effects/Lighting/RebirthContactRayEdgeFade.hlsl','src/Effects/Lighting/RebirthContactShadows.hlsl','src/Effects/Lighting/ContactShadowCommon.hlsl','src/ThirdParty/ShaderInjector/RebirthContactNoise.hlsl')
$sources=@(foreach($path in $sourcePaths){@{path=$path;sha256=(Get-FileHash -LiteralPath (Join-Path $fork $path)).Hash}})
function Invoke-Profile([string]$stem,[string]$source,[int]$count){
    $binary=Join-Path $output ($stem+'.cso')
    $messages=& $fxc /nologo /Ges /Gis /WX /O3 /T cs_5_0 /E main /Fo $binary (Join-Path $fork $source) 2>&1
    $code=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $output ($stem+'-compile.log')),($messages|Out-String),$utf8)
    if($code -ne 0){throw 'Profile fixture compile failed'}
    $messages=& $runner $binary ([string]$count) 2>&1
    $code=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $output ($stem+'-checks.log')),($messages|Out-String),$utf8)
    if($code -ne 0){throw 'Profile fixture execution failed'}
    $values=@{}
    foreach($line in $messages){if($line -match '^PASS (\d+) actual=([^ ]+) '){$values[[int]$Matches[1]]=[double]::Parse($Matches[2],[Globalization.CultureInfo]::InvariantCulture)}}
    if($values.Count -ne $count){throw 'Incomplete profile output'}
    return $values
}
$math=Invoke-Profile 'profile-math' $sourcePaths[0] 1056
$maxStep=0.0
foreach($i in 1..511){
    $step=$math[32+$i]-$math[31+$i]
    if($step -lt -2e-5 -or [Math]::Abs($math[32+$i]-$math[1055-$i]) -gt 2e-5){throw 'Curve is nonmonotonic or direction-dependent'}
    $maxStep=[Math]::Max($maxStep,$step)
}
if($maxStep -gt .006){throw 'Unexpected discontinuity in sampled fade curve'}
$rays=Invoke-Profile 'profile-rays' $sourcePaths[1] 1536
$changed=0
foreach($i in 0..511){
    $base=$rays[$i*3];$old=$rays[$i*3+1];$new=$rays[$i*3+2]
    if($old -lt $base-2e-6 -or $new -lt $old-2e-6 -or $new -gt 1){throw 'Profile introduced extra shadow'}
    if($i -ge 256 -and [Math]::Abs($new-$base) -gt 2e-6){throw 'Interior/top/bottom/right changed'}
    if($new-$old -gt .001){$changed++}
}
if($changed -lt 10){throw 'Vacuous full-ray profile comparison'}
foreach($source in $sources){if((Get-FileHash -LiteralPath (Join-Path $fork $source.path)).Hash -ne $source.sha256){throw 'Source changed during test'}}
$report=@{status='passed-left-cutoff-profile';cutoffPercent=.5;fullStrengthPercent=4;mathChecks=1056;rayChecks=1536;maxCurveStep=$maxStep;changedRays=$changed;sources=$sources;scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;runnerSha256=$prior.runnerSha256;qualityGatePassed=$false;gameModified=$false;limitations=@('Curve reversal tested, not game motion or sudden hit-validity changes','No temporal history, engine overscan or hardware performance claim')}
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),($report|ConvertTo-Json -Depth 7)+"`n",$utf8)
$report|Select-Object status,mathChecks,rayChecks,maxCurveStep,changedRays|ConvertTo-Json
