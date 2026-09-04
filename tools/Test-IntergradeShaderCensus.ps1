[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$source = Join-Path $root 'artifacts\shader-census\intergrade-live-census-v1\d3dx.ini.prepared.source'
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Census test fixture is missing: $source" }
$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$testRoot = Join-Path $root "artifacts\shader-census-tests\$stamp"
$game = Join-Path $testRoot 'game'
$backups = Join-Path $testRoot 'backups'
$receipt = Join-Path $testRoot 'enable-receipt.json'
[IO.Directory]::CreateDirectory($game) | Out-Null
Copy-Item -LiteralPath $source -Destination (Join-Path $game 'd3dx.ini')
$before = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $game 'd3dx.ini')).Hash

$guarded = $false
try {
    & (Join-Path $PSScriptRoot 'Enable-IntergradeShaderCensus.ps1') -GameDirectory $game -BackupRoot $backups -ProcessName 'pwsh' -ReceiptPath $receipt -Confirm:$false | Out-Null
} catch {
    if ($_.Exception.Message -like '*is running*') { $guarded = $true } else { throw }
}
if (-not $guarded) { throw 'Running-process guard did not refuse the census transition.' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $game 'd3dx.ini')).Hash -ne $before) {
    throw 'Running-process guard changed the fixture INI.'
}

$enabled = & (Join-Path $PSScriptRoot 'Enable-IntergradeShaderCensus.ps1') -GameDirectory $game -BackupRoot $backups -ProcessName '__codex_no_such_process__' -ReceiptPath $receipt -Confirm:$false
$config = [IO.File]::ReadAllText((Join-Path $game 'd3dx.ini'))
foreach ($line in @('override_directory=ShaderFixes','cache_directory=ShaderCache-Census','cache_shaders=0','export_shaders=1','export_binary=1','export_hlsl=0','reload_fixes = no_modifiers VK_F10','reload_config = no_modifiers VK_F10')) {
    if (-not $config.Contains($line)) { throw "Enabled census lost required line: $line" }
}
$manifest = Get-Content -Raw -LiteralPath $enabled.Manifest | ConvertFrom-Json
if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $game 'd3dx.ini')).Hash -ne [string]$manifest.censusSha256) {
    throw 'Enabled census hash does not match the manifest.'
}

& (Join-Path $PSScriptRoot 'Restore-IntergradeShaderCensus.ps1') -ManifestPath $enabled.Manifest -ProcessName '__codex_no_such_process__' -Confirm:$false | Out-Null
$after = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $game 'd3dx.ini')).Hash
if ($after -ne $before) { throw 'Census restore was not byte-for-byte exact.' }

$result = [ordered]@{
    result = 'pass'
    runningProcessGuard = $guarded
    beforeSha256 = $before
    restoredSha256 = $after
    censusSha256 = [string]$manifest.censusSha256
    manifest = [string]$enabled.Manifest
}
$resultPath = Join-Path $testRoot 'result.json'
[IO.File]::WriteAllText($resultPath, ($result | ConvertTo-Json -Depth 5) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
Write-Output "PASS: reversible shader census transition verified at $resultPath"
