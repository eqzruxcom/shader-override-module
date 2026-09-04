[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateSet('Experimental','Rebirth')][string]$Implementation='Experimental',
    [ValidateSet('Raw','RecomputeQuad','SharedQuad')][string]$Reconstruction='Raw'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($Implementation -ne 'Rebirth' -and $Reconstruction -ne 'Raw') {throw 'Quad reconstruction requires the Rebirth donor.'}
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if(-not $output.StartsWith((Join-Path $repo 'artifacts')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)) {throw 'Use a new output under workspace artifacts.'}
$analysisPath=Join-Path $repo 'artifacts/contact-capture-analysis-20260830-v2/analysis.json'
$analysis=Get-Content -LiteralPath $analysisPath -Raw | ConvertFrom-Json
$variant=$analysis.variants[0]
$boundKeys=@('cb0','cb1','cb4','normal','depth')
$materialPath=$null
if($Implementation -eq 'Rebirth') {
    $boundKeys+='material'
    $materialPath=Join-Path $analysis.captureDirectory $variant.files.material
    if((Get-FileHash -LiteralPath $materialPath).Hash -ne $variant.sha256.material) {throw 'Captured material changed.'}
}
$inputs=@(foreach($key in @('cb0','cb1','cb4','normal','depth')) {
    $path=Join-Path $analysis.captureDirectory $variant.files.$key
    if((Get-FileHash -LiteralPath $path).Hash -ne $variant.sha256.$key) {throw 'Captured input changed.'}
    $path
})
$vswhere='C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe'
$vs=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if($LASTEXITCODE -ne 0 -or -not $vs) {throw 'No compiler.'}
$vc=Get-ChildItem -LiteralPath (Join-Path $vs 'VC/Tools/MSVC') -Directory | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
$cl=Join-Path $vc 'bin/Hostx64/x64/cl.exe'
$sdk='C:/Program Files (x86)/Windows Kits/10';$version='10.0.26100.0'
$null=New-Item -ItemType Directory -Path $output
$program=Join-Path $output 'ReplayContact.exe';$source=Join-Path $repo 'tools/Replay-IntergradeContactCapture.cpp'
$wrapper=Join-Path $repo 'src/Tests/IntergradeContactCapture_cs.hlsl'
if($Implementation -eq 'Rebirth') {
    $wrapper=Join-Path $repo 'src/Tests/RebirthContactCapture_cs.hlsl'
    if($Reconstruction -eq 'RecomputeQuad') {$wrapper=Join-Path $repo 'src/Tests/RebirthContactReconstructedCapture_cs.hlsl'}
    if($Reconstruction -eq 'SharedQuad') {$wrapper=Join-Path $repo 'src/Tests/RebirthContactSharedCapture_cs.hlsl'}
}
$sourcePaths=@('src/Effects/Lighting/ContactShadowCommon.hlsl','tools/Replay-IntergradeContactCapture.cpp','tools/Replay-IntergradeContactCapture.ps1','tools/ContactShadowAdapterTests.h','src/Tests/IntergradeContactCapture_cs.hlsl','src/Adapters/FF7RemakeIntergrade/ContactShadowKernel_ps.hlsl','src/Effects/Lighting/ContactShadows.hlsl')
if($Implementation -eq 'Rebirth') {
    $sourcePaths+=@('src/Tests/RebirthContactCapture_cs.hlsl','src/Tests/RebirthContactReconstructedCapture_cs.hlsl',
        'src/Tests/RebirthContactSharedCapture_cs.hlsl','src/Adapters/FF7RemakeIntergrade/RebirthContactShared.hlsl',
        'src/Adapters/FF7RemakeIntergrade/RebirthContactShadowKernel_ps.hlsl','src/Adapters/FF7RemakeIntergrade/RebirthContactReconstructedKernel_ps.hlsl',
        'src/Adapters/FF7RemakeIntergrade/RebirthContactInputMapping.hlsl','src/Effects/Lighting/RebirthContactShadows.hlsl',
        'src/ThirdParty/ShaderInjector/RebirthContactRay.hlsl','src/ThirdParty/ShaderInjector/RebirthContactNoise.hlsl',
        'src/ThirdParty/ShaderInjector/RebirthContactReconstruction.hlsl','src/ThirdParty/ShaderInjector/provenance.json')
}
$sources=@(foreach($relative in $sourcePaths) {@{path=$relative;sha256=(Get-FileHash -LiteralPath (Join-Path $repo $relative)).Hash}})
$compileArgs=@('/nologo','/EHsc','/std:c++17','/O2','/MD','/W4',
    ('/I'+(Join-Path $vc 'include')),('/I'+(Join-Path $sdk "Include/$version/ucrt")),('/I'+(Join-Path $sdk "Include/$version/shared")),('/I'+(Join-Path $sdk "Include/$version/um")),
    ('/I'+(Join-Path $sdk "Include/$version/winrt")),
    ('/Fo'+(Join-Path $output 'ReplayContact.obj')),('/Fe'+$program),$source,'/link',
    ('/LIBPATH:'+(Join-Path $vc 'lib/x64')),('/LIBPATH:'+(Join-Path $sdk "Lib/$version/ucrt/x64")),('/LIBPATH:'+(Join-Path $sdk "Lib/$version/um/x64")),'d3d11.lib','d3dcompiler.lib')
