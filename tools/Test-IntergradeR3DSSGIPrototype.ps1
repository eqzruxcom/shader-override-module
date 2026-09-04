[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$builder = Join-Path $PSScriptRoot 'New-IntergradeR3DSSGIPrototype.ps1'
$testRoot = Join-Path $projectRoot ('artifacts\r3d-ssgi-sm5-prototype-test\' + [guid]::NewGuid().ToString('N'))
$first = Join-Path $testRoot 'first'
$second = Join-Path $testRoot 'second'

$null = & $builder -OutputDirectory $first
$null = & $builder -OutputDirectory $second

$firstManifest = Get-Content -Raw -LiteralPath (Join-Path $first 'manifest.json') | ConvertFrom-Json
$secondManifest = Get-Content -Raw -LiteralPath (Join-Path $second 'manifest.json') | ConvertFrom-Json

if ($firstManifest.result -ne 'pass' -or $secondManifest.result -ne 'pass') {
    throw 'One or more SSGI prototype builds did not pass.'
}
if ($firstManifest.shader.objectSha256 -ne $secondManifest.shader.objectSha256) {
    throw 'SSGI prototype DXBC output is not deterministic.'
}
if ($firstManifest.shader.sourceSha256 -ne $secondManifest.shader.sourceSha256) {
    throw 'SSGI prototype source changed between deterministic builds.'
}
if ($firstManifest.policy.runtimeEligible -ne $false -or
    $firstManifest.policy.installed -ne $false -or
    $firstManifest.policy.gameFilesTouched -ne $false -or
    $firstManifest.policy.keyBindingsEmitted -ne $false) {
    throw 'Offline SSGI prototype policy is unsafe.'
}

$assembly = Get-Content -Raw -LiteralPath (Join-Path $first 'R3DSSGI_SM5_ps.asm')
foreach ($slot in @('t0', 't1', 't2', 's0', 'cb0')) {
    if ($assembly -notmatch [regex]::Escape($slot)) {
        throw "Compiled SSGI prototype does not expose expected assembly slot $slot."
    }
}
if ($assembly -match 'dcl_uav') {
    throw 'Pixel-shader SSGI prototype unexpectedly declares a UAV.'
}

[pscustomobject]@{
    result = 'pass'
    deterministicObjectSha256 = $firstManifest.shader.objectSha256
    profile = $firstManifest.shader.profile
    inputs = @('t0 scene radiance', 't1 view normal', 't2 scene depth')
    output = 'SV_Target0'
    runtimeEligible = $false
}
