[CmdletBinding()]
param(
    [switch]$SkipProxyBuild
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$forkRoot = Join-Path $repositoryRoot 'src\Backends\3DmigotoFork'
$proxyPath = Join-Path $forkRoot 'builds\x64\Release\d3d11.dll'
$compilerPath = Join-Path $forkRoot 'builds\x64\Release\d3dcompiler_47.dll'
$nvapiPath = Join-Path $forkRoot 'builds\x64\Release\nvapi64.dll'
$hostSource = Join-Path $PSScriptRoot 'ShaderFamilyHostDraw.cpp'
$vsDevCmd = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat'
$runRoot = Join-Path $repositoryRoot ('artifacts\shader-family-tests\' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
$hostPath = Join-Path $runRoot 'ShaderFamilyHost.exe'

foreach ($requiredPath in @($forkRoot, $hostSource, $vsDevCmd)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required path is missing: $requiredPath"
    }
}

New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

if (-not $SkipProxyBuild) {
    $buildLine = 'call "{0}" -arch=x64 -host_arch=x64 -winsdk=10.0.26100.0 >nul && msbuild "StereovisionHacks.sln" /m /t:DirectX11 /p:Configuration=Release /p:Platform=x64 /p:PostBuildEventUseInBuild=false /v:minimal' -f $vsDevCmd
    Push-Location $forkRoot
    try {
        & $env:ComSpec /d /s /c $buildLine
        if ($LASTEXITCODE -ne 0) {
            throw "3Dmigoto proxy build failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

foreach ($requiredPath in @($proxyPath, $compilerPath, $nvapiPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Built runtime file is missing: $requiredPath"
    }
}

$compileLine = 'call "{0}" -arch=x64 -host_arch=x64 -winsdk=10.0.26100.0 >nul && cl /nologo /EHsc /std:c++17 /O2 /FIcwchar "{1}" /Fe:"{2}" d3d11.lib d3dcompiler.lib' -f $vsDevCmd, $hostSource, $hostPath
& $env:ComSpec /d /s /c $compileLine
if ($LASTEXITCODE -ne 0) {
    throw "Shader-family host compile failed with exit code $LASTEXITCODE"
}

$baseConfiguration = @'
[Logging]
calls = 1
input = 0
debug = 0
unbuffered = 1
crash = 0

[System]
load_library_redirect = 0
check_foreground_window = 0
allow_check_interface = 1
allow_create_device = 1
allow_platform_update = 1

[Device]
upscaling = 0
full_screen = 0
force_stereo = 0

[Stereo]
automatic_mode = 0
create_profile = 0
force_no_nvapi = 1

[Rendering]
shader_hash = 3dmigoto
override_directory = ShaderFixes
cache_directory = ShaderCache
cache_shaders = 0
export_fixed = 0
export_shaders = 0
export_hlsl = 0

[Hunting]
hunting = 0

'@

$structuralPattern = @'
[ShaderRegexFamilyFixture.Pattern]
sample_indexable\(texture2d\)\(float,float,float,float\) (?P<sample>r\d+)\.xyzw, v\d+\.[xyzw]{4}, t0\.xyzw, s0\n
mul o0\.xyzw, (?P=sample)\.xyzw, cb0\[0\]\.xyzw\n

[ShaderRegexFamilyFixture.Pattern.Replace]
${0}
'@

$fixtureHash = '0fbe0ebb01471ee7'
$commonContract = @'
required_bindings = b0, t0, s0
forbidden_bindings = u0
min_instructions = 3
max_instructions = 3
'@

function Invoke-FamilyCase {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$MainSection,
        [Parameter(Mandatory)] [string[]]$Expected,
        [string[]]$Forbidden = @(),
        [switch]$OmitPattern
    )

    $caseRoot = Join-Path $runRoot $Name
    New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $caseRoot 'ShaderFixes') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $caseRoot 'ShaderCache') -Force | Out-Null
    Copy-Item -LiteralPath $hostPath -Destination $caseRoot
    Copy-Item -LiteralPath $proxyPath -Destination $caseRoot
    Copy-Item -LiteralPath $compilerPath -Destination $caseRoot
    Copy-Item -LiteralPath $nvapiPath -Destination $caseRoot

    $configuration = $baseConfiguration + $MainSection
    if (-not $OmitPattern) {
        $configuration += "`r`n" + $structuralPattern
    }
    [IO.File]::WriteAllText((Join-Path $caseRoot 'd3dx.ini'), $configuration, [Text.UTF8Encoding]::new($false))

    Push-Location $caseRoot
    try {
        $hostOutput = (& '.\ShaderFamilyHost.exe' 2>&1 | Out-String).Trim()
        $hostExit = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    $logPath = Join-Path $caseRoot 'd3d11_log.txt'
    $log = if (Test-Path -LiteralPath $logPath) {
        [IO.File]::ReadAllText($logPath)
    }
    else {
        ''
    }

    $failures = [Collections.Generic.List[string]]::new()
    if ($hostExit -ne 0) {
        $failures.Add("host exit code $hostExit")
    }
    if ($hostOutput -notlike '*PASS: fixture shader reached a draw*') {
        $failures.Add('host did not reach Draw')
    }
    if ($hostOutput -notlike ("*" + $caseRoot + '\d3d11.dll*')) {
        $failures.Add('host did not report the case-local proxy path')
    }
    if (-not $log) {
        $failures.Add('d3d11_log.txt was not created')
    }
    foreach ($needle in $Expected) {
        if (-not $log.Contains($needle)) {
            $failures.Add("missing log text: $needle")
        }
    }
    foreach ($needle in $Forbidden) {
        if ($log.Contains($needle)) {
            $failures.Add("forbidden log text present: $needle")
        }
    }

    [pscustomobject]@{
        Name = $Name
        Passed = $failures.Count -eq 0
        HostExit = $hostExit
        Failures = @($failures)
        Directory = $caseRoot
    }
}

$matchLine = "ShaderRegex: ps_5_0 $fixtureHash matches [ShaderRegexFamilyFixture]"
$noAssemblyErrors = @(
    '*** Assembling patched shader failed',
    '*** Creating replacement shader failed',
    'Error assembling ShaderRegex patched'
)

$results = @()

$results += Invoke-FamilyCase -Name 'legacy' -MainSection @"
[ShaderRegexFamilyFixture]
shader_model = ps_5_0
"@ -Expected @($matchLine) -Forbidden $noAssemblyErrors

$results += Invoke-FamilyCase -Name 'audit' -MainSection @"
[ShaderRegexFamilyFixture]
shader_model = ps_5_0
family_mode = audit
$commonContract
"@ -Expected @("ShaderFamily: candidate ps_5_0 $fixtureHash for [ShaderRegexFamilyFixture] (audit mode)", 'Patch did not apply') -Forbidden @($matchLine)

$results += Invoke-FamilyCase -Name 'approved-reject' -MainSection @"
[ShaderRegexFamilyFixture]
shader_model = ps_5_0
family_mode = approved
approved_hashes = deadbeefdeadbeef
$commonContract
"@ -Expected @("ShaderFamily: candidate ps_5_0 $fixtureHash for [ShaderRegexFamilyFixture] (hash is not approved)", 'Patch did not apply') -Forbidden @($matchLine)

$results += Invoke-FamilyCase -Name 'approved-accept' -MainSection @"
[ShaderRegexFamilyFixture]
shader_model = ps_5_0
family_mode = approved
approved_hashes = $fixtureHash
$commonContract
"@ -Expected @($matchLine) -Forbidden ($noAssemblyErrors + @('Patch did not apply'))

$results += Invoke-FamilyCase -Name 'automatic-accept' -MainSection @"
[ShaderRegexFamilyFixture]
shader_model = ps_5_0
family_mode = automatic
$commonContract
"@ -Expected @($matchLine) -Forbidden ($noAssemblyErrors + @('Patch did not apply'))

$results += Invoke-FamilyCase -Name 'required-binding-reject' -MainSection @'
[ShaderRegexFamilyFixture]
shader_model = ps_5_0
family_mode = automatic
required_bindings = b0, t0, s0, u0
min_instructions = 3
max_instructions = 3
'@ -Expected @("ShaderFamily: skipped ps_5_0 $fixtureHash for [ShaderRegexFamilyFixture]: missing required binding u0", 'Patch did not apply') -Forbidden @($matchLine)

$results += Invoke-FamilyCase -Name 'forbidden-binding-reject' -MainSection @'
[ShaderRegexFamilyFixture]
shader_model = ps_5_0
family_mode = automatic
required_bindings = b0, t0, s0
forbidden_bindings = t0
min_instructions = 3
max_instructions = 3
'@ -Expected @("ShaderFamily: skipped ps_5_0 $fixtureHash for [ShaderRegexFamilyFixture]: contains forbidden binding t0", 'Patch did not apply') -Forbidden @($matchLine)

$results += Invoke-FamilyCase -Name 'instruction-range-reject' -MainSection @'
[ShaderRegexFamilyFixture]
shader_model = ps_5_0
family_mode = automatic
required_bindings = b0, t0, s0
min_instructions = 4
max_instructions = 4
'@ -Expected @("ShaderFamily: skipped ps_5_0 $fixtureHash for [ShaderRegexFamilyFixture]: instruction count 3 outside 4..4", 'Patch did not apply') -Forbidden @($matchLine)

$results += Invoke-FamilyCase -Name 'incomplete-family-reject' -MainSection @'
[ShaderRegexFamilyFixture]
shader_model = ps_5_0
family_mode = automatic
min_instructions = 3
max_instructions = 3
'@ -Expected @('disabling incomplete shader family [ShaderRegexFamilyFixture]: family mode requires a structural Pattern') -Forbidden @($matchLine) -OmitPattern

$summaryPath = Join-Path $runRoot 'summary.json'
[IO.File]::WriteAllText(
    $summaryPath,
    ($results | ConvertTo-Json -Depth 5),
    [Text.UTF8Encoding]::new($false))

$results | Format-Table Name, Passed, HostExit -AutoSize
Write-Output "SUMMARY=$summaryPath"

$failed = @($results | Where-Object { -not $_.Passed })
if ($failed.Count) {
    foreach ($failure in $failed) {
        Write-Error ("{0}: {1}" -f $failure.Name, ($failure.Failures -join '; '))
    }
    throw "$($failed.Count) shader-family mode test(s) failed"
}

Write-Output "PASS: all $($results.Count) shader-family mode tests passed"


