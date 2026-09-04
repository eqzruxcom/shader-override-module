[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output = Join-Path $repo ('artifacts\generated-runtime\NeutralIsolationTest-' + [Guid]::NewGuid().ToString('N'))
$generator = Join-Path $PSScriptRoot 'New-IntergradeScenePostNeutralIsolation.ps1'
$result = & $generator -OutputDirectory $output
$manifest = Get-Content -Raw -LiteralPath $result.Manifest | ConvertFrom-Json
if (-not $manifest.diagnosticOnly -or -not $manifest.failClosed -or $manifest.status -ne 'neutral-live-parity-pending') { throw 'Isolation was promoted without live evidence.' }
if ([int]$manifest.control.default -ne 0 -or $manifest.shaderParametersUsed) { throw 'Isolation does not start in original-bytecode mode.' }
if (@($manifest.files).Count -ne 2) { throw 'Isolation payload is not exactly two files.' }
foreach ($file in $manifest.files) {
    if ((Get-FileHash -LiteralPath (Join-Path $output $file.relativePath) -Algorithm SHA256).Hash -ne $file.sha256) { throw 'Payload fingerprint mismatch.' }
}
$ini = Get-Content -Raw -LiteralPath (Join-Path $output 'Mods\UE4EffectsGenerated.ini')
if ($ini -notmatch '(?m)^global \$ue4fx_scene_neutral_ab = 0\r?$') { throw 'Missing original default.' }
if ($ini -notmatch '(?ms)^if \$ue4fx_scene_neutral_ab == 1\r?\n    run = CustomShaderUE4FXScenePostNeutral\r?\nendif') { throw 'Custom draw is not explicitly gated.' }
if (@([regex]::Matches($ini,'(?m)^run\s*=|^\s+run\s*=')).Count -ne 1) { throw 'Unexpected custom commands outside isolation gate.' }
if ($ini -match 'ef7fe8d9c4e9ad15|a77b589dce5822d6|e2aa1c8cb39e0a55|[xyzw]101\s*=|(?i)shift|VK_F9|VK_F3') { throw 'Unrelated controls leaked into isolation.' }
$shader = Join-Path $output 'Mods\RebirthScenePostNeutral_ps.hlsl'
if ((Get-FileHash -LiteralPath $shader -Algorithm SHA256).Hash -ne $manifest.sourceSha256) { throw 'Neutral source was modified.' }
$refused = $false
try { & $generator -OutputDirectory $output | Out-Null } catch { $refused = $_.Exception.Message -match 'output exists' }
if (-not $refused) { throw 'Generator overwrote previous evidence.' }

# Test the real reload classifier against a neutral-only fixture and exact process.
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
if (@($baseline.expectedControlKeys).Count -ne 1 -or $baseline.expectedControlKeys[0] -ne 'UE4FXScenePostNeutralAB') { throw 'Neutral reload baseline retained unrelated keys.' }
if (@($baseline.expectedEligibleHashes).Count -ne 1) { throw 'Neutral reload baseline retained unrelated hashes.' }
$statusTool = Join-Path $PSScriptRoot 'Get-UE4GeneratedRuntimeLiveReloadStatus.ps1'
$pending = & $statusTool -GeneratedRuntimeDirectory $output
if ($pending.Classification -ne 'pending-no-reload') { throw 'Neutral fixture falsely passed before reload.' }
[IO.File]::AppendAllText($log, "> d3dx.ini reloaded`r`n[ShaderOverride\Mods\UE4EffectsGenerated.ini\UE4FXScenePostNeutral]`r`nHash = af6cd28a0108a18a`r`n", $utf8)
$incomplete = & $statusTool -GeneratedRuntimeDirectory $output
if ($incomplete.Classification -ne 'failed-generated-keys-incomplete') { throw 'Neutral fixture accepted missing A/B key.' }
[IO.File]::AppendAllText($log, "[Key\Mods\UE4EffectsGenerated.ini\UE4FXScenePostNeutralAB]`r`n", $utf8)
$passed = & $statusTool -GeneratedRuntimeDirectory $output
if ($passed.Classification -ne 'passed-live-parser-reload') { throw 'Neutral fixture did not accept a complete reload.' }
Write-Output 'Neutral scene-post isolation build and reload tests passed.'
Write-Output $output
