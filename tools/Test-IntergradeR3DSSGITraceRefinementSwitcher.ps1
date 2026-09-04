[CmdletBinding()]
param(
    [string]$FixtureRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\tests\agent2-r3d-ssgi-trace-refinement-switcher')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$fixture = [IO.Path]::GetFullPath($FixtureRoot).TrimEnd('\')
if (-not $fixture.StartsWith($workspace + '\artifacts\tests\',[StringComparison]::OrdinalIgnoreCase)) {
    throw "Fixture must remain under the workspace artifacts/tests directory: $fixture"
}
$parentMods = Join-Path $workspace 'artifacts\agent2-r3d-ssgi-f2-isolation-matrix\03-trace-only\Mods'
$matrix = Join-Path $workspace 'artifacts\agent2-r3d-ssgi-trace-refinement-matrix'
$switcher = Join-Path $workspace 'tools\Set-IntergradeR3DSSGITraceRefinementVariant.ps1'
foreach ($path in @($parentMods,$matrix,$switcher)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Fixture dependency is missing: $path" }
}

if (Test-Path -LiteralPath $fixture -PathType Container) { [IO.Directory]::Delete($fixture,$true) }
$mods = Join-Path $fixture 'Mods'
$backups = Join-Path $fixture 'backups'
[IO.Directory]::CreateDirectory($mods) | Out-Null
[IO.Directory]::CreateDirectory($backups) | Out-Null
foreach ($file in Get-ChildItem -LiteralPath $parentMods -File) {
    [IO.File]::Copy($file.FullName,(Join-Path $mods $file.Name),$false)
}

$initialIni = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $mods 'Agent2R3DSSGITest.ini')).Hash
$ackRefused = $false
try {
    & $switcher -Variant '00-descriptor-only' -TargetModsDirectory $mods -BackupRoot $backups -Confirm:$false | Out-Null
} catch {
    $ackRefused = $_.Exception.Message -match 'forbidden until 03-trace-only'
}
if (-not $ackRefused) { throw 'Switcher did not refuse deployment without parent-failure acknowledgement.' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $mods 'Agent2R3DSSGITest.ini')).Hash -ne $initialIni -or
    (Test-Path -LiteralPath (Join-Path $mods 'Agent2R3DSSGITraceZero_ps.hlsl'))) {
    throw 'Acknowledgement refusal modified the fixture.'
}

$r0 = & $switcher -Variant '00-descriptor-only' -TargetModsDirectory $mods -BackupRoot $backups -ParentTraceFailureConfirmed -Confirm:$false
$r3 = & $switcher -Variant '03-zero-output-draw' -TargetModsDirectory $mods -BackupRoot $backups -ParentTraceFailureConfirmed -Confirm:$false
$r4 = & $switcher -Variant '04-real-trace-draw' -TargetModsDirectory $mods -BackupRoot $backups -ParentTraceFailureConfirmed -Confirm:$false
foreach ($result in @($r0,$r3,$r4)) {
    if ($result.Status -ne 'staged' -or -not $result.ReloadRequired) { throw "Fixture transition failed: $($result | Out-String)" }
}

$manifest = Get-Content -Raw -LiteralPath (Join-Path $matrix 'manifest.json') | ConvertFrom-Json
$finalEntry = @($manifest.Variants | Where-Object Name -eq '04-real-trace-draw')[0]
foreach ($file in @($finalEntry.Files)) {
    $path = Join-Path $mods ([string]$file.Name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$file.Sha256) {
        throw "Final fixture payload mismatch: $($file.Name)"
    }
}

$zeroPath = Join-Path $mods 'Agent2R3DSSGITraceZero_ps.hlsl'
[IO.File]::AppendAllText($zeroPath,"// deliberate fixture drift`r`n",[Text.UTF8Encoding]::new($false))
$driftRefused = $false
try {
    & $switcher -Variant '01-custom-bind-only' -TargetModsDirectory $mods -BackupRoot $backups -ParentTraceFailureConfirmed -Confirm:$false | Out-Null
} catch {
    $driftRefused = $_.Exception.Message -match 'zero shader is unknown or drifted'
}
if (-not $driftRefused) { throw 'Switcher did not refuse a drifted existing zero shader.' }

$receipts = @(Get-ChildItem -LiteralPath $backups -Recurse -Filter 'receipt.json' -File)
if ($receipts.Count -ne 3) { throw "Expected three successful-transition receipts, found $($receipts.Count)." }

[pscustomobject]@{
    Result='pass'
    MissingAcknowledgementRefused=$ackRefused
    SuccessfulTransitions=3
    DriftedZeroShaderRefused=$driftRefused
    Receipts=$receipts.Count
    FixtureOnly=$true
    RealGameFilesModified=$false
}
