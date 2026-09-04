[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\dxbc-compatibility-tool'),
    [string]$SourcePath = (Join-Path $PSScriptRoot 'DxbcCompatibilityCheck.cpp')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$vsDevCmd = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat'
if (-not (Test-Path -LiteralPath $vsDevCmd -PathType Leaf)) { throw "Missing Visual Studio Build Tools: $vsDevCmd" }
$source = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($output) | Out-Null
$executable = Join-Path $output 'DxbcCompatibilityCheck.exe'
$object = Join-Path $output 'DxbcCompatibilityCheck.obj'
$command = @(
    'call', ('"{0}"' -f $vsDevCmd), '-arch=amd64', '-host_arch=amd64', '>', 'nul', '&&',
    'cl.exe', '/nologo', '/std:c++17', '/EHsc', '/W4', '/WX', '/O2',
    ('/Fo:"{0}"' -f $object), ('/Fe:"{0}"' -f $executable), ('"{0}"' -f $source),
    'd3dcompiler.lib', 'dxguid.lib'
) -join ' '
$messages = & $env:ComSpec /d /s /c $command 2>&1
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    $messages | Write-Host
    throw "DXBC compatibility checker build failed (exit code $exitCode)"
}
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'Build produced no DXBC compatibility checker.' }

[pscustomobject]@{
    Executable = $executable
    Sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $executable).Hash
    Installed = $false
}
