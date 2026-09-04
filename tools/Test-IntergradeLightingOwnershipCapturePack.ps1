[CmdletBinding()]
param(
    [string]$PackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\intergrade-lighting-ownership-capture-pack-20260904-v1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$manifestPath = Join-Path $PackRoot 'manifest.json'
$iniPath = Join-Path $PackRoot 'Mods\IntergradeLightingOwnershipCapture.ini'
foreach ($path in @($manifestPath, $iniPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required pack file is missing: $path" }
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$ini = [IO.File]::ReadAllText($iniPath)

if ($manifest.result -ne 'pass' -or $manifest.packId -ne 'ff7-remake-lighting-ownership-capture-v1') { throw 'Capture-pack identity changed.' }
if (@($manifest.targets).Count -ne 2) { throw 'Expected exactly two ownership targets.' }
if ((@($manifest.targets.hash | Sort-Object) -join ',') -ne 'aadc1c2374853914,adb544f9a11d6c7e') { throw 'Ownership target set changed.' }
if ([bool]$manifest.runtimeEligible -or [bool]$manifest.installed) { throw 'Offline capture pack was incorrectly promoted or marked installed.' }

foreach ($hash in @('aadc1c2374853914','adb544f9a11d6c7e')) {
    if ([regex]::Matches($ini, "(?im)^hash\s*=\s*$hash\s*$").Count -ne 1) { throw "Expected one override for $hash" }
}
if ([regex]::Matches($ini, '(?im)^analyse_options\s*=\s*dump_rt dump_tex dump_cb mono desc\s*$').Count -ne 2) {
    throw 'Each target must have the exact narrowed frame-analysis options.'
}
foreach ($forbidden in @(
    '(?im)^\s*key\s*=',
    '(?im)^\s*handling\s*=',
    '(?im)^\s*run\s*=',
    '(?im)^\s*(?:draw|dispatch)\s*=',
    '(?im)^\s*(?:ps|cs|vs|gs|hs|ds)-t\d+\s*=',
    '(?im)^\s*(?:o\d+|ps|cs|vs|gs|hs|ds)\s*='
)) {
    if ($ini -match $forbidden) { throw "Rendering mutation leaked into capture-only INI: $forbidden" }
}
$record = @($manifest.files | Where-Object path -eq 'Mods/IntergradeLightingOwnershipCapture.ini')
if ($record.Count -ne 1 -or $record[0].sha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $iniPath).Hash) {
    throw 'Capture INI checksum does not match its manifest.'
}

[pscustomobject]@{ Result='pass'; Targets=2; RenderingMutated=$false; KeyBindings=0; PackRoot=(Resolve-Path -LiteralPath $PackRoot).Path }

