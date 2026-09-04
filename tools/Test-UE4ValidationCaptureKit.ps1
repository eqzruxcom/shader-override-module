[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output = Join-Path $repoRoot 'artifacts\ue4-validation-capture-kit-test'
& (Join-Path $repoRoot 'tools\New-UE4ValidationCaptureKit.ps1') -OutputDirectory $output | Out-Null
$manifest = Get-Content -Raw -LiteralPath (Join-Path $output 'capture-kit-manifest.json') | ConvertFrom-Json

if ([bool]$manifest.containsReplacementShaders -or [bool]$manifest.containsGameShaderHashes) { throw 'Neutrality flags failed.' }
if (Test-Path -LiteralPath (Join-Path $output 'Mods')) { throw 'Neutral kit must not contain a Mods directory.' }
if (@(Get-ChildItem -LiteralPath $output -Recurse -File | Where-Object Extension -in @('.hlsl','.cso','.bin')).Count) { throw 'Neutral kit contains shader payloads.' }
$config = [IO.File]::ReadAllText((Join-Path $output 'd3dx.ini'))
foreach ($setting in @('hunting=2','analyse_frame = no_modifiers VK_F8','analyse_options = dump_rt jps mono desc','cache_shaders=1','export_shaders=1')) {
    if (-not $config.Contains($setting)) { throw "Capture setting missing: $setting" }
}
foreach ($hash in @('af6cd28a0108a18a','a77b589dce5822d6','ef7fe8d9c4e9ad15','b2bc6059f9a39c7f','e2aa1c8cb39e0a55')) {
    foreach ($file in Get-ChildItem -LiteralPath $output -File | Where-Object Extension -in @('.ini','.txt','.json')) {
        if ([IO.File]::ReadAllText($file.FullName) -match $hash) { throw "FF7 hash leaked into neutral kit: $hash" }
    }
}
foreach ($record in @($manifest.files)) {
    $file = Join-Path $output ([string]$record.relativePath)
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash -ne [string]$record.sha256) { throw "Payload hash mismatch: $file" }
}
Write-Output 'UE4 validation capture-kit neutrality test passed.'