$utf8=[Text.UTF8Encoding]::new($false)
$savedReplayPath=$env:PATH
try {
    $env:PATH=(Split-Path -Parent $cl)+';'+$savedReplayPath
    $messages=& $cl @compileArgs 2>&1;$exitCode=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $output 'build.log'),($messages|Out-String),$utf8)
    if($exitCode -ne 0) {throw "Replay build failed: $output/build.log"}
} finally {$env:PATH=$savedReplayPath}
$replayArgs=@($wrapper)+$inputs+@($output)
if($Implementation -eq 'Rebirth') {$replayArgs+=@($materialPath,$(if($Reconstruction -eq 'SharedQuad'){'shared-quads'}else{'quads'}))}
$messages=& $program @replayArgs 2>&1;$exitCode=$LASTEXITCODE
[IO.File]::WriteAllText((Join-Path $output 'replay.log'),($messages|Out-String),$utf8)
$messages | Write-Output
if($exitCode -ne 0) {throw 'Capture replay failed.'}
$results=@(Import-Csv -LiteralPath (Join-Path $output 'results.csv'))
if($results.Count -ne 10) {throw 'Incomplete replay.'}
foreach($item in $sources) {if((Get-FileHash -LiteralPath (Join-Path $repo $item.path)).Hash -ne $item.sha256) {throw 'Replay source changed during execution.'}}
foreach($key in $boundKeys) {if((Get-FileHash -LiteralPath (Join-Path $analysis.captureDirectory $variant.files.$key)).Hash -ne $variant.sha256.$key) {throw 'Replay input changed during execution.'}}
$outputs=@(Get-ChildItem -LiteralPath $output -File | Where-Object {$_.Name -match '(^light-.*\.(f32|u8)$|^capture-kernel\.cso$|^results\.csv$)'} | ForEach-Object {@{path=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
$grid=@(480,270);$layout='RegularStride';$execution='D3D11 WARP production-kernel replay of captured resources'
if($Implementation -eq 'Rebirth') {$grid=@(960,540);$layout='SparseCompleteQuads';$execution='D3D11 WARP donor prototype replay of captured resources'}
$report=[ordered]@{
    schemaVersion=2;createdAtUtc=[DateTime]::UtcNow.ToString('o');execution=$execution
    runnerSha256=(Get-FileHash -LiteralPath $program).Hash;analysisSha256=(Get-FileHash -LiteralPath $analysisPath).Hash
    captureDirectory=$analysis.captureDirectory;inputFiles=$variant.files;inputHashes=$variant.sha256;boundInputKeys=$boundKeys;sources=$sources;results=$results;outputs=$outputs
    implementation=$Implementation;reconstruction=$Reconstruction;sampleLayout=$layout;sampleStride=8;grid=$grid;selectedLight=50;gameFilesModified=$false
    dispatchGroupWidth=$(if($Reconstruction -eq 'SharedQuad'){16}else{8})
    runtimeEligible=$false;qualityGatePassed=$false
    limitations=@('No native tile-membership or BRDF/shadow-map application in this wrapper','Shared sparse quads preserve neighbor mapping but do not reproduce native contiguous 16x16 tile layout','Software execution is not live hardware performance','No visual improvement inferred from hits','Current game frame may differ from saved capture','Single saved frame; no engine animation, temporal history or phase progression','Validity flags describe receiver preflight, not ray hits or native light contribution')
}
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),($report|ConvertTo-Json -Depth 8)+"`n",$utf8)
