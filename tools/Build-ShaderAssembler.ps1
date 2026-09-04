[CmdletBinding()]
param(
    [string]$SdkRoot = 'C:\Program Files (x86)\Windows Kits\10',
    [string]$SdkVersion = '10.0.26100.0'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$source = Join-Path $repo 'reference\3Dmigoto'
$build = Join-Path $repo 'artifacts\shader-assembler-build'
$props = Join-Path $PSScriptRoot 'ShaderAssembler.Build.props'
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
$msbuild = @(& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find 'MSBuild\**\Bin\MSBuild.exe')
if ($LASTEXITCODE -ne 0 -or $msbuild.Count -ne 1) { throw 'A unique installed C++ MSBuild toolchain is required.' }
foreach ($relative in @("Include\$SdkVersion\ucrt\math.h", "Include\$SdkVersion\shared\sdkddkver.h", "Include\$SdkVersion\um\Windows.h", "Lib\$SdkVersion\um\x64\d3dcompiler.lib", "Lib\$SdkVersion\ucrt\x64\libucrt.lib", "bin\$SdkVersion\x64\rc.exe")) {
    if (-not (Test-Path -LiteralPath (Join-Path $SdkRoot $relative) -PathType Leaf)) { throw "SDK file is missing: $relative" }
}
[IO.Directory]::CreateDirectory($build) | Out-Null
$savedBuildPath = $env:PATH
try {
    $env:PATH = (Join-Path $SdkRoot "bin\$SdkVersion\x64") + ';' + $savedBuildPath
    & $msbuild[0] (Join-Path $source 'HLSLDecompiler\cmd_Decompiler\cmd_Decompiler.vcxproj') /nologo /m:2 /v:minimal /p:Configuration=Release /p:Platform=x64 "/p:WindowsTargetPlatformVersion=$SdkVersion" "/p:WindowsSdkDir=$SdkRoot\" "/p:UniversalCRTSdkDir=$SdkRoot\" /p:WindowsSDKInstalled=true /p:WindowsSDK_Desktop_Support=true "/p:SolutionDir=$source\" "/p:ForceImportBeforeCppTargets=$props" /p:PostBuildEventUseInBuild=false ("/flp:logfile=$build\build.log;verbosity=normal")
    if ($LASTEXITCODE -ne 0) { throw "Assembler build failed; see $build\build.log" }
} finally { $env:PATH = $savedBuildPath }
$binary = Join-Path $build 'bin\cmd_Decompiler.exe'
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { throw 'Build produced no assembler.' }
[pscustomobject]@{ Assembler=$binary; Sha256=(Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash }
