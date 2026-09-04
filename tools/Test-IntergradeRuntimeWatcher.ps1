[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$caseRoot = Join-Path $repoRoot 'artifacts\runtime-watcher-test'
$gameRoot = Join-Path $caseRoot 'game'
$runtimeRoot = Join-Path $gameRoot 'End\Binaries\Win64'
$modsRoot = Join-Path $runtimeRoot 'Mods'
$output = Join-Path $repoRoot 'artifacts\runtime-health\watcher-test'
$utf8 = [Text.UTF8Encoding]::new($false)
if (Test-Path -LiteralPath $caseRoot) { Remove-Item -LiteralPath $caseRoot -Recurse -Force }
if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Recurse -Force }
[IO.Directory]::CreateDirectory($modsRoot) | Out-Null
[IO.File]::WriteAllText((Join-Path $runtimeRoot 'd3dx.ini'),'[System]',$utf8)
[IO.File]::WriteAllText((Join-Path $modsRoot 'UE4EffectsGenerated.ini'),'[Constants]',$utf8)
$log = @'
D3D11CreateDevice returned device handle = 0001, context handle = 0002
HackerSwapChain 0003 created to wrap 0004
[ShaderOverride\Mods\UE4EffectsGenerated.ini\Test]
'@
[IO.File]::WriteAllText((Join-Path $runtimeRoot 'd3d11_log.txt'),$log,$utf8)
$pwsh = (Get-Process -Id $PID).Path
$child = Start-Process -FilePath $pwsh -ArgumentList @('-NoLogo','-NoProfile','-Command','Start-Sleep -Seconds 2') -PassThru -WindowStyle Hidden
& (Join-Path $repoRoot 'tools\Watch-IntergradeRuntime.ps1') -ProcessId $child.Id -ProjectRoot $repoRoot -GameRoot $gameRoot -PollSeconds 1 -MaxMinutes 1 -OutputDirectory $output | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $output 'startup.json') -PathType Leaf)) { throw 'Watcher did not record startup health.' }
if (-not (Test-Path -LiteralPath (Join-Path $output 'exit.json') -PathType Leaf)) { throw 'Watcher did not record exit health.' }
if (-not (Test-Path -LiteralPath (Join-Path $output 'watch-summary.json') -PathType Leaf)) { throw 'Watcher did not record an exit summary.' }
$exit = Get-Content -Raw -LiteralPath (Join-Path $output 'exit.json') | ConvertFrom-Json
$summary = Get-Content -Raw -LiteralPath (Join-Path $output 'watch-summary.json') | ConvertFrom-Json
if ($exit.classification -ne 'process-exited' -or $exit.result -ne 'fail') { throw 'Watcher exit snapshot did not preserve process-exited classification.' }
if ([int]$summary.processId -ne [int]$child.Id -or $summary.classification -ne 'process-exited') { throw 'Watcher exit summary identity is incorrect.' }
if (@($exit.log.tail).Count -lt 1 -or -not $exit.log.sha256) { throw 'Watcher exit snapshot omitted final log evidence.' }

Write-Output 'Intergrade bounded runtime watcher tests passed.'
