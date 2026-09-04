[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$fixtureRoot = Join-Path $repoRoot 'artifacts\ue4-validation-candidate-test\fixtures'
$reportPath = Join-Path $repoRoot 'artifacts\ue4-validation-candidate-test\report.json'
$scanner = Join-Path $repoRoot 'tools\Find-UE4ValidationCandidates.ps1'

if (Test-Path -LiteralPath $fixtureRoot) {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}

$sm5 = Join-Path $fixtureRoot 'Stock UE4 SM5'
$sm6 = Join-Path $fixtureRoot 'Stock UE SM6'
$unknown = Join-Path $fixtureRoot 'Unreal Unknown Model'
$unity = Join-Path $fixtureRoot 'Unity Game'
foreach ($path in @($sm5, $sm6, $unknown, $unity)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
}
New-Item -ItemType Directory -Path (Join-Path $sm5 'Engine') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $sm6 'Engine') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $unknown 'Engine') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $unity 'Unity Game_Data') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $unity 'UnityPlayer.dll'), '', [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $sm5 'Manifest_UFSFiles_Win64.txt'), "Engine/GlobalShaderCache-PCD3D_SM5.bin`t123`n", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $sm6 'Manifest_UFSFiles_Win64.txt'), "Game/Content/ShaderArchive-Game-PCD3D_SM6.ushaderbytecode`t123`n", [Text.UTF8Encoding]::new($false))

& $scanner -GameDirectory @($sm5, $sm6, $unknown, $unity) -OutputPath $reportPath | Out-Null
$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json

if ($report.scannedGameCount -ne 4) { throw "Expected four fixtures, got $($report.scannedGameCount)." }
if ($report.eligibleAdditionalGameCount -ne 1) { throw 'Expected exactly one additional SM5 candidate.' }

$byName = @{}
foreach ($game in $report.games) { $byName[$game.name] = $game }
if ($byName['Stock UE4 SM5'].classification -ne 'eligible-dx11-sm5-candidate') { throw 'SM5 fixture was not eligible.' }
if ($byName['Stock UE SM6'].classification -ne 'excluded-sm6-only') { throw 'SM6-only fixture was not excluded.' }
if ($byName['Unreal Unknown Model'].classification -ne 'manual-shader-model-evidence-required') { throw 'Unknown-model Unreal fixture did not fail closed.' }
if ($byName['Unity Game'].classification -ne 'excluded-no-unreal-evidence') { throw 'Unity fixture was misclassified as Unreal.' }

Write-Output 'UE4 validation candidate discovery test passed.'
Write-Output "Report: $reportPath"
