[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RefinementDirectory,
    [Parameter(Mandatory)][string]$FloatCheckBuildDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$refinement=(Resolve-Path -LiteralPath $RefinementDirectory).Path
$build=(Resolve-Path -LiteralPath $FloatCheckBuildDirectory).Path
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(-not $output.StartsWith((Join-Path $repo 'artifacts')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Use a fresh workspace artifacts directory.'}
$runner=Join-Path $build 'RunShaderFloatChecks.exe'
$buildReceipt=Get-Content -LiteralPath (Join-Path $build 'manifest.json') -Raw | ConvertFrom-Json
if($buildReceipt.status -ne 'passed-math-only' -or (Get-FileHash -LiteralPath $runner).Hash -ne $buildReceipt.runnerSha256){throw 'Require the verified math-check runner.'}
$testRelative='src/Tests/ContactViewportRayCases_cs.hlsl'
if((Get-FileHash -LiteralPath (Join-Path $repo $testRelative)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $refinement $testRelative)).Hash){throw 'Both branches must use the identical fixture.'}
$fxc='C:/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64/fxc.exe'
$utf8=[Text.UTF8Encoding]::new($false)
$null=New-Item -ItemType Directory -Path $output
function Invoke-RayCheck([string]$Program,[string[]]$Arguments,[string]$Log) {
    $messages=& $Program @Arguments 2>&1
    $code=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $output $Log),($messages|Out-String),$utf8)
    if($code -ne 0){throw "Full-ray check failed: $Log"}
    return ,@($messages)
}
$records=@(foreach($profile in @(@{name='baseline';root=$repo;refined=0},@{name='viewport';root=$refinement;refined=1})) {
    $sources=@('src/Effects/Lighting/ContactShadowCommon.hlsl','src/Effects/Lighting/RebirthContactShadows.hlsl','src/ThirdParty/ShaderInjector/RebirthContactRay.hlsl','src/ThirdParty/ShaderInjector/RebirthContactNoise.hlsl',$testRelative)
    if($profile.refined){$sources+=@('src/Effects/Lighting/ContactViewportClip.hlsl','src/Effects/Lighting/RebirthContactRayViewport.hlsl')}
    $sourceRecords=@(foreach($path in $sources){@{path=$path;sha256=(Get-FileHash -LiteralPath (Join-Path $profile.root $path)).Hash}})
    foreach($samples in @(8,16,32)) {
        $stem=$profile.name+'-'+$samples
        $binary=Join-Path $output ($stem+'.cso')
        $null=Invoke-RayCheck $fxc @('/nologo','/Ges','/Gis','/WX','/O3','/T','cs_5_0','/E','main','/D',('EXPECT_VIEWPORT_REFINEMENT='+$profile.refined),'/D',('REDX11_CONTACT_SAMPLES='+$samples),'/Fo',$binary,(Join-Path $profile.root $testRelative)) ($stem+'-compile.log')
        $messages=Invoke-RayCheck $runner @($binary,'256') ($stem+'-checks.log')
        if(@($messages|Where-Object {$_ -match '^PASS \d+ '}).Count -ne 256){throw 'Incomplete full-ray checks.'}
        Write-Host "$stem : 128 full-ray fixtures / 256 checks passed."
        @{profile=$profile.name;samples=$samples;shaderSha256=(Get-FileHash -LiteralPath $binary).Hash;checks=256;root=$profile.root;sources=$sourceRecords}
    }
    foreach($source in $sourceRecords){if((Get-FileHash -LiteralPath (Join-Path $profile.root $source.path)).Hash -ne $source.sha256){throw 'Source changed during test.'}}
})
if($records.Count -ne 6){throw 'Incomplete comparison matrix.'}
$manifest=@{
    status='passed-analytic-full-ray-comparison';casesPerCompile=128;checksPerCompile=256;profiles=$records
    runnerSha256=(Get-FileHash -LiteralPath $runner).Hash;scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    gameModified=$false;liveCauseConfirmed=$false
    baselineInterpretation='Expected-result checks reproduce missed entry hits and subviewport out-of-bounds fetch coordinates; not correctness approval.'
    limits=@('Analytic depth, not captured game buffers','No motion or penumbra validation','No recovery of offscreen geometry')
}
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),($manifest|ConvertTo-Json -Depth 9)+"`n",$utf8)
Write-Output "Full-ray comparison completed: $output"
