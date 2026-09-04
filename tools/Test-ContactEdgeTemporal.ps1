[CmdletBinding()]
param([Parameter(Mandatory)][string]$RefinementDirectory,
      [Parameter(Mandatory)][string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$fork=(Resolve-Path -LiteralPath $RefinementDirectory).Path
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(-not $output.StartsWith((Join-Path $repo 'artifacts')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Use a fresh artifacts child'}
$build=Join-Path $repo 'artifacts/contact-viewport-clip-20260831-v3'
$runner=Join-Path $build 'RunShaderFloatChecks.exe'
$prior=Get-Content -LiteralPath (Join-Path $build 'manifest.json') -Raw|ConvertFrom-Json
if($prior.status -ne 'passed-math-only' -or (Get-FileHash -LiteralPath $runner).Hash -ne $prior.runnerSha256){throw 'Runner fingerprint mismatch'}
$sourcePaths=@('src/Effects/Lighting/ContactEdgeTemporal.hlsl','src/Tests/ContactEdgeTemporalCases_cs.hlsl')
$sources=@(foreach($path in $sourcePaths){@{path=$path;sha256=(Get-FileHash -LiteralPath (Join-Path $fork $path)).Hash}})
$null=New-Item -ItemType Directory -Path $output
$utf8=[Text.UTF8Encoding]::new($false)
$fxc='C:/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64/fxc.exe'
$binary=Join-Path $output 'temporal.cso'
$messages=& $fxc /nologo /Ges /Gis /WX /O3 /T cs_5_0 /E main /Fo $binary (Join-Path $fork $sourcePaths[1]) 2>&1
$code=$LASTEXITCODE
[IO.File]::WriteAllText((Join-Path $output 'compile.log'),($messages|Out-String),$utf8)
if($code -ne 0){throw 'Temporal fixture compile failed'}
$messages=& $runner $binary 2048 2>&1
$code=$LASTEXITCODE
[IO.File]::WriteAllText((Join-Path $output 'checks.log'),($messages|Out-String),$utf8)
if($code -ne 0){throw 'Temporal fixture execution failed'}
$values=@{}
foreach($line in $messages){if($line -match '^PASS (\d+) actual=([^ ]+) '){$values[[int]$Matches[1]]=[double]::Parse($Matches[2],[Globalization.CultureInfo]::InvariantCulture)}}
if($values.Count -ne 2048){throw 'Incomplete temporal readback'}
$profiles=@(foreach($p in 0..5){
    $fps=@(30,60,90,120,144,240)[$p]
    $firstFull=-1
    foreach($frame in 0..127){if($values[$p*128+$frame] -ge .99998){$firstFull=$frame;break}}
    if($firstFull -ne [Math]::Ceiling(.2*$fps)){throw 'Incorrect full-range fade duration'}
    @{fps=$fps;firstFullFrame=$firstFull;seconds=$firstFull/$fps}
})
foreach($source in $sources){if((Get-FileHash -LiteralPath (Join-Path $fork $source.path)).Hash -ne $source.sha256){throw 'Source changed during test'}}
$report=@{status='passed-temporal-limiter-math-only';numericChecks=2048;profiles=$profiles;sources=$sources;
    scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;binarySha256=(Get-FileHash -LiteralPath $binary).Hash;
    runnerSha256=$prior.runnerSha256;runtimeEligible=$false;gameModified=$false;
    limitations=@('Analytic history values in one dispatch, not real multi-frame resource ping-pong',
      'Native surface/light correspondence and edge-dependency persistence are not wired',
      'No game motion, performance, softness or full cutoff-fix claim')}
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),($report|ConvertTo-Json -Depth 7)+"`n",$utf8)
$report|Select-Object status,numericChecks,profiles|ConvertTo-Json -Depth 4
