[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [string]$ProcessName = 'ff7remake_'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$manifestFull = (Resolve-Path -LiteralPath $ManifestPath).Path
$manifest = Get-Content -Raw -LiteralPath $manifestFull | ConvertFrom-Json
if ([int]$manifest.schemaVersion -ne 1 -or [string]$manifest.mode -ne 'intergrade-cumulative-shader-census') {
    throw 'Not an Intergrade shader-census manifest.'
}
if (@(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue).Count) {
    throw "Refusing to restore shader census while $ProcessName is running."
}

$liveIni = [IO.Path]::GetFullPath([string]$manifest.liveIni)
$backupIni = [IO.Path]::GetFullPath([string]$manifest.backupIni)
if (-not (Test-Path -LiteralPath $backupIni -PathType Leaf)) { throw "Census backup is missing: $backupIni" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $backupIni).Hash -ne [string]$manifest.beforeSha256) {
    throw 'Census backup hash mismatch.'
}
if (-not (Test-Path -LiteralPath $liveIni -PathType Leaf)) { throw "Live INI is missing: $liveIni" }
$currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $liveIni).Hash
if ($currentHash -ne [string]$manifest.censusSha256) {
    throw 'Refusing to overwrite a live INI that changed after census was enabled.'
}

if (-not $PSCmdlet.ShouldProcess($liveIni, "Restore exact pre-census INI from $backupIni")) { return }
Copy-Item -LiteralPath $backupIni -Destination $liveIni -Force
$restoredHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $liveIni).Hash
if ($restoredHash -ne [string]$manifest.beforeSha256) { throw 'Restored INI hash mismatch.' }

[pscustomobject]@{
    Result = 'shader-census-restored'
    LiveIni = $liveIni
    RestoredSha256 = $restoredHash
    Manifest = $manifestFull
}
