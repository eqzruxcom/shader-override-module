[CmdletBinding()]
param(
    [string]$DiagnosticRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\clothing-material1-contact-route-diagnostic-20260901-v1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $DiagnosticRoot 'diagnostic-manifest.json'
$shaderPath = Join-Path $DiagnosticRoot 'payload\ShaderFixes\62b33a2d1e505241-cs.txt'
$iniPath = Join-Path $DiagnosticRoot 'payload\Mods\ContactShadows.ini'
$binaryPath = Join-Path $DiagnosticRoot 'validation\62b-material1-contact-route.shdr'

foreach ($path in @($manifestPath, $shaderPath, $iniPath, $binaryPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing diagnostic file: $path" }
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.installed -ne $false -or $manifest.runtimeEligible -ne $false) {
    throw 'Unverified material-ID diagnostic must remain offline and runtime-ineligible.'
}
$shader = Get-Content -Raw -LiteralPath $shaderPath
foreach ($required in @(
    'ieq r40.x, r6.x, l(1)',
    'and r26.x, r26.x, r40.x',
    'movc r25.x, r26.x, l(1.000000), r25.x'
)) {
    if ($shader -notmatch [regex]::Escape($required)) { throw "Missing narrow route instruction: $required" }
}
if ($shader -match 'movc r25\.x, r26\.x, l\(0(?:\.0+)?\), r25\.x') {
    throw 'Rejected zero-visibility light-kill instruction returned.'
}
$ini = Get-Content -Raw -LiteralPath $iniPath
foreach ($required in @('VK_NEXT', 'VK_PRIOR', 'x28 = $ue4fx_material1_contact_route_v1', 'x31 = $ue4fx_master_injected_v1')) {
    if (-not $ini.Contains($required)) { throw "Missing hotkey/control contract: $required" }
}
if ([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($binaryPath), 0, 4) -ne 'DXBC') {
    throw 'Assembled route diagnostic is not a DXBC container.'
}
foreach ($file in $manifest.files) {
    $path = Join-Path $DiagnosticRoot ([string]$file.path).Replace('/', '\')
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$file.sha256) {
        throw "Manifest fingerprint mismatch: $($file.path)"
    }
}

Write-Host 'PASS: corrected material-ID 1 route test preserves local light, uses Page Down/Page Up policy, assembles to DXBC, and remains offline.'
