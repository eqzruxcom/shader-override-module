[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateSet('Experimental','Rebirth')][string]$Implementation='Experimental',
    [string]$SdkRoot = 'C:\Program Files (x86)\Windows Kits\10',
    [string]$SdkVersion = '10.0.26100.0'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if (-not $output.StartsWith((Join-Path $repo 'artifacts') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Test output must be a child of workspace artifacts.' }
if (Test-Path -LiteralPath $output) { throw 'Test output exists; preserve earlier evidence.' }
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
$vsRoot = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $vsRoot) { throw 'C++ Build Tools were not found.' }
$vc = Get-ChildItem -LiteralPath (Join-Path $vsRoot 'VC\Tools\MSVC') -Directory |
    Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
$compiler = Join-Path $vc 'bin\Hostx64\x64\cl.exe'
$fxc = Join-Path $SdkRoot "bin\$SdkVersion\x64\fxc.exe"
foreach ($tool in @($compiler,$fxc)) { if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing compiler: $tool" } }
$null = New-Item -ItemType Directory -Path $output
$utf8 = [Text.UTF8Encoding]::new($false)
function Invoke-ContactTestTool([string]$Tool, [string[]]$Arguments, [string]$Log, [bool]$AllowRegression=$false) {
    $messages = & $Tool @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    [IO.File]::WriteAllText($Log, ($messages | Out-String), $utf8)
    if ($exitCode -ne 0 -and -not ($AllowRegression -and $exitCode -eq 1)) { throw "Test tool failed; see $Log" }
    return $messages
}
$smoke = Join-Path $repo 'src\Tests\ContactShadowsSmoke.hlsl'
$records = @(foreach ($samples in @(8,16,32)) {
    foreach ($stage in @('ps','cs')) {
        $base = "contact-$stage-$samples"
        $binary = Join-Path $output ($base + '.cso')
        $smokeArgs=@('/nologo','/Ges','/Gis','/WX','/O3','/D',"REDX11_CONTACT_SAMPLES=$samples",'/E',('main'+$stage.ToUpper()),'/T',($stage+'_5_0'),'/Fo',$binary,'/Fc',(Join-Path $output ($base+'.asm')))
        if($Implementation -eq 'Rebirth') {$smokeArgs+=@('/D','REDX11_CONTACT_USE_REBIRTH_SOURCE=1')}
        $smokeArgs+=$smoke
        $null = Invoke-ContactTestTool $fxc $smokeArgs (Join-Path $output ($base+'.log'))
        [ordered]@{stage=$stage;samples=$samples;sha256=(Get-FileHash -LiteralPath $binary).Hash}
    }
})
$program = Join-Path $output 'ContactShadowWarpTest.exe'
$argsForCompiler = @('/nologo','/EHsc','/std:c++17','/O2','/MD','/W4','/WX',
    ('/I'+(Join-Path $vc 'include')),('/I'+(Join-Path $SdkRoot "Include\$SdkVersion\ucrt")),
    ('/I'+(Join-Path $SdkRoot "Include\$SdkVersion\shared")),('/I'+(Join-Path $SdkRoot "Include\$SdkVersion\um")),
    ('/I'+(Join-Path $SdkRoot "Include\$SdkVersion\winrt")),
    ('/Fo'+(Join-Path $output 'ContactShadowWarpTest.obj')),('/Fe'+$program),
    (Join-Path $repo 'tools\ContactShadowWarpTest.cpp'),'/link',
    ('/LIBPATH:'+(Join-Path $vc 'lib\x64')),('/LIBPATH:'+(Join-Path $SdkRoot "Lib\$SdkVersion\ucrt\x64")),
    ('/LIBPATH:'+(Join-Path $SdkRoot "Lib\$SdkVersion\um\x64")), 'd3d11.lib','d3dcompiler.lib')
$savedContactPath = $env:PATH
try {
    $env:PATH = (Split-Path -Parent $compiler) + ';' + $savedContactPath
    $null = Invoke-ContactTestTool $compiler $argsForCompiler (Join-Path $output 'runner-build.log')
} finally { $env:PATH = $savedContactPath }
$caseSource = Join-Path $repo 'src\Tests\ContactShadowsCases_cs.hlsl'
$adapterSource=Join-Path $repo 'src\Tests\IntergradeContactAdapter_cs.hlsl'
if($Implementation -eq 'Rebirth') {
    $caseSource=Join-Path $repo 'src\Tests\RebirthContactCases_cs.hlsl'
    $adapterSource=Join-Path $repo 'src\Tests\RebirthContactAdapter_cs.hlsl'
}
$testResults = Invoke-ContactTestTool $program @($caseSource) (Join-Path $output 'warp-tests.log') ($Implementation -eq 'Rebirth')
$testResults | Write-Output
$adapterResults = Invoke-ContactTestTool $program @('--adapter',$adapterSource) (Join-Path $output 'adapter-tests.log') ($Implementation -eq 'Rebirth')
$adapterResults | Write-Output
$caseSummary=[regex]::Match(($testResults|Out-String),'WARP HLSL tests: (\d+)/34 passed')
$adapterSummary=[regex]::Match(($adapterResults|Out-String),'Adapter resource tests: (\d+)/56 passed')
if(-not $caseSummary.Success -or -not $adapterSummary.Success) {throw 'Incomplete test execution; regression mode does not excuse compile/execution errors.'}
$casesPassed=[int]$caseSummary.Groups[1].Value
$adaptersPassed=[int]$adapterSummary.Groups[1].Value
$suitePassed=$casesPassed -eq 34 -and $adaptersPassed -eq 56
$donorInputsPassed=0
$reconstructionPassed=0
$reconstructedAdaptersPassed=0
if($Implementation -eq 'Rebirth') {
    $inputResults=Invoke-ContactTestTool $program @('--donor-inputs',(Join-Path $repo 'src/Tests/RebirthContactInputs_cs.hlsl')) (Join-Path $output 'donor-input-tests.log') $true
    $inputResults | Write-Output
    $inputSummary=[regex]::Match(($inputResults|Out-String),'Donor input tests: (\d+)/34 passed')
    if(-not $inputSummary.Success) {throw 'Incomplete donor input test execution.'}
    $donorInputsPassed=[int]$inputSummary.Groups[1].Value
    $suitePassed=$suitePassed -and $donorInputsPassed -eq 34
    $reconstructionResults=Invoke-ContactTestTool $program @('--reconstruction',(Join-Path $repo 'src/Tests/RebirthContactReconstruction_cs.hlsl')) (Join-Path $output 'donor-reconstruction-tests.log') $true
    $reconstructionResults | Write-Output
    $reconstructionSummary=[regex]::Match(($reconstructionResults|Out-String),'Donor reconstruction tests: (\d+)/34 passed')
    if(-not $reconstructionSummary.Success) {throw 'Incomplete donor reconstruction tests.'}
    $reconstructionPassed=[int]$reconstructionSummary.Groups[1].Value
    $reconstructedResults=Invoke-ContactTestTool $program @('--adapter-reconstruction',(Join-Path $repo 'src/Tests/RebirthContactReconstructedAdapter_cs.hlsl')) (Join-Path $output 'reconstruction-adapter-tests.log') $true
    $reconstructedSummary=[regex]::Match(($reconstructedResults|Out-String),'Reconstruction adapter tests: (\d+)/448 passed')
    if(-not $reconstructedSummary.Success) {throw 'Incomplete reconstructed adapter execution.'}
    $reconstructedAdaptersPassed=[int]$reconstructedSummary.Groups[1].Value
    Write-Output $reconstructedSummary.Value
    $suitePassed=$suitePassed -and $reconstructionPassed -eq 34 -and $reconstructedAdaptersPassed -eq 448
}
$sourceRecords = @(foreach ($relative in @('src/Effects/Lighting/RebirthContactShadows.hlsl','src/ThirdParty/ShaderInjector/RebirthContactRay.hlsl','src/ThirdParty/ShaderInjector/RebirthContactNoise.hlsl','src/ThirdParty/ShaderInjector/provenance.json','src/Tests/RebirthContactCases_cs.hlsl','src/Tests/RebirthContactAdapter_cs.hlsl','tools/import_rebirth_contact_source.py','src\Effects\Lighting\ContactShadowCommon.hlsl','src\Effects\Lighting\ContactShadows.hlsl','src\Tests\ContactShadowsSmoke.hlsl','src\Tests\ContactShadowsCases_cs.hlsl','src\Tests\IntergradeContactAdapter_cs.hlsl','src\Adapters\FF7RemakeIntergrade\ContactShadowKernel_ps.hlsl','tools\ContactShadowWarpTest.cpp','tools\ContactShadowAdapterTests.h','tools\Test-ContactShadows.ps1')) {
    [ordered]@{path=$relative;sha256=(Get-FileHash -LiteralPath (Join-Path $repo $relative)).Hash}
})
$manifest = [ordered]@{
    schemaVersion=1;generatedAtUtc=[DateTime]::UtcNow.ToString('o')
    result=$(if($suitePassed){'passed'}else{'regressions-recorded'});implementation=$Implementation
    smokeCompiles=$records.Count;warpCases=34;warpCasesPassed=$casesPassed;adapterResourceCases=56;adapterResourceCasesPassed=$adaptersPassed
    donorInputCasesPassed=$donorInputsPassed;donorInputCases=$(if($Implementation -eq 'Rebirth'){34}else{0})
    reconstructionCasesPassed=$reconstructionPassed;reconstructionAdapterCasesPassed=$reconstructedAdaptersPassed
    assemblyFixtureInputRows=3;assemblyFixtureCases=37
    runtimeEligible=$false;liveGameTested=$false;performanceTested=$false
    execution='Headless D3D11 WARP: analytic ray fixtures plus real textures/buffers with synthetic adapter data'
    compiler=$fxc;compilerSha256=(Get-FileHash -LiteralPath $fxc).Hash
    runnerSha256=(Get-FileHash -LiteralPath $program).Hash
    sources=$sourceRecords;smokeShaders=$records
    limitations=@('No Remake bindings installed','Analytic depth fixtures do not verify game textures or sampler binding','No material coverage or live baseline comparison','SM5 standalone compile is not proof of assembled game-shader integration')
}
$manifest.sources+=@(foreach($path in @('src/Adapters/FF7RemakeIntergrade/RebirthContactInputMapping.hlsl','src/Tests/RebirthContactInputs_cs.hlsl','src/ThirdParty/ShaderInjector/RebirthContactReconstruction.hlsl','src/Adapters/FF7RemakeIntergrade/RebirthContactReconstructedKernel_ps.hlsl','src/Tests/RebirthContactReconstruction_cs.hlsl','src/Tests/RebirthContactReconstructedAdapter_cs.hlsl')) {
    @{path=$path;sha256=(Get-FileHash -LiteralPath (Join-Path $repo $path)).Hash}
})
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'), (($manifest | ConvertTo-Json -Depth 8)+"`n"), $utf8)
Write-Output "Contact-shadow tests completed: $($manifest.result). Offline artifacts: $output"
