[CmdletBinding()]
param([Parameter(Mandatory)][string]$RefinementDirectory,[Parameter(Mandatory)][string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$fork=(Resolve-Path -LiteralPath $RefinementDirectory).Path
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(-not $output.StartsWith((Join-Path $repo 'artifacts')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Use a fresh artifacts child'}
$sources=@(foreach($path in @((Join-Path $fork 'src/Effects/Lighting/ContactEdgeTemporal.hlsl'),(Join-Path $fork 'src/Tests/ContactEdgeTemporalHistory_cs.hlsl'),(Join-Path $repo 'tools/RunContactEdgeTemporalHistory.cpp'),$PSCommandPath)){@{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash}})
$vs=& 'C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe' -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$vc=Get-ChildItem (Join-Path $vs 'VC/Tools/MSVC') -Directory|Sort-Object Name -Descending|Select-Object -First 1 -ExpandProperty FullName
$sdk='C:/Program Files (x86)/Windows Kits/10';$version='10.0.26100.0'
$compiler=Join-Path $vc 'bin/Hostx64/x64/cl.exe'
$null=New-Item -ItemType Directory -Path $output
$utf8=[Text.UTF8Encoding]::new($false)
$program=Join-Path $output 'TemporalHistory.exe'
$compileArgs=@('/nologo','/EHsc','/std:c++17','/O2','/MD','/W4','/WX',('/I'+(Join-Path $vc 'include')))
foreach($inc in @('ucrt','shared','um','winrt')){$compileArgs+=('/I'+(Join-Path $sdk "Include/$version/$inc"))}
$compileArgs+=@(('/Fo'+(Join-Path $output 'history.obj')),('/Fe'+$program),(Join-Path $repo 'tools/RunContactEdgeTemporalHistory.cpp'),'/link',('/LIBPATH:'+(Join-Path $vc 'lib/x64')),('/LIBPATH:'+(Join-Path $sdk "Lib/$version/ucrt/x64")),('/LIBPATH:'+(Join-Path $sdk "Lib/$version/um/x64")),'d3d11.lib','d3dcompiler.lib')
$savedCompilerPath=$env:PATH
try{
    $env:PATH=(Split-Path -Parent $compiler)+';'+$savedCompilerPath
    $messages=& $compiler @compileArgs 2>&1;$code=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $output 'build.log'),($messages|Out-String),$utf8)
    if($code -ne 0){throw 'History runner build failed'}
}finally{$env:PATH=$savedCompilerPath}
$binary=Join-Path $output 'history.cso'
$fxc=Join-Path $sdk "bin/$version/x64/fxc.exe"
$messages=& $fxc /nologo /Ges /Gis /WX /O3 /T cs_5_0 /E main /Fo $binary (Join-Path $fork 'src/Tests/ContactEdgeTemporalHistory_cs.hlsl') 2>&1;$code=$LASTEXITCODE
[IO.File]::WriteAllText((Join-Path $output 'compile.log'),($messages|Out-String),$utf8)
if($code -ne 0){throw 'History shader compile failed'}
$messages=& $program $binary 2>&1;$code=$LASTEXITCODE
[IO.File]::WriteAllText((Join-Path $output 'checks.log'),($messages|Out-String),$utf8)
$messages|Write-Output
if($code -ne 0){throw 'History test failed'}
$summary=@($messages|Where-Object {$_ -match '^PASS history checks='})
if($summary.Count -ne 1){throw 'Missing history coverage summary'}
foreach($source in $sources){if((Get-FileHash -LiteralPath $source.path).Hash -ne $source.sha256){throw 'Source changed during test'}}
$report=@{status='passed-synthetic-history-ping-pong';summary=$summary[0];sources=$sources;binarySha256=(Get-FileHash -LiteralPath $binary).Hash;runnerSha256=(Get-FileHash -LiteralPath $program).Hash;runtimeEligible=$false;gameModified=$false;limitations=@('Synthetic receiver/light keys and correspondence, not native engine bindings','No native per-light history allocation, reprojection or velocity integration','No game motion, softness or hardware-performance pass')}
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),($report|ConvertTo-Json -Depth 6)+"`n",$utf8)
