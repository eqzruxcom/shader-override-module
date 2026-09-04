[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$caseRoot = Join-Path $repoRoot 'artifacts\ue4-validation-capture-kit-install-test'
$gameRoot = Join-Path $caseRoot 'FakeGame\Binaries\Win64'
$exe = Join-Path $gameRoot 'NeutralGame.exe'
$installManifest = Join-Path $caseRoot 'install.json'
if (Test-Path -LiteralPath $caseRoot) { Remove-Item -LiteralPath $caseRoot -Recurse -Force }
[IO.Directory]::CreateDirectory($gameRoot) | Out-Null
[IO.File]::WriteAllBytes($exe, [byte[]](1,2,3,4))
$originalConfig = 'preexisting-d3dx-config'
[IO.File]::WriteAllText((Join-Path $gameRoot 'd3dx.ini'), $originalConfig, [Text.UTF8Encoding]::new($false))
$installer = Join-Path $repoRoot 'tools\Install-UE4ValidationCaptureKit.ps1'
$uninstaller = Join-Path $repoRoot 'tools\Uninstall-UE4ValidationCaptureKit.ps1'
& $installer -GameExecutable $exe -CaptureId 'fake-game' -InstallManifestPath $installManifest -Confirm:$false | Out-Null
$manifest = Get-Content -Raw -LiteralPath $installManifest | ConvertFrom-Json
if (@($manifest.files).Count -ne 4) { throw 'Installer did not record four runtime files.' }
foreach ($name in @('d3d11.dll','d3dcompiler_46.dll','nvapi64.dll','d3dx.ini')) { if (-not (Test-Path -LiteralPath (Join-Path $gameRoot $name) -PathType Leaf)) { throw "Installed file missing: $name" } }
& $uninstaller -CaptureId 'fake-game' -InstallManifestPath $installManifest -Confirm:$false | Out-Null
if ([IO.File]::ReadAllText((Join-Path $gameRoot 'd3dx.ini')) -ne $originalConfig) { throw 'Preexisting d3dx.ini was not restored exactly.' }
foreach ($name in @('d3d11.dll','d3dcompiler_46.dll','nvapi64.dll')) { if (Test-Path -LiteralPath (Join-Path $gameRoot $name)) { throw "Generated-only file was not removed: $name" } }

& $installer -GameExecutable $exe -CaptureId 'fake-game' -InstallManifestPath $installManifest -Confirm:$false | Out-Null
$dll = Join-Path $gameRoot 'd3d11.dll'
[IO.File]::WriteAllBytes($dll, [byte[]](9,9,9))
$refused = $false
try { & $uninstaller -CaptureId 'fake-game' -InstallManifestPath $installManifest -Confirm:$false | Out-Null } catch { $refused = $_.Exception.Message -match 'modified generated-only file' }
if (-not $refused) { throw 'Rollback did not refuse deletion of a modified generated-only file.' }
Copy-Item -LiteralPath (Join-Path $repoRoot 'artifacts\ue4-validation-capture-kit\d3d11.dll') -Destination $dll -Force
& $uninstaller -CaptureId 'fake-game' -InstallManifestPath $installManifest -Confirm:$false | Out-Null
Write-Output 'UE4 validation capture-kit install/rollback test passed.'
