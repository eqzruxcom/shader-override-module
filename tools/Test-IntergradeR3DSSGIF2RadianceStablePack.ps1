[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$generator = Join-Path $PSScriptRoot 'New-IntergradeR3DSSGIF2RadianceStablePack.ps1'
$a = Join-Path $root 'artifacts\agent2-r3d-ssgi-f2-radiance-stable-pack-test-a'
$b = Join-Path $root 'artifacts\agent2-r3d-ssgi-f2-radiance-stable-pack-test-b'

& $generator -OutputDirectory $a | Out-Host
& $generator -OutputDirectory $b | Out-Host

$manifestA = Get-Content -Raw -LiteralPath (Join-Path $a 'manifest.json') | ConvertFrom-Json
$manifestB = Get-Content -Raw -LiteralPath (Join-Path $b 'manifest.json') | ConvertFrom-Json
if ($manifestA.variant -ne 'material-aware-bounded-hdr-radiance-v1' -or $manifestA.result -ne 'pass') { throw 'Unexpected stable-pack classification' }
if ($manifestA.effect.sourceRadianceCap -ne 4.0 -or $manifestA.effect.reconstructedIrradianceCap -ne 1.0) { throw 'Radiance cap contract changed' }
if (@($manifestA.files).Count -ne 7 -or @($manifestA.compile).Count -ne 6) { throw 'Payload or compile inventory changed' }
if ($manifestA.policy.gameFilesTouched -or $manifestA.policy.runtimeEligible -or $manifestA.policy.installed) { throw 'Offline safety policy changed' }

$filesA = @($manifestA.files | ForEach-Object { "$($_.path):$($_.sha256)" })
$filesB = @($manifestB.files | ForEach-Object { "$($_.path):$($_.sha256)" })
if (@(Compare-Object $filesA $filesB).Count -ne 0) { throw 'Stable pack payload is not deterministic' }

$trace = Get-Content -Raw -LiteralPath (Join-Path $a 'Mods\Agent2R3DSSGITraceE2AA_ps.hlsl')
$composite = Get-Content -Raw -LiteralPath (Join-Path $a 'Mods\Agent2R3DSSGICompositeE2AA_ps.hlsl')
foreach ($pattern in @('AGENT2_SOURCE_RADIANCE_CAP = 4\.0','sourcePeak','min\(1\.0, AGENT2_SOURCE_RADIANCE_CAP')) {
    if ($trace -notmatch $pattern) { throw "Trace stability pattern is missing: $pattern" }
}
foreach ($pattern in @('AGENT2_INDIRECT_IRRADIANCE_CAP = 1\.0','float3 irradiance','min\(1\.0, AGENT2_INDIRECT_IRRADIANCE_CAP')) {
    if ($composite -notmatch $pattern) { throw "Composite stability pattern is missing: $pattern" }
}

Remove-Item -LiteralPath $a, $b -Recurse -Force
Write-Host 'PASS: bounded-HDR SSGI pack is deterministic, compiled, and leaves live files untouched.'
