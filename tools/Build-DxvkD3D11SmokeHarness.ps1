[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\dxvk-d3d11-smoke-harness')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $PSScriptRoot 'DxvkD3D11Smoke.cpp'
$fixtureRoot = Join-Path $root 'tests\fixtures\dxvk-d3d11-smoke'
$originalSource = Join-Path $fixtureRoot 'original-cs.hlsl'
$replacementSource = Join-Path $fixtureRoot 'replacement-cs.hlsl'
$checkerPath = Join-Path $root 'artifacts\dxbc-compatibility-tool\DxbcCompatibilityCheck.exe'
$checkerBuild = Join-Path $PSScriptRoot 'Build-DxbcCompatibilityChecker.ps1'
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $root 'artifacts'))
$resolvedOutput = [IO.Path]::GetFullPath($OutputRoot)

if (-not $resolvedOutput.StartsWith($artifactsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing output outside the workspace artifacts directory: $resolvedOutput"
}

function Find-Fxc {
    $command = Get-Command fxc.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }

    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $matches = @(Get-ChildItem -LiteralPath $kitsRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'x64\fxc.exe' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($matches.Count -eq 0) { throw 'Windows SDK fxc.exe was not found' }
    return $matches[0]
}

function Get-3DmigotoHash {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $modulus = [Numerics.BigInteger]::One -shl 64
    $value = [Numerics.BigInteger]::Zero
    $prime = [Numerics.BigInteger]::Parse('1099511628211')
    foreach ($byte in $Bytes) {
        $value = (($value * $prime) % $modulus) -bxor [Numerics.BigInteger]$byte
    }
    return ([UInt64]$value).ToString('x16')
}

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$FailureMessage
    )
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) { throw "$FailureMessage (exit code $LASTEXITCODE)" }
}

foreach ($path in @($sourcePath, $originalSource, $replacementSource, $checkerBuild)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required source is missing: $path" }
}

if (-not (Test-Path -LiteralPath $checkerPath -PathType Leaf)) {
    & $checkerBuild | Out-Null
}
if (-not (Test-Path -LiteralPath $checkerPath -PathType Leaf)) {
    throw "DXBC compatibility checker was not built: $checkerPath"
}

New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null
$replacementRoot = Join-Path $resolvedOutput 'replacements'
New-Item -ItemType Directory -Force -Path $replacementRoot | Out-Null

$fxc = Find-Fxc
$originalBin = Join-Path $resolvedOutput 'original-cs.bin'
$temporaryReplacement = Join-Path $resolvedOutput '_replacement-cs.bin'
Invoke-NativeChecked $fxc @('/nologo', '/T', 'cs_5_0', '/E', 'main', '/O3', '/Fo', $originalBin, $originalSource) 'Compiling original smoke shader failed'
Invoke-NativeChecked $fxc @('/nologo', '/T', 'cs_5_0', '/E', 'main', '/O3', '/Fo', $temporaryReplacement, $replacementSource) 'Compiling replacement smoke shader failed'

$identity = Get-3DmigotoHash ([IO.File]::ReadAllBytes($originalBin))
$replacementBin = Join-Path $replacementRoot ("$identity-cs_replace.bin")
Move-Item -LiteralPath $temporaryReplacement -Destination $replacementBin -Force
Invoke-NativeChecked $checkerPath @($originalBin, $replacementBin) 'Smoke replacement failed the DXBC compatibility gate'

$vsDevCmd = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat'
if (-not (Test-Path -LiteralPath $vsDevCmd -PathType Leaf)) { throw "Visual Studio developer command was not found: $vsDevCmd" }
$executable = Join-Path $resolvedOutput 'DxvkD3D11Smoke.exe'
$command = @(
    'call', ('"{0}"' -f $vsDevCmd), '-arch=x64', '-host_arch=x64', '-no_logo', '>', 'nul', '&&',
    'cl.exe', '/nologo', '/std:c++17', '/EHsc', '/W4', '/WX', '/DUNICODE', '/D_UNICODE',
    ('/Fe"{0}"' -f $executable), ('"{0}"' -f $sourcePath), 'd3d11.lib', 'dxgi.lib'
)
& $env:ComSpec /d /s /c ($command -join ' ')
if ($LASTEXITCODE -ne 0) { throw "Compiling D3D11 smoke executable failed (exit code $LASTEXITCODE)" }

$configPath = Join-Path $resolvedOutput 'dxvk-smoke.conf'
@(
    "d3d11.shaderOverridePath = $($replacementRoot.Replace('\', '/'))"
) | Set-Content -LiteralPath $configPath -Encoding ascii

$manifest = [ordered]@{
    Schema = 1
    Identity = "$identity-cs"
    OriginalBytecode = $originalBin
    OriginalSha256 = (Get-FileHash -LiteralPath $originalBin -Algorithm SHA256).Hash
    ReplacementBytecode = $replacementBin
    ReplacementSha256 = (Get-FileHash -LiteralPath $replacementBin -Algorithm SHA256).Hash
    CompatibilityVerified = $true
    NativeExpected = 7
    PatchedDxvkExpected = 42
    Executable = $executable
    DxvkConfig = $configPath
    Installed = $false
    RuntimeEligible = $false
}
$manifestPath = Join-Path $resolvedOutput 'manifest.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8

[pscustomobject]@{
    OutputRoot = $resolvedOutput
    Executable = $executable
    OriginalBytecode = $originalBin
    ReplacementBytecode = $replacementBin
    Identity = "$identity-cs"
    ManifestPath = $manifestPath
}
