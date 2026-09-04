[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$caseRoot = Join-Path $repoRoot 'artifacts\runtime-health-test'
$runtimeRoot = Join-Path $caseRoot 'game\End\Binaries\Win64'
$modsRoot = Join-Path $runtimeRoot 'Mods'
$log = Join-Path $runtimeRoot 'd3d11_log.txt'
$output = Join-Path $repoRoot 'artifacts\runtime-health\test.json'
$checker = Join-Path $repoRoot 'tools\Get-IntergradeRuntimeHealth.ps1'
$utf8 = [Text.UTF8Encoding]::new($false)
if (Test-Path -LiteralPath $caseRoot) { Remove-Item -LiteralPath $caseRoot -Recurse -Force }
[IO.Directory]::CreateDirectory($modsRoot) | Out-Null
[IO.File]::WriteAllText((Join-Path $runtimeRoot 'd3dx.ini'), '[System]', $utf8)
[IO.File]::WriteAllText((Join-Path $modsRoot 'UE4EffectsGenerated.ini'), '[Constants]', $utf8)
$healthyLog = @'
D3D11CreateDevice returned device handle = 0001, context handle = 0002
HackerSwapChain 0003 created to wrap 0004
[ShaderOverride\Mods\UE4EffectsGenerated.ini\Test]
'@
[IO.File]::WriteAllText($log, $healthyLog, $utf8)
$writer = [IO.File]::Open($log, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
try { $health = & $checker -ProjectRoot $repoRoot -GameRoot (Join-Path $caseRoot 'game') -ProcessId $PID -OutputPath $output }
finally { $writer.Dispose() }
if ($health.Classification -ne 'healthy-generated-runtime' -or $health.Result -ne 'pass') { throw 'Healthy locked-log fixture did not pass.' }

[IO.File]::WriteAllText((Join-Path $modsRoot 'RebirthEffectsDX11.ini'), '[Legacy]', $utf8)
$legacy = & $checker -ProjectRoot $repoRoot -GameRoot (Join-Path $caseRoot 'game') -ProcessId $PID -OutputPath $output
if ($legacy.Classification -ne 'failed-legacy-conflict') { throw 'Active legacy diagnostic did not fail health classification.' }
Remove-Item -LiteralPath (Join-Path $modsRoot 'RebirthEffectsDX11.ini') -Force

[IO.File]::AppendAllText($log, "`nWARNING: Unrecognised entry: invalid", $utf8)
$parser = & $checker -ProjectRoot $repoRoot -GameRoot (Join-Path $caseRoot 'game') -ProcessId $PID -OutputPath $output
if ($parser.Classification -ne 'failed-parser') { throw 'Parser warning did not fail health classification.' }
[IO.File]::WriteAllText($log, $healthyLog, $utf8)

$exited = & $checker -ProjectRoot $repoRoot -GameRoot (Join-Path $caseRoot 'game') -ProcessId 2147483647 -OutputPath $output
if ($exited.Classification -ne 'process-exited' -or $exited.Result -ne 'fail') { throw 'Missing process was not recorded as exited.' }
$report = Get-Content -Raw -LiteralPath $output | ConvertFrom-Json
if (@($report.log.tail).Count -lt 1 -or -not $report.log.sha256) { throw 'Exit snapshot omitted preserved log evidence.' }

Write-Output 'Intergrade generated-runtime health snapshot tests passed.'
