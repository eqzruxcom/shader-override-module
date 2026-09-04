[CmdletBinding()]
param([Parameter(Mandatory)][string] $BuildDirectory)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$testRoot = Join-Path $artifactsRoot ('fallout-new-vegas-component-validation-test-' + [Guid]::NewGuid().ToString('N'))
$assertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5ComponentBuild.ps1'
$buildPath = Join-Path $PSScriptRoot 'Build-FalloutNewVegasDlss5Components.ps1'

try {
    $validated = & $assertPath -BuildDirectory $BuildDirectory
    if (-not $validated.Valid -or -not $validated.ByteIdentical -or $validated.OutputCount -ne 4) { throw 'Positive deterministic component artifact did not return the expected state.' }
    Copy-Item -LiteralPath $validated.BuildRoot -Destination $testRoot -Recurse

    $addon = Join-Path $testRoot 'bin\x86\dlss5-feed.addon32'
    $bytes = [IO.File]::ReadAllBytes($addon)
    $bytes[0x100] = $bytes[0x100] -bxor 1
    [IO.File]::WriteAllBytes($addon, $bytes)
    $rejected = $false
    try { $null = & $assertPath -BuildDirectory $testRoot } catch { $rejected = $_.Exception.Message -match 'hash mismatch' }
    if (-not $rejected) { throw 'Component validator accepted a tampered source-built add-on.' }

    $builderText = [IO.File]::ReadAllText($buildPath)
    foreach ($forbidden in @('Invoke-WebRequest', 'Start-BitsTransfer', 'HKCU:', 'HKLM:', 'git clone https:')) {
        if ($builderText.Contains($forbidden)) { throw "Component builder unexpectedly performs network or registry work: $forbidden" }
    }

    Write-Host 'PASS: deterministic component build receipt is hash-closed and rejects binary tampering.'
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
