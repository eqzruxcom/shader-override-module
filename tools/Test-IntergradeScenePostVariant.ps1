[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\scene-post-generator-test')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$generator = Join-Path $repoRoot 'tools\New-IntergradeScenePostVariant.ps1'
$outputFull = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $outputFull) { Remove-Item -LiteralPath $outputFull -Recurse -Force }

$result = & $generator -OutputDirectory $outputFull
foreach ($path in @($result.Source,$result.Object,$result.Assembly,$result.Manifest)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Scene-post generator output is missing: $path" }
}
$manifest = Get-Content -Raw -LiteralPath $result.Manifest | ConvertFrom-Json
if ($manifest.shaderHash -ne 'af6cd28a0108a18a' -or $manifest.stage -ne 'ps' -or $manifest.status -ne 'strict-compile-neutral-live-parity-pending') {
    throw 'Scene-post manifest identity or fail-closed status is invalid.'
}
if ($manifest.controls.iniTexture -ne 't120' -or [int]$manifest.controls.row -ne 101) { throw 'Scene-post control binding is invalid.' }
if ([double]$manifest.controls.neutral.saturation -ne 1.0 -or [int]$manifest.controls.neutral.tonemapMode -ne 0) {
    throw 'Scene-post neutral settings are invalid.'
}
if (@($manifest.controls.tonemapModes).Count -ne 9) { throw 'Scene-post tonemap mode table is incomplete.' }
$source = Get-Content -Raw -LiteralPath $result.Source
foreach ($required in @('IniParams.Load(int2(101, 0))','Redx11ApplyTonemap','redx11Saturation','redx11TonemapMode')) {
    if (-not $source.Contains($required)) { throw "Generated scene-post source omitted: $required" }
}
if (([regex]::Matches($source, '(?m)^  o0\.w = 0;$')).Count -ne 1) { throw 'Scene-post shader did not preserve alpha behavior exactly once.' }
$assembly = Get-Content -Raw -LiteralPath $result.Assembly
if ($assembly -notmatch '(?m)^dcl_resource_texture1d \(float,float,float,float\) t120\r?$') { throw 'Scene-post assembly omitted t120.' }

$badSource = Join-Path $outputFull 'bad-source.hlsl'
$captured = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'artifacts\captured-shaders\af6cd28a0108a18a-ps\af6cd28a0108a18a-ps_decompiled.txt')
[IO.File]::WriteAllText($badSource, $captured.Replace('  o0.w = 0;', "  o0.w = 0;`n  o0.xyz = r5.xyz;`n  o0.w = 0;"), [Text.UTF8Encoding]::new($false))
$refusedAmbiguous = $false
try { & $generator -SourcePath $badSource -OutputDirectory (Join-Path $outputFull 'bad') | Out-Null }
catch { $refusedAmbiguous = $_.Exception.Message -match 'exactly one scene-color output assignment' }
if (-not $refusedAmbiguous) { throw 'Scene-post generator accepted an ambiguous output assignment.' }

Write-Output 'Intergrade dynamic scene-post variant tests passed.'
Write-Output "Manifest: $($result.Manifest)"
