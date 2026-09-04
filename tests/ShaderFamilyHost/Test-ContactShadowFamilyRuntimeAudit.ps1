[CmdletBinding()]
param(
    [switch]$SkipProxyBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$forkRoot = Join-Path $repositoryRoot 'src\Backends\3DmigotoFork'
$proxyPath = Join-Path $forkRoot 'builds\x64\Release\d3d11.dll'
$compilerPath = Join-Path $forkRoot 'builds\x64\Release\d3dcompiler_47.dll'
$nvapiPath = Join-Path $forkRoot 'builds\x64\Release\nvapi64.dll'
$hostSource = Join-Path $PSScriptRoot 'ShaderFamilyComputeHost.cpp'
$auditIni = Join-Path $repositoryRoot 'src\Adapters\FF7RemakeIntergrade\ContactShadowFamilyAudit.ini'
$positiveRoot = Join-Path $repositoryRoot 'artifacts\contact-header-generator-verification-20260831-v1\validation'
$negativeRoot = Join-Path $repositoryRoot 'artifacts\contact-edge-fade-development-20260831-v1\artifacts\surface-lighting-study-20260830-v3'
$vsDevCmd = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat'
$runRoot = Join-Path $repositoryRoot ('artifacts\shader-family-tests\contact-runtime-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
$hostPath = Join-Path $runRoot 'ShaderFamilyComputeHost.exe'

$positiveHashes = @(
    '08bb8764f1840179',
    '0e97888f9a8767da',
    '5a9fbefe0ab6f815',
    '62b33a2d1e505241',
    'c30cdc8365df9840'
)
$negativeHashes = @(
    'b9e2305a994308f2',
    'c814bac1ac75b35e',
    'f97a821dddaa328a'
)

$positivePaths = @($positiveHashes | ForEach-Object {
    Join-Path $positiveRoot ($_ + '-original.bin')
})
$negativePaths = @($negativeHashes | ForEach-Object {
    Join-Path $negativeRoot ($_ + '-cs.bin')
})

foreach ($requiredPath in @($forkRoot, $hostSource, $auditIni, $vsDevCmd) +
        $positivePaths + $negativePaths) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf) -and
        -not (Test-Path -LiteralPath $requiredPath -PathType Container)) {
        throw "Required path is missing: $requiredPath"
    }
}

[IO.Directory]::CreateDirectory($runRoot) | Out-Null

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
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Built runtime file is missing: $requiredPath"
    }
}

$compileLine = 'call "{0}" -arch=x64 -host_arch=x64 -winsdk=10.0.26100.0 >nul && cl /nologo /EHsc /std:c++17 /O2 /FIcwchar "{1}" /Fe:"{2}" d3d11.lib' -f $vsDevCmd, $hostSource, $hostPath
& $env:ComSpec /d /s /c $compileLine
if ($LASTEXITCODE -ne 0) {
    throw "Compute-family host compile failed with exit code $LASTEXITCODE"
}

foreach ($runtimePath in @($proxyPath, $compilerPath, $nvapiPath)) {
    Copy-Item -LiteralPath $runtimePath -Destination $runRoot
}

$shaderRoot = Join-Path $runRoot 'Shaders'
[IO.Directory]::CreateDirectory($shaderRoot) | Out-Null
$caseShaders = [Collections.Generic.List[string]]::new()
foreach ($shaderPath in $positivePaths + $negativePaths) {
    $destination = Join-Path $shaderRoot (Split-Path -Leaf $shaderPath)
    Copy-Item -LiteralPath $shaderPath -Destination $destination
    $caseShaders.Add($destination)
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

$configuration = $baseConfiguration + [Environment]::NewLine +
    [IO.File]::ReadAllText($auditIni)
[IO.File]::WriteAllText(
    (Join-Path $runRoot 'd3dx.ini'),
    $configuration,
    [Text.UTF8Encoding]::new($false))

Push-Location $runRoot
try {
    $hostOutput = (& '.\ShaderFamilyComputeHost.exe' @($caseShaders) 2>&1 | Out-String).Trim()
    $hostExit = $LASTEXITCODE
}
finally {
    Pop-Location
}

$logPath = Join-Path $runRoot 'd3d11_log.txt'
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
if ($hostOutput -notlike '*PASS: 8 compute shaders created*') {
    $failures.Add('host did not create all eight compute shaders')
}
if ($hostOutput -notlike ('*' + $runRoot + '\d3d11.dll*')) {
    $failures.Add('host did not report the case-local proxy path')
}
if (-not $log) {
    $failures.Add('d3d11_log.txt was not created')
}

$familyName = '[ShaderRegexUE4FXRemakeTiledSurfaceLightContactAudit]'
foreach ($hash in $positiveHashes) {
    $expected = "ShaderFamily: candidate cs_5_0 $hash for $familyName (audit mode)"
    if (-not $log.Contains($expected)) {
        $failures.Add("missing positive audit candidate: $hash")
    }
}
foreach ($hash in $negativeHashes) {
    $unexpected = "ShaderFamily: candidate cs_5_0 $hash for $familyName"
    if ($log.Contains($unexpected)) {
        $failures.Add("unrelated compute shader became an audit candidate: $hash")
    }
}

$report = [ordered]@{
    schemaVersion = 1
    kind = 'remake-contact-family-runtime-audit'
    mode = 'case-local-3dmigoto-audit'
    runtime = $proxyPath
    runtimeSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $proxyPath).Hash
    auditIni = $auditIni
    auditIniSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $auditIni).Hash
    positives = $positiveHashes
    negatives = $negativeHashes
    hostExit = $hostExit
    passed = $failures.Count -eq 0
    failures = @($failures)
    runDirectory = $runRoot
}
$summaryPath = Join-Path $runRoot 'summary.json'
[IO.File]::WriteAllText(
    $summaryPath,
    ($report | ConvertTo-Json -Depth 6) + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))

Write-Host $hostOutput
Write-Host "SUMMARY=$summaryPath"
if ($failures.Count) {
    throw "Contact family runtime audit failed: $($failures -join '; ')"
}

Write-Host 'PASS: the case-local 3Dmigoto runtime audited all five contact-family shaders and rejected three unrelated compute shaders.'
