[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output = Join-Path $repo ('artifacts\generated-runtime\TonemapIsolationTest-' + [Guid]::NewGuid().ToString('N'))
$generator = Join-Path $PSScriptRoot 'New-IntergradeScenePostTonemapIsolation.ps1'
$result = & $generator -OutputDirectory $output
$manifest = Get-Content -Raw -LiteralPath $result.Manifest | ConvertFrom-Json
if (-not $manifest.diagnosticOnly -or -not $manifest.failClosed -or $manifest.status -ne 'effect-live-validation-pending') { throw 'Isolation was promoted without visual evidence.' }
if ($manifest.adapterId -ne 'FF7RemakeIntergradeScenePostTonemapIsolation' -or $manifest.shaderParametersUsed) { throw 'Wrong isolation identity or dynamic controls.' }
if ([int]$manifest.control.default -ne 0 -or $manifest.control.labels[0] -ne 'game-original' -or $manifest.control.labels[1] -ne 'static-reinhard') { throw 'Wrong A/B states.' }
if (@($manifest.files).Count -ne 2) { throw 'Unexpected payload count.' }
foreach ($file in $manifest.files) {
    if ((Get-FileHash -LiteralPath (Join-Path $output $file.relativePath) -Algorithm SHA256).Hash -ne $file.sha256) { throw 'Payload fingerprint mismatch.' }
}
$ini = Get-Content -Raw -LiteralPath (Join-Path $output 'Mods\UE4EffectsGenerated.ini')
if ($ini -notmatch '(?m)^global \$ue4fx_scene_tonemap_ab = 0\r?$') { throw 'Missing original default.' }
if ($ini -notmatch '(?ms)^if \$ue4fx_scene_tonemap_ab == 1\r?\n    run = CustomShaderUE4FXScenePostTonemap\r?\nendif') { throw 'Custom draw is not explicitly gated.' }
if ([regex]::Matches($ini,'(?m)^\s*run\s*=').Count -ne 1 -or [regex]::Matches($ini,'(?m)^hash\s*=').Count -ne 1) { throw 'Unexpected override commands.' }
if ($ini -match 'ef7fe8d9c4e9ad15|a77b589dce5822d6|e2aa1c8cb39e0a55|[xyzw]101\s*=|VK_F9|VK_F3|VK_INSERT|VK_HOME|VK_PAGEUP') { throw 'Unrelated controls leaked into isolation.' }
$shader = Get-Content -Raw -LiteralPath (Join-Path $output 'Mods\RebirthScenePostNeutral_ps.hlsl')
if (-not $shader.Contains('o0.xyz = Redx11ApplyTonemap(r5.xyz, REDX11_TONEMAP_REINHARD);')) { throw 'Missing static Reinhard output.' }
if ($shader -match 'IniParams.Load|redx11Saturation' -or [regex]::Matches($shader,'(?m)^  o0.w = 0;$').Count -ne 1) { throw 'Changed alpha or extra controls.' }
$assembly = Get-Content -Raw -LiteralPath $result.Assembly
if ($assembly -match '(?m)^dcl_resource_.*\bt120\b') { throw 'Unexpected dynamic texture binding.' }
$refused = $false
try { & $generator -OutputDirectory $output | Out-Null } catch { $refused = $_.Exception.Message -match 'output exists' }
if (-not $refused) { throw 'Generator overwrote previous evidence.' }

$game = Join-Path $output 'fixture-game'
$live = Join-Path $game 'End\Binaries\Win64'
[IO.Directory]::CreateDirectory((Join-Path $live 'Mods')) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$records = foreach ($file in $manifest.files) {
    Copy-Item -LiteralPath (Join-Path $output $file.relativePath) -Destination (Join-Path $live $file.relativePath)
    [ordered]@{ relativePath=$file.relativePath; installedSha256=$file.sha256 }
}
$install = Join-Path $output 'fixture-installed.json'
[IO.File]::WriteAllText($install, (@{adapterId=$manifest.adapterId; files=@($records)} | ConvertTo-Json -Depth 6), $utf8)
$log = Join-Path $live 'd3d11_log.txt'
[IO.File]::WriteAllText($log, "fixture startup`r`n", $utf8)
$baselineResult = & (Join-Path $PSScriptRoot 'New-IntergradeScenePostDiagnosticReloadBaseline.ps1') -GeneratedRuntimeDirectory $output -InstallManifestPath $install -GameRoot $game -ProcessId $PID
$baseline = Get-Content -Raw -LiteralPath $baselineResult.Baseline | ConvertFrom-Json
if (@($baseline.expectedControlKeys).Count -ne 1 -or $baseline.expectedControlKeys[0] -ne 'UE4FXScenePostTonemapAB' -or @($baseline.expectedEligibleHashes).Count -ne 1) { throw 'Wrong reload expectations.' }
$statusTool = Join-Path $PSScriptRoot 'Get-UE4GeneratedRuntimeLiveReloadStatus.ps1'
if ((& $statusTool -GeneratedRuntimeDirectory $output).Classification -ne 'pending-no-reload') { throw 'False success before reload.' }
[IO.File]::AppendAllText($log, "> d3dx.ini reloaded`r`n[ShaderOverride\Mods\UE4EffectsGenerated.ini\UE4FXScenePostTonemap]`r`nHash = af6cd28a0108a18a`r`n", $utf8)
if ((& $statusTool -GeneratedRuntimeDirectory $output).Classification -ne 'failed-generated-keys-incomplete') { throw 'Accepted missing A/B key.' }
[IO.File]::AppendAllText($log, "[Key\Mods\UE4EffectsGenerated.ini\UE4FXScenePostTonemapAB]`r`n", $utf8)
if ((& $statusTool -GeneratedRuntimeDirectory $output).Classification -ne 'passed-live-parser-reload') { throw 'Rejected complete reload.' }
Write-Output 'Static Reinhard scene-post isolation and reload tests passed.'
Write-Output $output
