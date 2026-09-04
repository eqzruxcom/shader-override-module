[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(-not $output.StartsWith((Join-Path $repo 'artifacts')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Use a fresh artifacts directory.'}
$vs=& 'C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe' -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$vc=Get-ChildItem -LiteralPath (Join-Path $vs 'VC/Tools/MSVC') -Directory|Sort-Object Name -Descending|Select-Object -First 1 -ExpandProperty FullName
$sdk='C:/Program Files (x86)/Windows Kits/10';$version='10.0.26100.0'
$cl=Join-Path $vc 'bin/Hostx64/x64/cl.exe';$fxc=Join-Path $sdk "bin/$version/x64/fxc.exe"
$null=New-Item -ItemType Directory -Path $output
$utf8=[Text.UTF8Encoding]::new($false)
function Run-CheckTool([string]$Tool,[string[]]$Arguments,[string]$Log) {
    $messages=& $Tool @Arguments 2>&1; $code=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $output $Log),($messages|Out-String),$utf8)
    if($code -ne 0){throw "Check failed: $Log"}
    return ,@($messages)
}
$program=Join-Path $output 'RunShaderFloatChecks.exe'
$compilerArgs=@('/nologo','/EHsc','/std:c++17','/O2','/MD','/W4','/WX',('/I'+(Join-Path $vc 'include')))
foreach($inc in @('ucrt','shared','um','winrt')){$compilerArgs+=('/I'+(Join-Path $sdk "Include/$version/$inc"))}
$compilerArgs+=@(('/Fo'+(Join-Path $output 'checks.obj')),('/Fe'+$program),(Join-Path $repo 'tools/RunShaderFloatChecks.cpp'),'/link',('/LIBPATH:'+(Join-Path $vc 'lib/x64')),('/LIBPATH:'+(Join-Path $sdk "Lib/$version/ucrt/x64")),('/LIBPATH:'+(Join-Path $sdk "Lib/$version/um/x64")),'d3d11.lib','d3dcompiler.lib')
$savedCheckPath=$env:PATH
try { $env:PATH=(Split-Path -Parent $cl)+';'+$savedCheckPath; $null=Run-CheckTool $cl $compilerArgs 'build.log' }
finally { $env:PATH=$savedCheckPath }
$binary=Join-Path $output 'viewport-cases.cso'
$null=Run-CheckTool $fxc @('/nologo','/Ges','/Gis','/WX','/O3','/T','cs_5_0','/E','main','/Fo',$binary,(Join-Path $repo 'src/Tests/ContactViewportClipCases_cs.hlsl')) 'compile.log'
$messages=Run-CheckTool $program @($binary,'64') 'checks.log'
$messages|Select-Object -Last 1|Write-Output
$sources=@(foreach($path in @('src/Effects/Lighting/ContactViewportClip.hlsl','src/Tests/ContactViewportClipCases_cs.hlsl','tools/RunShaderFloatChecks.cpp','tools/Test-ContactViewportClip.ps1')){@{path=$path;sha256=(Get-FileHash -LiteralPath (Join-Path $repo $path)).Hash}})
$manifest=@{status='passed-math-only';cases=64;sources=$sources;binarySha256=(Get-FileHash -LiteralPath $binary).Hash;runnerSha256=(Get-FileHash -LiteralPath $program).Hash;gameModified=$false;liveCauseConfirmed=$false;limitations=@('Analytic clip intervals, not engine frames','No recovered offscreen geometry','Not a visual or performance gate')}
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),($manifest|ConvertTo-Json -Depth 6)+"`n",$utf8)
