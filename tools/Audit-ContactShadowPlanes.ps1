[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if(-not $output.StartsWith((Join-Path $repo 'artifacts')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)) {throw 'Use a new workspace artifact directory.'}
$vsRoot=& 'C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe' -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$vc=Get-ChildItem -LiteralPath (Join-Path $vsRoot 'VC/Tools/MSVC') -Directory | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
$sdk='C:/Program Files (x86)/Windows Kits/10';$version='10.0.26100.0'
$compiler=Join-Path $vc 'bin/Hostx64/x64/cl.exe'
$null=New-Item -ItemType Directory -Path $output
$program=Join-Path $output 'Audit-ContactShadowPlanes.exe'
$utf8=[Text.UTF8Encoding]::new($false)
$arguments=@('/nologo','/EHsc','/std:c++17','/O2','/MD','/W4','/WX',('/I'+(Join-Path $vc 'include')))
foreach($inc in @('ucrt','shared','um','winrt')) {$arguments+=('/I'+(Join-Path $sdk "Include/$version/$inc"))}
$arguments+=@(('/Fo'+(Join-Path $output 'audit.obj')),('/Fe'+$program),(Join-Path $PSScriptRoot 'Audit-ContactShadowPlanes.cpp'),'/link',('/LIBPATH:'+(Join-Path $vc 'lib/x64')),('/LIBPATH:'+(Join-Path $sdk "Lib/$version/ucrt/x64")),('/LIBPATH:'+(Join-Path $sdk "Lib/$version/um/x64")),'d3d11.lib','d3dcompiler.lib')
$savedAuditPath=$env:PATH
try {
    $env:PATH=(Split-Path -Parent $compiler)+';'+$savedAuditPath
    $messages=& $compiler @arguments 2>&1;$code=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $output 'build.log'),($messages|Out-String),$utf8)
    if($code -ne 0) {throw 'Build failed; inspect build.log.'}
} finally {$env:PATH=$savedAuditPath}
$source=Join-Path $repo 'src/Tests/ContactShadowsPlaneAudit_cs.hlsl'
$messages=& $program $source (Join-Path $output 'results.csv') 2>&1;$code=$LASTEXITCODE
[IO.File]::WriteAllText((Join-Path $output 'audit.log'),($messages|Out-String),$utf8)
$messages | Write-Output
if($code -notin @(0,1)) {throw 'Audit execution failed.'}
$sources=@(foreach($path in @('src/Effects/Lighting/ContactShadowCommon.hlsl','src/Effects/Lighting/ContactShadows.hlsl','src/Tests/ContactShadowsPlaneAudit_cs.hlsl','tools/Audit-ContactShadowPlanes.cpp','tools/Audit-ContactShadowPlanes.ps1','tools/ContactShadowAdapterTests.h')) {@{path=$path;sha256=(Get-FileHash -LiteralPath (Join-Path $repo $path)).Hash}})
$manifest=@{createdAtUtc=[DateTime]::UtcNow.ToString('o');execution='completed-offline-WARP';regressionDetected=($code -eq 1);caseCount=20480;unobstructedCases=10240;boxOccluderCases=10240;orientations=8;subpixelPhases=4;sources=$sources;runnerSha256=(Get-FileHash -LiteralPath $program).Hash;liveGameChanged=$false;limitation='Analytic planes and boxes, not curved/normal-mapped character materials or temporal history'}
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),($manifest|ConvertTo-Json -Depth 6)+"`n",$utf8)
