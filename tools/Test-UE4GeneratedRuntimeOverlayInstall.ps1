[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$testRoot = Join-Path $repoRoot 'artifacts\generated-runtime\install-test'
$gameRoot = Join-Path $testRoot 'game'
$targetRoot = Join-Path $gameRoot 'End\Binaries\Win64'
$modsRoot = Join-Path $targetRoot 'Mods'
$manifestPath = Join-Path $testRoot 'installed.json'
$installer = Join-Path $repoRoot 'tools\Install-UE4GeneratedRuntimeOverlay.ps1'
$uninstaller = Join-Path $repoRoot 'tools\Uninstall-UE4GeneratedRuntimeOverlay.ps1'
$generatedRoot = Join-Path $repoRoot 'artifacts\generated-runtime\FF7RemakeIntergrade'

if (Test-Path -LiteralPath $testRoot -PathType Container) {
    $resolved = (Resolve-Path -LiteralPath $testRoot).Path
    $allowed = (Resolve-Path -LiteralPath (Join-Path $repoRoot 'artifacts\generated-runtime')).Path
    if (-not $resolved.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe generated-runtime install-test path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
[IO.Directory]::CreateDirectory($modsRoot) | Out-Null
[IO.File]::WriteAllText((Join-Path $targetRoot 'ff7remake_.exe'), 'test executable', [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $modsRoot 'RebirthPostSceneSaturation000_ps.hlsl'), 'preexisting shader', [Text.UTF8Encoding]::new($false))
$originalSha = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $modsRoot 'RebirthPostSceneSaturation000_ps.hlsl')).Hash

$legacyDiagnostic = Join-Path $modsRoot 'RebirthEffectsDX11.ini'
[IO.File]::WriteAllText($legacyDiagnostic, '[ShaderOverrideLegacy]', [Text.UTF8Encoding]::new($false))
$refusedLegacy = $false
try { & $installer -ProjectRoot $repoRoot -GeneratedRuntimeDirectory $generatedRoot -GameRoot $gameRoot -InstallManifestPath $manifestPath -AllowUnknownExecutable | Out-Null }
catch { $refusedLegacy = $_.Exception.Message -match 'legacy diagnostic INIs are active' }
if (-not $refusedLegacy) { throw 'Overlay installer accepted an active legacy diagnostic INI.' }
Remove-Item -LiteralPath $legacyDiagnostic -Force

& $installer -ProjectRoot $repoRoot -GeneratedRuntimeDirectory $generatedRoot -GameRoot $gameRoot -InstallManifestPath $manifestPath -AllowUnknownExecutable | Out-Null
$installed = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if (@($installed.files).Count -ne 13) { throw 'Overlay installer did not install all generated files.' }
if (@($installed.files | Where-Object { $_.relativePath -eq 'Mods/RebirthPostSceneSaturation000_ps.hlsl' -and $_.hadOriginal }).Count -ne 1) {
    throw 'Overlay installer did not record the preexisting file.'
}
if (-not (Test-Path -LiteralPath (Join-Path $modsRoot 'UE4EffectsGenerated.ini') -PathType Leaf)) { throw 'Generated INI was not installed.' }

& $uninstaller -ProjectRoot $repoRoot -InstallManifestPath $manifestPath | Out-Null
if (Test-Path -LiteralPath (Join-Path $modsRoot 'UE4EffectsGenerated.ini') -PathType Leaf) { throw 'Generated INI was not removed during rollback.' }
$restoredPath = Join-Path $modsRoot 'RebirthPostSceneSaturation000_ps.hlsl'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $restoredPath).Hash -ne $originalSha) { throw 'Preexisting shader was not restored exactly.' }

Write-Output 'UE4 generated runtime overlay install/rollback test passed.'
[pscustomobject]@{
    InstalledFiles = @($installed.files).Count
    RestoredPreexisting = $true
    RemovedGeneratedOnly = $true
    Result = 'pass'
}
