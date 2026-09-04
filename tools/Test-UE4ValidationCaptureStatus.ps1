[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$caseRoot = Join-Path $repoRoot 'artifacts\ue4-validation-capture-status-test'
$target = Join-Path $caseRoot 'game'
$exe = Join-Path $target 'StatusGame.exe'
$manifestPath = Join-Path $caseRoot 'install.json'
$statusPath = Join-Path $caseRoot 'status.json'
if (Test-Path -LiteralPath $caseRoot) { Remove-Item -LiteralPath $caseRoot -Recurse -Force }
[IO.Directory]::CreateDirectory($target) | Out-Null
[IO.File]::WriteAllBytes($exe,[byte[]](4,3,2,1))
$installFiles = foreach ($name in @('d3d11.dll','d3dcompiler_46.dll','nvapi64.dll','d3dx.ini')) {
    [ordered]@{relativePath=$name;hadOriginal=$false;originalSha256=$null;installedSha256=('A'*64)}
}
$manifest = [ordered]@{
    schemaVersion=1;captureId='status-game';installedAtUtc='2026-08-30T00:00:00Z'
    gameExecutable=[ordered]@{path=$exe;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash};targetRoot=$target
    kitManifest='artifacts/ue4-validation-capture-kit/capture-kit-manifest.json';kitManifestSha256=('A'*64)
    backupRoot=(Join-Path $repoRoot 'backups\UE4ValidationCaptureKit\status-game\fake');files=@($installFiles)
}
[IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
$checker = Join-Path $repoRoot 'tools\Get-UE4ValidationCaptureStatus.ps1'
& $checker -CaptureId 'status-game' -InstallManifestPath $manifestPath -OutputPath $statusPath | Out-Null
$status = Get-Content -Raw -LiteralPath $statusPath | ConvertFrom-Json
if ([string]$status.classification -ne 'awaiting-first-launch') { throw 'Missing-log state did not fail closed.' }

$log = @'
3DMigoto path: C:\Fake\d3d11.dll
*** D3D11CreateDevice called with
D3D11CreateDevice returned device handle = 0001, context handle = 0002
HackerSwapChain 0003 created to wrap 0004
'@
[IO.File]::WriteAllText((Join-Path $target 'd3d11_log.txt'),$log,[Text.UTF8Encoding]::new($false))
[IO.Directory]::CreateDirectory((Join-Path $target 'ShaderCache')) | Out-Null
[IO.File]::WriteAllBytes((Join-Path $target 'ShaderCache\1111111111111111-ps.bin'),[byte[]](1))
[IO.File]::WriteAllBytes((Join-Path $target 'ShaderCache\2222222222222222-cs.bin'),[byte[]](2))
[IO.File]::WriteAllBytes((Join-Path $target 'ShaderCache\not-a-shader.bin'),[byte[]](3))
& $checker -CaptureId 'status-game' -InstallManifestPath $manifestPath -OutputPath $statusPath | Out-Null
$status = Get-Content -Raw -LiteralPath $statusPath | ConvertFrom-Json
if ([string]$status.classification -ne 'ready-to-import' -or [int]$status.shaderCache.validShaderCount -ne 2) { throw 'Ready capture was not classified correctly.' }
if (@($status.shaderCache.stageCounts).Count -ne 2) { throw 'Shader stage counts are incomplete.' }

[IO.File]::AppendAllText((Join-Path $target 'd3d11_log.txt'),"`nWARNING: Unrecognised entry: bad setting",[Text.UTF8Encoding]::new($false))
& $checker -CaptureId 'status-game' -InstallManifestPath $manifestPath -OutputPath $statusPath | Out-Null
$status = Get-Content -Raw -LiteralPath $statusPath | ConvertFrom-Json
if ([string]$status.classification -ne 'failed-config-parse') { throw 'Config parser error did not fail closed.' }
Write-Output 'UE4 validation capture-readiness test passed.'
