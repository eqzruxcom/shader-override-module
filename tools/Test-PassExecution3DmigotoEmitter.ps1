[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\pass-execution-3dmigoto-r3d-ssgi-composite'),
    [string]$ReviewedIni = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-real-pack\Mods\Agent2R3DSSGITest.ini')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$manifestPath = Join-Path $OutputRoot 'manifest.json'
$fragmentPath = Join-Path $OutputRoot 'Mods\GeneratedOwnedPass.ini'
foreach ($path in @($manifestPath,$fragmentPath,$ReviewedIni)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required emitter artifact is missing: $path" }
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.result -ne 'pass' -or
    $manifest.backend -ne '3dmigoto-d3d11' -or $manifest.executionOwnership -ne 'injector-owned' -or
    $manifest.runtimeEligible -ne $false -or $manifest.installed -ne $false -or @($manifest.files).Count -ne 3) {
    throw '3DMigoto emitter manifest contract failed.'
}
foreach ($file in @($manifest.files)) {
    $path = Join-Path (Join-Path $OutputRoot 'Mods') ([string]$file.name)
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$file.sha256) { throw "Emitter output drifted: $($file.name)" }
}

$fragment = (Get-Content -Raw -LiteralPath $fragmentPath).Trim()
$reviewed = Get-Content -Raw -LiteralPath $ReviewedIni
$match = [regex]::Match($reviewed, '(?ms)^\[CustomShaderAgent2R3DSSGIComposite\]\r?\n.*?(?=^; AGENT 2 R3D SSGI F2 TEST END)')
if (-not $match.Success) { throw 'Reviewed owned composite section was not found.' }
$normalizedFragment = $fragment -replace "`r?`n", "`n"
$normalizedReviewed = $match.Value.Trim() -replace "`r?`n", "`n"
if ($normalizedFragment -ne $normalizedReviewed) { throw 'Generated 3DMigoto section is not byte-semantic equivalent to the reviewed owned composite section.' }
if ($fragment -match '(?im)^\s*key\s*=.*F10' -or $fragment -notmatch '(?m)^draw = 3, 0\r?$') {
    throw 'Generated section binds F10 or does not own Draw(3,0).'
}

[pscustomobject]@{
    Result='pass'
    Backend=$manifest.backend
    ExactReviewedSection=$true
    Files=@($manifest.files).Count
    Draw='owned Draw(3,0)'
    F10='unbound'
    RuntimeEligible=$manifest.runtimeEligible
}
