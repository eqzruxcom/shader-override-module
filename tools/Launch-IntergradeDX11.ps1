[CmdletBinding()]
param(
    [string]$GameRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes',
    [string[]]$AdditionalArguments = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workingDirectory = Join-Path $GameRoot 'End\Binaries\Win64'
$exePath = Join-Path $workingDirectory 'ff7remake_.exe'
$proxyPath = Join-Path $workingDirectory 'd3d11.dll'

if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    throw "Intergrade executable not found: $exePath"
}

if (-not (Test-Path -LiteralPath $proxyPath -PathType Leaf)) {
    throw "3Dmigoto d3d11.dll is not installed: $proxyPath"
}

$arguments = @('-dx11') + $AdditionalArguments
$process = Start-Process -FilePath $exePath -ArgumentList $arguments -WorkingDirectory $workingDirectory -PassThru

Write-Output 'Started Intergrade in DX11 mode.'
Write-Output "PID: $($process.Id)"
Write-Output "Arguments: $($arguments -join ' ')"
