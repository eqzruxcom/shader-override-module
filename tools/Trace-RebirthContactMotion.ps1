[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if(-not $output.StartsWith((Join-Path $repo 'artifacts')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Use a fresh workspace artifact directory.'}
$prior=Join-Path $repo 'artifacts/rebirth-contact-pixel-motion-20260831-v2'
$priorManifest=Get-Content (Join-Path $prior 'manifest.json') -Raw|ConvertFrom-Json
if($priorManifest.implementation -ne 'Rebirth' -or $priorManifest.reconstruction -ne 'RawPixel' -or $priorManifest.noiseMode -ne 'donor-animated-IGN'){throw 'Wrong prior motion configuration.'}
$sceneSource=@($priorManifest.sources|Where-Object path -eq 'tools/Audit-ContactShadowMotion.cpp')
if($sceneSource.Count -ne 1 -or (Get-FileHash (Join-Path $repo $sceneSource[0].path)).Hash -ne $sceneSource[0].sha256){throw 'Analytic scene changed.'}
$sourcePaths=@($priorManifest.sources.path)+@('tools/Trace-RebirthContactMotion.cpp','tools/Trace-RebirthContactMotion.ps1','src/Tests/RebirthContactTrace_cs.hlsl')
$sources=@(foreach($path in ($sourcePaths|Sort-Object -Unique)){@{path=$path;sha256=(Get-FileHash (Join-Path $repo $path)).Hash}})
$inputs=@(foreach($path in @('manifest.json','results.csv','visibility.f32')){@{path=(Join-Path $prior $path);sha256=(Get-FileHash (Join-Path $prior $path)).Hash}})
$vs=& 'C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe' -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$vc=Get-ChildItem (Join-Path $vs 'VC/Tools/MSVC') -Directory|Sort-Object Name -Descending|Select-Object -First 1 -ExpandProperty FullName
$sdk='C:/Program Files (x86)/Windows Kits/10';$version='10.0.26100.0'
$compiler=Join-Path $vc 'bin/Hostx64/x64/cl.exe'
$null=New-Item -ItemType Directory -Path $output
$program=Join-Path $output 'TraceContact.exe';$utf8=[Text.UTF8Encoding]::new($false)
$compileArgs=@('/nologo','/EHsc','/std:c++17','/O2','/MD','/W4','/WX',('/I'+(Join-Path $vc 'include')))
foreach($inc in @('ucrt','shared','um','winrt')){$compileArgs+=('/I'+(Join-Path $sdk "Include/$version/$inc"))}
$compileArgs+=@(('/Fo'+(Join-Path $output 'trace.obj')),('/Fe'+$program),(Join-Path $repo 'tools/Trace-RebirthContactMotion.cpp'),'/link',('/LIBPATH:'+(Join-Path $vc 'lib/x64')),('/LIBPATH:'+(Join-Path $sdk "Lib/$version/ucrt/x64")),('/LIBPATH:'+(Join-Path $sdk "Lib/$version/um/x64")),'d3d11.lib','d3dcompiler.lib')
$savedTracePath=$env:PATH
try {
    $env:PATH=(Split-Path -Parent $compiler)+';'+$savedTracePath
    $messages=& $compiler @compileArgs 2>&1;$code=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $output 'build.log'),($messages|Out-String),$utf8)
    if($code -ne 0){throw 'Trace build failed; inspect build.log.'}
} finally {$env:PATH=$savedTracePath}
$messages=& $program $repo $output (Join-Path $prior 'visibility.f32') 2>&1;$code=$LASTEXITCODE
[IO.File]::WriteAllText((Join-Path $output 'trace.log'),($messages|Out-String),$utf8)
$messages|Write-Output
if($code -ne 0){throw 'Trace execution failed.'}
if((Get-Item (Join-Path $output 'trace.f32')).Length -ne 96*512*54*16 -or (Get-Item (Join-Path $output 'visibility.f32')).Length -ne 96*512*4){throw 'Incomplete trace readback.'}
foreach($item in $sources){if((Get-FileHash (Join-Path $repo $item.path)).Hash -ne $item.sha256){throw 'Source changed during trace.'}}
foreach($item in $inputs){if((Get-FileHash $item.path).Hash -ne $item.sha256){throw 'Input changed during trace.'}}
$outputs=@(Get-ChildItem $output -File|Where-Object {$_.Extension -in @('.cso','.f32','.hlsl','.log')}|ForEach-Object {@{path=$_.Name;sha256=(Get-FileHash $_.FullName).Hash}})
$manifest=@{result='completed-observer-only';createdAtUtc=[DateTime]::UtcNow.ToString('o');sources=$sources;inputs=$inputs;outputs=$outputs;runnerSha256=(Get-FileHash $program).Hash;frames=96;receivers=512;float4RowsPerReceiver=54;scene='moving-box';referenceMatchesPriorBitExactly=$true;maximumInstrumentationTolerance=2e-6;runtimeEligible=$false;qualityGatePassed=$false;gameFilesModified=$false;limitations=@('Synthetic geometry, not FF7','Only raw pixel rays; reconstructed results require neighbor attribution','Observer call inserted into in-memory donor text; checked-in donor is unmodified','Instrumentation result must match reference; no deployment gate is relaxed')}
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),($manifest|ConvertTo-Json -Depth 7)+"`n",$utf8)
