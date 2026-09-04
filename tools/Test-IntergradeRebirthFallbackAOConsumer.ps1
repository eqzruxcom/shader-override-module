[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-rebirth-fallback-consumer-candidate-test'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$generator = Join-Path $repoRoot 'tools\New-IntergradeRebirthFallbackAOConsumer.ps1'
$first = & $generator -OutputDirectory (Join-Path $OutputDirectory 'first')
$second = & $generator -OutputDirectory (Join-Path $OutputDirectory 'second')
if ($first.ObjectSha256 -ne $second.ObjectSha256) { throw 'Candidate object compilation was not deterministic.' }
if ($first.SourceSha256 -ne $second.SourceSha256) { throw 'Candidate source generation was not deterministic.' }

$manifest = Get-Content -Raw -LiteralPath $first.Manifest | ConvertFrom-Json
if ($manifest.shaderHash -ne 'e2aa1c8cb39e0a55' -or $manifest.stage -ne 'ps') { throw 'Unexpected target shader contract.' }
if ($manifest.runtimeAdapterEligible -ne $false -or $manifest.liveStatus -ne 'not-staged') { throw 'Offline candidate must fail closed for runtime.' }
if ($manifest.controlReservation.bindingsEmitted -ne $false) { throw 'Offline candidate emitted a key binding.' }
if ($manifest.scope -ne 'reflection and indirect-light consumer only') { throw 'Candidate scope drifted outside the consumer.' }

$source = [IO.File]::ReadAllText($first.Source)
foreach ($pattern in @('r0\.x = saturate\(r0\.x \* r0\.x\);','r0\.x = lerp\(r0\.x, 1\.0, 0\.5\);','r0\.x = pow\(saturate\(r0\.x\), 1\.75\);','r11\.w = 1 \+ -r11\.w;','r2\.xyz = r2\.xyz \* r11\.www;','r2\.xyz = r2\.xyz \* r0\.www \+ r11\.xyz;')) {
    if ([regex]::Matches($source, $pattern).Count -ne 1) { throw "Candidate source contract missing or ambiguous: $pattern" }
}
foreach ($forbidden in @('a77b589dce5822d6','(?i)(?<![A-Z0-9_])(?:VK_)?F[123](?![A-Z0-9_])','(?i)\[Key')) {
    if ($source -match $forbidden) { throw "Candidate source contains forbidden producer or binding text: $forbidden" }
}

$baselineObject = Join-Path $repoRoot 'artifacts\captured-shaders\e2aa1c8cb39e0a55-ps\e2aa1c8cb39e0a55-ps_recompiled.cso'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $baselineObject).Hash -eq $first.ObjectSha256) { throw 'AO candidate unexpectedly matches the neutral baseline object.' }

$negativeSource = Join-Path $OutputDirectory 'missing-anchor.hlsl'
$neutralSource = Join-Path $repoRoot 'artifacts\captured-shaders\e2aa1c8cb39e0a55-ps\e2aa1c8cb39e0a55-ps_decompiled.txt'
$mutated = [IO.File]::ReadAllText($neutralSource).Replace('r0.x = t6.SampleLevel(s6_s, v0.xy, 0).x;', 'r0.x = t6.SampleLevel(s6_s, v0.xy, 0).y;')
[IO.File]::WriteAllText($negativeSource, $mutated, [Text.UTF8Encoding]::new($false))
$failedClosed = $false
try { & $generator -SourcePath $negativeSource -OutputDirectory (Join-Path $OutputDirectory 'negative') | Out-Null } catch { $failedClosed = $_.Exception.Message -match 'screen-AO t6 sample anchor' }
if (-not $failedClosed) { throw 'Generator did not fail closed when the verified t6 anchor changed.' }

$report = [ordered]@{ schemaVersion=1; result='pass'; candidate='Rebirth native-SSAO fallback consumer adapter'; deterministic=$true; negativeAnchorTest='pass'; objectSha256=$first.ObjectSha256; runtimeAdapterEligible=$false; liveStatus='not-staged'; bindingsEmitted=$false }
$reportPath = Join-Path $OutputDirectory 'report.json'
[IO.File]::WriteAllText($reportPath, (($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Output 'Intergrade Rebirth fallback AO consumer tests passed.'
Write-Output "Report: $reportPath"
