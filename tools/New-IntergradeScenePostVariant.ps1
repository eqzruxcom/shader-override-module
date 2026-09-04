[CmdletBinding()]
param(
    [string]$SourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\captured-shaders\af6cd28a0108a18a-ps\af6cd28a0108a18a-ps_decompiled.txt'),
    [string]$TonemapLibraryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Effects\Post\Tonemaps.hlsl'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\scene-post-generator'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$utf8 = [Text.UTF8Encoding]::new($false)

function Resolve-WorkspacePath([string]$Path, [switch]$AllowMissing) {
    $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) }
    else { [IO.Path]::GetFullPath((Join-Path $repoRoot $Path)) }
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must remain inside the project workspace: $full"
    }
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "Required file does not exist: $full"
    }
    return $full
}

$sourceFull = Resolve-WorkspacePath $SourcePath
$libraryFull = Resolve-WorkspacePath $TonemapLibraryPath
$outputFull = Resolve-WorkspacePath $OutputDirectory -AllowMissing
[IO.Directory]::CreateDirectory($outputFull) | Out-Null
if (-not (Test-Path -LiteralPath $FxcPath -PathType Leaf)) { throw "FXC was not found: $FxcPath" }

$source = [IO.File]::ReadAllText($sourceFull).Replace("`r`n", "`n")
$library = [IO.File]::ReadAllText($libraryFull).Replace("`r`n", "`n")
if (([regex]::Matches($source, '(?m)^Texture1D<float4> IniParams : register\(t120\);$')).Count -ne 1) {
    throw 'Expected exactly one t120 IniParams declaration in the captured shader.'
}
$guardOpen = "#ifndef REDX11_TONEMAPS_HLSL`n#define REDX11_TONEMAPS_HLSL`n"
if (-not $library.StartsWith($guardOpen) -or -not $library.TrimEnd().EndsWith('#endif')) {
    throw 'Tonemap library guard structure is not recognized.'
}
$libraryBody = $library.Substring($guardOpen.Length)
$lastEndIf = $libraryBody.LastIndexOf('#endif', [StringComparison]::Ordinal)
if ($lastEndIf -lt 0) { throw 'Tonemap library closing guard is missing.' }
$libraryBody = $libraryBody.Substring(0, $lastEndIf).Trim()
if ($libraryBody -match '(?m)^\s*#include\s+') { throw 'Tonemap library contains an unresolved include.' }

$mainMarker = "`nvoid main(`n"
if (([regex]::Matches($source, [regex]::Escape($mainMarker))).Count -ne 1) {
    throw 'Captured shader main-function marker is not unique.'
}
$generated = $source.Replace($mainMarker, "`n// Portable SM5 tonemap library, embedded by the generator.`n$libraryBody`n`nvoid main(`n")
$outputPattern = '(?m)^  o0\.xyz = r5\.xyz;\n  o0\.w = 0;$'
if (([regex]::Matches($generated, $outputPattern)).Count -ne 1) {
    throw 'Expected exactly one scene-color output assignment.'
}
$replacement = @'
  // Dynamic scene-only controls. The HUD is composed after this pass.
  // IniParams row 101: x = saturation [0,1], w = tonemap mode [0,8].
  float4 redx11ScenePost = IniParams.Load(int2(101, 0));
  float redx11Saturation = clamp(redx11ScenePost.x, 0.0f, 1.0f);
  uint redx11TonemapMode = (uint)clamp(floor(redx11ScenePost.w + 0.5f), 0.0f, 8.0f);
  float redx11SceneLuma = dot(r5.xyz, float3(0.2126f, 0.7152f, 0.0722f));
  float3 redx11Adjusted = lerp(redx11SceneLuma.xxx, r5.xyz, redx11Saturation);
  o0.xyz = Redx11ApplyTonemap(redx11Adjusted, redx11TonemapMode);
  o0.w = 0;
'@ -replace "`r`n", "`n"
$generated = [regex]::Replace($generated, $outputPattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement }, 1)

$base = 'RebirthPostSceneControls_ps'
$hlslPath = Join-Path $outputFull "$base.hlsl"
$objectPath = Join-Path $outputFull "$base.cso"
$assemblyPath = Join-Path $outputFull "$base.asm"
$manifestPath = Join-Path $outputFull "$base.json"
[IO.File]::WriteAllText($hlslPath, $generated, $utf8)
$compilerOutput = & $FxcPath /nologo /T ps_5_0 /E main /Ges /WX /O3 /Fo $objectPath /Fc $assemblyPath $hlslPath 2>&1
if ($LASTEXITCODE -ne 0) { throw "FXC failed for $base`n$($compilerOutput -join [Environment]::NewLine)" }
$assembly = [IO.File]::ReadAllText($assemblyPath)
foreach ($binding in @('t0','t1','t2','cb0','cb1')) {
    if ($assembly -notmatch "(?m)^//\s+$binding\s+") { throw "Compiled scene-post shader is missing binding $binding." }
}
if ($assembly -notmatch '(?m)^//\s+SV_Target\s+0\s+xyzw') { throw 'Compiled scene-post shader is missing SV_Target0.' }
if ($assembly -notmatch '(?m)^dcl_resource_texture1d \(float,float,float,float\) t120\r?$') {
    throw 'Compiled scene-post shader does not read the 3Dmigoto IniParams texture.'
}

$manifest = [ordered]@{
    schemaVersion = 1
    adapter = 'FF7RemakeIntergrade'
    shaderHash = 'af6cd28a0108a18a'
    stage = 'ps'
    effect = 'scene-saturation-and-tonemap'
    status = 'strict-compile-neutral-live-parity-pending'
    source = $hlslPath.Substring($repoRoot.Length + 1).Replace('\','/')
    sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hlslPath).Hash
    object = $objectPath.Substring($repoRoot.Length + 1).Replace('\','/')
    objectSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectPath).Hash
    assembly = $assemblyPath.Substring($repoRoot.Length + 1).Replace('\','/')
    assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assemblyPath).Hash
    tonemapLibrary = $libraryFull.Substring($repoRoot.Length + 1).Replace('\','/')
    tonemapLibrarySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $libraryFull).Hash
    controls = [ordered]@{
        iniTexture = 't120'
        row = 101
        saturationComponent = 'x'
        tonemapModeComponent = 'w'
        neutral = [ordered]@{ saturation = 1.0; tonemapMode = 0 }
        tonemapModes = @('none','reinhard','reinhard2','aces-2015','aces-fitted','filmic','uncharted2','unreal3','khronos-neutral')
    }
    contract = [ordered]@{
        inputs = @('t0','t1','t2','t120','cb0','cb1')
        output = 'SV_Target0'
        preserveAlphaBehavior = 'o0.w = 0'
        uiComposedAfterPass = $true
        alwaysOnNeutralReplacement = $true
    }
    compiler = [ordered]@{ profile='ps_5_0';entry='main';flags=@('/Ges','/WX','/O3') }
}
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 10)+[Environment]::NewLine, $utf8)

[pscustomobject]@{
    ShaderHash = 'af6cd28a0108a18a'
    Status = [string]$manifest.status
    Source = $hlslPath
    Object = $objectPath
    Assembly = $assemblyPath
    Manifest = $manifestPath
    SourceSha256 = [string]$manifest.sourceSha256
    ObjectSha256 = [string]$manifest.objectSha256
}
