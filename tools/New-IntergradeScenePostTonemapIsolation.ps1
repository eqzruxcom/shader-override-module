[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
# The neutral generator validates source identity, confines output, refuses
# overwrites, and verifies the unchanged source before this single-effect edit.
$neutral = & (Join-Path $PSScriptRoot 'New-IntergradeScenePostNeutralIsolation.ps1') -OutputDirectory $OutputDirectory -FxcPath $FxcPath
$output = $neutral.Output
$shader = Join-Path $output 'Mods\RebirthScenePostNeutral_ps.hlsl'
$libraryPath = Join-Path $repo 'src\Effects\Post\Tonemaps.hlsl'
$source = [IO.File]::ReadAllText($shader).Replace("`r`n", "`n")
$library = [IO.File]::ReadAllText($libraryPath).Replace("`r`n", "`n")
if ($library -match '(?m)^\s*#include\s+') { throw 'Tonemap isolation library must be self-contained.' }
$marker = "`nvoid main(`n"
if (([regex]::Matches($source, [regex]::Escape($marker))).Count -ne 1) { throw 'Main marker is not unique.' }
$assignment = '  o0.xyz = r5.xyz;'
if (([regex]::Matches($source, [regex]::Escape($assignment))).Count -ne 1) { throw 'Scene output is not unique.' }
$source = $source.Replace($marker, "`n$library`nvoid main(`n").Replace($assignment,
    '  o0.xyz = Redx11ApplyTonemap(r5.xyz, REDX11_TONEMAP_REINHARD);')
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($shader, $source, $utf8)
$objectPath = Join-Path $output 'validation\reinhard.cso'
$assemblyPath = Join-Path $output 'validation\reinhard.asm'
$compile = & $FxcPath /nologo /T ps_5_0 /E main /Ges /WX /O3 /Fo $objectPath /Fc $assemblyPath $shader 2>&1
if ($LASTEXITCODE -ne 0) { throw "Reinhard isolation compilation failed: $($compile -join [Environment]::NewLine)" }
$assembly = Get-Content -Raw -LiteralPath $assemblyPath
if ($assembly -match '(?m)^dcl_resource_.*\bt120\b') { throw 'Static Reinhard isolation must not consume IniParams.' }
foreach ($binding in @('t0','t1','t2','cb0','cb1')) {
    if ($assembly -notmatch "(?m)^//\s+$binding\s+") { throw "Reinhard rebuild lost binding $binding." }
}
if ($assembly -notmatch '(?m)^//\s+SV_Target\s+0\s+xyzw') { throw 'Missing SV_Target0.' }
$ini = @'
; Diagnostic only: actual game original versus static Reinhard scene output.
; Page Down toggles this one effect; no fog, AO, or dynamic shader parameters.
[Constants]
global $ue4fx_scene_tonemap_ab = 0

[KeyUE4FXScenePostTonemapAB]
key = no_modifiers VK_PAGEDOWN
type = cycle
smart = true
$ue4fx_scene_tonemap_ab = 0, 1

[CustomShaderUE4FXScenePostTonemap]
ps = RebirthScenePostNeutral_ps.hlsl
handling = skip
draw = from_caller

[ShaderOverrideUE4FXScenePostTonemap]
hash = af6cd28a0108a18a
if $ue4fx_scene_tonemap_ab == 1
    run = CustomShaderUE4FXScenePostTonemap
endif
'@
# Reuse the neutral payload filename so the overlay backs up and replaces
# both existing files, leaving no orphaned neutral shader on rollback.
$iniPath = Join-Path $output 'Mods\UE4EffectsGenerated.ini'
[IO.File]::WriteAllText($iniPath, $ini.Replace("`r`n", "`n").Replace("`n", "`r`n") + "`r`n", $utf8)
$manifest = Get-Content -Raw -LiteralPath $neutral.Manifest | ConvertFrom-Json -AsHashtable
$manifest.adapterId = 'FF7RemakeIntergradeScenePostTonemapIsolation'
$manifest.status = 'effect-live-validation-pending'
$manifest.effect = 'static-reinhard-scene-output'
$manifest.control = [ordered]@{ key='VK_PAGEDOWN'; variable='$ue4fx_scene_tonemap_ab'; default=0; values=@(0,1); labels=@('game-original','static-reinhard') }
$manifest.tonemapLibrary = $libraryPath.Substring($repo.Length+1).Replace('\','/')
$manifest.tonemapLibrarySha256 = (Get-FileHash -LiteralPath $libraryPath -Algorithm SHA256).Hash
$manifest.requiredLivePreconditions = @('no other active mod INIs','no replacement artifacts in ShaderFixes','neutral comparison visually unchanged in current scene')
$manifest.files = @(foreach ($path in @($iniPath,$shader)) {
    [ordered]@{ relativePath='Mods/'+[IO.Path]::GetFileName($path); size=(Get-Item -LiteralPath $path).Length; sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
})
$manifest.generatedAtUtc = [DateTime]::UtcNow.ToString('o')
[IO.File]::WriteAllText($neutral.Manifest, ($manifest | ConvertTo-Json -Depth 8)+[Environment]::NewLine, $utf8)
[pscustomobject]@{ Output=$output; Manifest=$neutral.Manifest; Status=$manifest.status; Files=@($manifest.files).Count; Assembly=$assemblyPath }
