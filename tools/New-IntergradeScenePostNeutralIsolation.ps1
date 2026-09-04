[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\generated-runtime\FF7RemakeIntergradeScenePostNeutralIsolation'),
    [string]$SourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\captured-shaders\af6cd28a0108a18a-ps\af6cd28a0108a18a-ps_decompiled.txt'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$allowed = [IO.Path]::GetFullPath((Join-Path $repo 'artifacts\generated-runtime')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$source = (Resolve-Path -LiteralPath $SourcePath).Path
if (-not $output.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Isolation output escaped generated-runtime.' }
if (-not $source.StartsWith($repo + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Isolation source escaped workspace.' }
if (Test-Path -LiteralPath $output) { throw 'Isolation output exists; preserve prior evidence and choose a fresh directory.' }
$sourceSha = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
if ($sourceSha -ne 'F002901E2D8B0B5FAE5E01D6C1197D5EF45644925D4CDA23680325E8AA3CA3E7') {
    throw 'Neutral source differs from the captured decompiled shader.'
}
$base = Get-Content -Raw -LiteralPath (Join-Path $allowed 'FF7RemakeIntergrade\runtime-manifest.json') | ConvertFrom-Json
$mods = Join-Path $output 'Mods'
$validation = Join-Path $output 'validation'
[IO.Directory]::CreateDirectory($mods) | Out-Null
[IO.Directory]::CreateDirectory($validation) | Out-Null
$shaderPath = Join-Path $mods 'RebirthScenePostNeutral_ps.hlsl'
Copy-Item -LiteralPath $source -Destination $shaderPath
$objectPath = Join-Path $validation 'neutral.cso'
$assemblyPath = Join-Path $validation 'neutral.asm'
$compile = & $FxcPath /nologo /T ps_5_0 /E main /Ges /WX /O3 /Fo $objectPath /Fc $assemblyPath $shaderPath 2>&1
if ($LASTEXITCODE -ne 0) { throw "Neutral shader compilation failed: $($compile -join [Environment]::NewLine)" }
$assembly = Get-Content -Raw -LiteralPath $assemblyPath
if ($assembly -match '(?m)^dcl_resource_.*\bt120\b') { throw 'Neutral isolation unexpectedly consumes shader control parameters.' }
foreach ($binding in @('t0','t1','t2','cb0','cb1')) {
    if ($assembly -notmatch "(?m)^//\s+$binding\s+") { throw "Neutral rebuild lost binding $binding." }
}
$ini = @'
; Diagnostic only: original bytecode versus unchanged decompiled rebuild.
; Default 0 issues no custom draw. Page Down toggles only this replacement.
; No fog, AO, saturation, or tonemap controls are installed by this INI.
[Constants]
global $ue4fx_scene_neutral_ab = 0

[KeyUE4FXScenePostNeutralAB]
key = no_modifiers VK_PAGEDOWN
type = cycle
smart = true
$ue4fx_scene_neutral_ab = 0, 1

[CustomShaderUE4FXScenePostNeutral]
ps = RebirthScenePostNeutral_ps.hlsl
handling = skip
draw = from_caller

[ShaderOverrideUE4FXScenePostNeutral]
hash = af6cd28a0108a18a
if $ue4fx_scene_neutral_ab == 1
    run = CustomShaderUE4FXScenePostNeutral
endif
'@
$utf8 = [Text.UTF8Encoding]::new($false)
$iniPath = Join-Path $mods 'UE4EffectsGenerated.ini'
[IO.File]::WriteAllText($iniPath, $ini.Replace("`r`n", "`n").Replace("`n", "`r`n") + "`r`n", $utf8)
$files = foreach ($path in @($iniPath,$shaderPath)) {
    [ordered]@{ relativePath='Mods/'+[IO.Path]::GetFileName($path); size=(Get-Item -LiteralPath $path).Length; sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
}
$manifest = [ordered]@{
    schemaVersion=1
    adapterId='FF7RemakeIntergradeScenePostNeutralIsolation'
    renderer='D3D11'
    executable=$base.executable
    licensedRegexDependency=$false
    diagnosticOnly=$true
    failClosed=$true
    status='neutral-live-parity-pending'
    shaderHash='af6cd28a0108a18a'
    source=$source.Substring($repo.Length+1).Replace('\','/')
    sourceSha256=$sourceSha
    control=[ordered]@{ key='VK_PAGEDOWN'; variable='$ue4fx_scene_neutral_ab'; default=0; values=@(0,1); labels=@('game-original','unchanged-decompiled-rebuild') }
    shaderParametersUsed=$false
    requiredLivePreconditions=@('no other active mod INIs','no replacement artifacts in ShaderFixes','stock fog restored before installation')
    files=@($files)
    generatedAtUtc=[DateTime]::UtcNow.ToString('o')
}
$manifestPath = Join-Path $output 'runtime-manifest.json'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8)+[Environment]::NewLine, $utf8)
[pscustomobject]@{ Output=$output; Manifest=$manifestPath; Status=$manifest.status; Files=@($files).Count; ShaderSourceSha256=$sourceSha }
