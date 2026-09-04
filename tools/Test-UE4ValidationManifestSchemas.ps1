[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$captureSchema = Join-Path $repoRoot 'src\Engine\UE4\ValidationCapture\capture-manifest.schema.json'
$installSchema = Join-Path $repoRoot 'src\Engine\UE4\ValidationCapture\install-manifest.schema.json'
$sha = 'A' * 64
$capture = [ordered]@{
    schemaVersion=1; captureId='schema-test'; importedAtUtc='2026-08-30T00:00:00Z'; source='C:\Game\ShaderCache'
    localResearchOnly=$true; redistributionAllowed=$false; fxc=[ordered]@{path='C:\SDK\fxc.exe';sha256=$sha}
    capturedShaderCount=1; semanticMatchCount=0; nearMatchCount=0; semanticReport='semantic-matches.json'; semanticReportSha256=$sha
    shaders=@([ordered]@{shader='1111111111111111-ps';sourceSha256=$sha;binary='dxbc/1111111111111111-ps.bin';assembly='assembly/1111111111111111-ps.asm';assemblySha256=$sha})
}
$files = foreach ($name in @('d3d11.dll','d3dcompiler_46.dll','nvapi64.dll','d3dx.ini')) {
    [ordered]@{relativePath=$name;hadOriginal=$false;originalSha256=$null;installedSha256=$sha}
}
$install = [ordered]@{
    schemaVersion=1;captureId='schema-test';installedAtUtc='2026-08-30T00:00:00Z'
    gameExecutable=[ordered]@{path='C:\Game\Game.exe';sha256=$sha};targetRoot='C:\Game'
    kitManifest='artifacts/ue4-validation-capture-kit/capture-kit-manifest.json';kitManifestSha256=$sha
    backupRoot='C:\Project\backups\UE4ValidationCaptureKit\schema-test\stamp';files=@($files)
}
$captureJson=$capture|ConvertTo-Json -Depth 10
$installJson=$install|ConvertTo-Json -Depth 10
if(-not ($captureJson|Test-Json -SchemaFile $captureSchema -ErrorAction Stop)){throw 'Valid capture manifest failed its schema.'}
if(-not ($installJson|Test-Json -SchemaFile $installSchema -ErrorAction Stop)){throw 'Valid install manifest failed its schema.'}

$badCapture=$captureJson|ConvertFrom-Json
$badCapture.redistributionAllowed=$true
if(($badCapture|ConvertTo-Json -Depth 10)|Test-Json -SchemaFile $captureSchema -ErrorAction SilentlyContinue){throw 'Capture schema accepted redistributionAllowed=true.'}
$badCapture=$captureJson|ConvertFrom-Json
$badCapture.shaders[0].shader='not-a-shader'
if(($badCapture|ConvertTo-Json -Depth 10)|Test-Json -SchemaFile $captureSchema -ErrorAction SilentlyContinue){throw 'Capture schema accepted an invalid shader identity.'}
$badInstall=$installJson|ConvertFrom-Json
$badInstall.files[0].relativePath='unknown.dll'
if(($badInstall|ConvertTo-Json -Depth 10)|Test-Json -SchemaFile $installSchema -ErrorAction SilentlyContinue){throw 'Install schema accepted an unknown runtime target.'}
$badInstall=$installJson|ConvertFrom-Json
$badInstall.files[0].hadOriginal=$true
if(($badInstall|ConvertTo-Json -Depth 10)|Test-Json -SchemaFile $installSchema -ErrorAction SilentlyContinue){throw 'Install schema accepted hadOriginal=true with a null backup hash.'}

Write-Output 'UE4 validation capture/install manifest schema tests passed.'
