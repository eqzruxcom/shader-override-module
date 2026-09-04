[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory,[ValidateSet(16,32,64)][int]$Samples=16,[ValidateSet('Experimental','Rebirth')][string]$Implementation='Experimental',[ValidateSet('Fixed','Animated')][string]$NoiseMode='Animated',[ValidateSet('Raw','RawPixel','RecomputeQuad')][string]$Reconstruction='Raw')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($Implementation -ne 'Rebirth' -and $Reconstruction -ne 'Raw'){throw 'Donor reconstruction modes require Rebirth.'}
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if(-not $output.StartsWith((Join-Path $repo 'artifacts')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)) {throw 'Use a new workspace artifact directory.'}
$vsRoot=& 'C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe' -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$vc=Get-ChildItem -LiteralPath (Join-Path $vsRoot 'VC/Tools/MSVC') -Directory | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
$sdk='C:/Program Files (x86)/Windows Kits/10';$version='10.0.26100.0'
$compiler=Join-Path $vc 'bin/Hostx64/x64/cl.exe'
$null=New-Item -ItemType Directory -Path $output
$program=Join-Path $output 'Audit-ContactShadowMotion.exe';$utf8=[Text.UTF8Encoding]::new($false)
$arguments=@('/nologo','/EHsc','/std:c++17','/O2','/MD','/W4','/WX',('/I'+(Join-Path $vc 'include')))
foreach($inc in @('ucrt','shared','um','winrt')) {$arguments+=('/I'+(Join-Path $sdk "Include/$version/$inc"))}
$arguments+=@(('/Fo'+(Join-Path $output 'motion.obj')),('/Fe'+$program),(Join-Path $PSScriptRoot 'Audit-ContactShadowMotion.cpp'),'/link',('/LIBPATH:'+(Join-Path $vc 'lib/x64')),('/LIBPATH:'+(Join-Path $sdk "Lib/$version/ucrt/x64")),('/LIBPATH:'+(Join-Path $sdk "Lib/$version/um/x64")),'d3d11.lib','d3dcompiler.lib')
$savedMotionPath=$env:PATH
try {
    $env:PATH=(Split-Path -Parent $compiler)+';'+$savedMotionPath
    $messages=& $compiler @arguments 2>&1;$code=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $output 'build.log'),($messages|Out-String),$utf8)
    if($code -ne 0) {throw 'Build failed; inspect build.log.'}
} finally {$env:PATH=$savedMotionPath}
$source=Join-Path $repo 'src/Tests/ContactShadowsMotion_cs.hlsl'
if($Implementation -eq 'Rebirth') {$source=Join-Path $repo 'src/Tests/RebirthContactMotion_cs.hlsl'}
$nativeNoiseMode=if($Implementation -eq 'Rebirth' -and $NoiseMode -eq 'Animated'){'animated'}else{'fixed'}
$nativeReconstruction=switch($Reconstruction){'Raw'{'raw'} 'RawPixel'{'pixel'} 'RecomputeQuad'{'quad'}}
$messages=& $program $source $output $Samples $nativeNoiseMode $nativeReconstruction 2>&1;$code=$LASTEXITCODE
[IO.File]::WriteAllText((Join-Path $output 'audit.log'),($messages|Out-String),$utf8)
$messages | Write-Output
if($code -notin @(0,1)) {throw 'Motion audit execution failed.'}
$sources=@(foreach($path in @('src/Effects/Lighting/ContactShadowCommon.hlsl','src/Effects/Lighting/ContactShadows.hlsl','src/Tests/ContactShadowsMotion_cs.hlsl','tools/Audit-ContactShadowMotion.cpp','tools/Audit-ContactShadowMotion.ps1','tools/ContactShadowAdapterTests.h')) {@{path=$path;sha256=(Get-FileHash -LiteralPath (Join-Path $repo $path)).Hash}})
$manifest=@{createdAtUtc=[DateTime]::UtcNow.ToString('o');execution='completed-offline-WARP-synthetic-motion';regressionDetected=($code -eq 1);samples=$Samples;framesPerScene=96;scenes=4;receiversPerFrame=512;depthDimensions=@(1280,720);sources=$sources;runnerSha256=(Get-FileHash -LiteralPath $program).Hash;liveGameChanged=$false;limitation='Synthetic tracked surfaces and moving box, not FF7 animation, full lighting composition, or temporal history'}
$manifest.implementation=$Implementation
$manifest.reconstruction=$Reconstruction
$manifest.reconstructionLimit='Pixel/quad modes trace pixel-center depth and generated normals; tracked CPU truth can differ at silhouettes. Raw uses exact tracked receivers. No full native dispatch, raster-helper coverage or temporal AA.'
$manifest.noiseMode=$(if($Implementation -eq 'Rebirth'){'donor-'+$nativeNoiseMode+'-IGN'}else{'fixed-midpoint'})
$manifest.endpointRepeatsNoiseFrame=$true
if($Implementation -eq 'Rebirth') {
    $manifest.sources+=@(foreach($path in @('src/Effects/Lighting/RebirthContactShadows.hlsl','src/ThirdParty/ShaderInjector/RebirthContactRay.hlsl','src/ThirdParty/ShaderInjector/RebirthContactNoise.hlsl','src/ThirdParty/ShaderInjector/RebirthContactReconstruction.hlsl','src/ThirdParty/ShaderInjector/provenance.json','src/Tests/RebirthContactMotion_cs.hlsl')) {
        @{path=$path;sha256=(Get-FileHash -LiteralPath (Join-Path $repo $path)).Hash}
    })
}
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),($manifest|ConvertTo-Json -Depth 6)+"`n",$utf8)
