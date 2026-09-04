[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$GameDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64',
    [string]$BackupRoot = 'F:\Shader3Dmigoto\FF7Remake\ShaderCensus',
    [string]$ProcessName = 'ff7remake_',
    [string]$ReceiptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$game = (Resolve-Path -LiteralPath $GameDirectory).Path.TrimEnd('\')
$ini = Join-Path $game 'd3dx.ini'
if (-not (Test-Path -LiteralPath $ini -PathType Leaf)) {
    throw "Live d3dx.ini is missing: $ini"
}
if (@(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue).Count) {
    throw "Refusing to enable shader census while $ProcessName is running."
}

$original = [IO.File]::ReadAllText($ini)
$required = [ordered]@{
    '^override_directory=ShaderFixes\s*$' = 'active ShaderFixes boundary'
    '^cache_directory=ShaderCache\s*$' = 'original cache directory'
    '^cache_shaders=0\s*$' = 'reference-only cache behavior'
    '^export_shaders=0\s*$' = 'disabled assembly export'
    '^export_hlsl=0\s*$' = 'disabled bulk HLSL decompilation'
    '^reload_fixes\s*=\s*no_modifiers\s+VK_F10\s*$' = 'F10 shader reload binding'
    '^reload_config\s*=\s*no_modifiers\s+VK_F10\s*$' = 'F10 config reload binding'
}
foreach ($entry in $required.GetEnumerator()) {
    if ([regex]::Matches($original, $entry.Key, [Text.RegularExpressions.RegexOptions]::Multiline).Count -ne 1) {
        throw "Expected exactly one $($entry.Value) line before enabling census."
    }
}
if ([regex]::Matches($original, '^export_binary\s*=', [Text.RegularExpressions.RegexOptions]::Multiline).Count -gt 1) {
    throw 'Multiple export_binary settings are not safe to rewrite.'
}

$updated = [regex]::Replace($original, '^cache_directory=ShaderCache\s*$', 'cache_directory=ShaderCache-Census', [Text.RegularExpressions.RegexOptions]::Multiline)
$updated = [regex]::Replace($updated, '^export_shaders=0\s*$', 'export_shaders=1', [Text.RegularExpressions.RegexOptions]::Multiline)
if ([regex]::IsMatch($updated, '^export_binary\s*=\s*0\s*$', [Text.RegularExpressions.RegexOptions]::Multiline)) {
    $updated = [regex]::Replace($updated, '^export_binary\s*=\s*0\s*$', 'export_binary=1', [Text.RegularExpressions.RegexOptions]::Multiline)
} elseif (-not [regex]::IsMatch($updated, '^export_binary\s*=\s*1\s*$', [Text.RegularExpressions.RegexOptions]::Multiline)) {
    $updated = [regex]::Replace($updated, '(^export_shaders=1\s*$)', "`${1}`r`nexport_binary=1", [Text.RegularExpressions.RegexOptions]::Multiline)
}

foreach ($line in @(
    'override_directory=ShaderFixes',
    'cache_directory=ShaderCache-Census',
    'cache_shaders=0',
    'export_shaders=1',
    'export_binary=1',
    'export_hlsl=0',
    'reload_fixes = no_modifiers VK_F10',
    'reload_config = no_modifiers VK_F10'
)) {
    if (-not $updated.Contains($line)) { throw "Prepared census INI lost required line: $line" }
}

$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$backup = Join-Path ([IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')) $stamp
$backupIni = Join-Path $backup 'd3dx.ini.before-census'
$manifestPath = Join-Path $backup 'manifest.json'
if ([string]::IsNullOrWhiteSpace($ReceiptPath)) {
    $project = Split-Path -Parent $PSScriptRoot
    $ReceiptPath = Join-Path $project "artifacts\shader-census\receipts\$stamp-enabled.json"
}
$receipt = [IO.Path]::GetFullPath($ReceiptPath)

if (-not $PSCmdlet.ShouldProcess($ini, "Enable cumulative shader census with backup at $backup")) { return }
[IO.Directory]::CreateDirectory($backup) | Out-Null
Copy-Item -LiteralPath $ini -Destination $backupIni
$beforeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $backupIni).Hash

$prepared = Join-Path $backup 'd3dx.ini.census'
[IO.File]::WriteAllText($prepared, $updated, [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath $prepared -Destination $ini -Force
$afterHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ini).Hash
if ($afterHash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $prepared).Hash) {
    Copy-Item -LiteralPath $backupIni -Destination $ini -Force
    throw 'Census INI verification failed; original INI was restored.'
}

$manifest = [ordered]@{
    schemaVersion = 1
    mode = 'intergrade-cumulative-shader-census'
    enabledAtUtc = [DateTime]::UtcNow.ToString('o')
    gameDirectory = $game
    liveIni = $ini
    backupIni = $backupIni
    beforeSha256 = $beforeHash
    censusSha256 = $afterHash
    cacheDirectory = 'ShaderCache-Census'
    exports = [ordered]@{ assembly = $true; originalDxbc = $true; bulkHlsl = $false }
    activeReplacementBoundary = 'ShaderFixes'
    requiresFullProcessRestartForCompleteStartupCapture = $true
}
$json = ($manifest | ConvertTo-Json -Depth 6) + [Environment]::NewLine
[IO.File]::WriteAllText($manifestPath, $json, [Text.UTF8Encoding]::new($false))
[IO.Directory]::CreateDirectory((Split-Path -Parent $receipt)) | Out-Null
[IO.File]::WriteAllText($receipt, $json, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Result = 'shader-census-enabled-restart-required'
    LiveIni = $ini
    CacheDirectory = (Join-Path $game 'ShaderCache-Census')
    Backup = $backup
    Manifest = $manifestPath
    Receipt = $receipt
    BeforeSha256 = $beforeHash
    CensusSha256 = $afterHash
}
