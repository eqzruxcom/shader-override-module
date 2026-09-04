[CmdletBinding()]
param([Parameter(Mandatory)][string]$RefinementDirectory,
    [Parameter(Mandatory)][string]$FloatCheckBuildDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$fork=(Resolve-Path -LiteralPath $RefinementDirectory).Path
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(-not $output.StartsWith((Join-Path $repo 'artifacts')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Use a fresh artifacts child.'}
$build=(Resolve-Path -LiteralPath $FloatCheckBuildDirectory).Path
$receipt=Get-Content -LiteralPath (Join-Path $build 'manifest.json') -Raw|ConvertFrom-Json
$runner=Join-Path $build 'RunShaderFloatChecks.exe'
if($receipt.status -ne 'passed-math-only' -or (Get-FileHash -LiteralPath $runner).Hash -ne $receipt.runnerSha256){throw 'Unverified runner.'}
$fixture='src/Tests/ContactEdgeFadeRay_cs.hlsl'
if((Get-FileHash -LiteralPath (Join-Path $repo $fixture)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $fork $fixture)).Hash){throw 'Ray fixture copies differ.'}
$null=New-Item -ItemType Directory -Path $output
$fxc='C:/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64/fxc.exe'
$utf8=[Text.UTF8Encoding]::new($false)
function Invoke-FadeTool([string]$program,[string[]]$arguments,[string]$log) {
    $messages=& $program @arguments 2>&1;$code=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $output $log),($messages|Out-String),$utf8)
    if($code -ne 0){throw "Edge-fade check failed: $log"}
    return ,@($messages)
}
function Invoke-FadeFixture([string]$root,[string]$relative,[string]$stem,[int]$count,[int]$refined) {
    $binary=Join-Path $output ($stem+'.cso')
    $null=Invoke-FadeTool $fxc @('/nologo','/Ges','/Gis','/WX','/O3','/T','cs_5_0','/E','main','/D',("EXPECT_EDGE_FADE=$refined"),'/Fo',$binary,(Join-Path $root $relative)) ($stem+'-compile.log')
    $messages=Invoke-FadeTool $runner @($binary,[string]$count) ($stem+'-checks.log')
    $values=@{}
    foreach($line in $messages){if($line -match '^PASS (\d+) actual=([^ ]+) '){$values[[int]$Matches[1]]=[double]::Parse($Matches[2],[Globalization.CultureInfo]::InvariantCulture)}}
    if($values.Count -ne $count){throw 'Incomplete numeric readback.'}
    return $values
}
$sourcePaths=@('src/Effects/Lighting/ContactEdgeFade.hlsl','src/Effects/Lighting/ContactShadowCommon.hlsl','src/Effects/Lighting/RebirthContactShadows.hlsl','src/ThirdParty/ShaderInjector/RebirthContactRay.hlsl','src/ThirdParty/ShaderInjector/RebirthContactNoise.hlsl',$fixture)
$sources=@(foreach($root in @($repo,$fork)){foreach($path in $sourcePaths){@{root=$root;path=$path;sha256=(Get-FileHash -LiteralPath (Join-Path $root $path)).Hash}}})
$sources+=@{root=$fork;path='src/Effects/Lighting/RebirthContactRayEdgeFade.hlsl';sha256=(Get-FileHash -LiteralPath (Join-Path $fork 'src/Effects/Lighting/RebirthContactRayEdgeFade.hlsl')).Hash}
$sources+=@{root=$repo;path='src/Tests/ContactEdgeFadeCases_cs.hlsl';sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'src/Tests/ContactEdgeFadeCases_cs.hlsl')).Hash}
$null=Invoke-FadeFixture $repo 'src/Tests/ContactEdgeFadeCases_cs.hlsl' 'left-edge-math' 576 0
$baseline=Invoke-FadeFixture $repo $fixture 'baseline-ray' 5120 0
$fade=Invoke-FadeFixture $fork $fixture 'fade-ray' 5120 1
$changed=@(0,0,0,0);$widthChanges=0;$zeroExact=0
foreach($rayIndex in 0..511) {
    $base=$baseline[$rayIndex*10]
    if($fade[$rayIndex*10] -ne $base){throw "Zero-width donor parity failed: $rayIndex"}
    $zeroExact++
    foreach($preset in 1..9) {
        $index=$rayIndex*10+$preset;$value=$fade[$index];$profile=[int][Math]::Floor($rayIndex/128)
        if($baseline[$index] -ne $base){throw 'Baseline unexpectedly depends on preset.'}
        if($value -lt $base-2e-6 -or $value -gt 1){throw "Fade introduced extra shadow: $index"}
        if($value -lt $fade[$index-1]-2e-6){throw "Wider fade darkened a ray: $index"}
        if($profile -ge 2 -and [Math]::Abs($value-$base) -gt 2e-6){throw "Top/bottom/right or interior changed: $index"}
        if($value-$base -gt .1){$changed[$profile]++}
        if($preset -gt 1 -and $value-$fade[$index-1] -gt .001){$widthChanges++}
    }
}
if($changed[0] -lt 10 -or $changed[1] -lt 10 -or $widthChanges -lt 10){throw 'Receiver, blocker or preset coverage is vacuous.'}
foreach($source in $sources){if((Get-FileHash -LiteralPath (Join-Path $source.root $source.path)).Hash -ne $source.sha256){throw 'Source changed during test.'}}
$manifest=@{status='passed-left-only-math-and-analytic-ray';mathChecks=576;rayChecksPerBranch=5120;zeroWidthExactRays=$zeroExact;changedOverPointOneByProfile=$changed;nontrivialPresetChanges=$widthChanges;defaultWidth=.01;sources=$sources;scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;runnerSha256=$receipt.runnerSha256;gameModified=$false;runtimeEligible=$false;limitations=@('Analytic depth, not FF7 rendering','Fade masks missing data, not overscan','No new motion, hardware-cost or native shader integration pass')}
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),($manifest|ConvertTo-Json -Depth 8)+"`n",$utf8)
$manifest|Select-Object status,mathChecks,rayChecksPerBranch,zeroWidthExactRays,changedOverPointOneByProfile,nontrivialPresetChanges|ConvertTo-Json
