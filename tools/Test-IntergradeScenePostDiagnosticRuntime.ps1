[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output = Join-Path $repoRoot 'artifacts\generated-runtime\FF7RemakeIntergradeScenePostDiagnosticTest'
$result = & (Join-Path $repoRoot 'tools\New-IntergradeScenePostDiagnosticRuntime.ps1') -OutputDirectory $output
if ($result.Status -ne 'neutral-live-parity-pending' -or [int]$result.Files -ne 2) { throw 'Diagnostic runtime did not fail closed with exactly two overlay files.' }
$manifest = Get-Content -Raw -LiteralPath $result.Manifest | ConvertFrom-Json
if ($manifest.diagnosticOnly -ne $true -or $manifest.failClosed -ne $true -or $manifest.licensedRegexDependency -ne $false) {
    throw 'Diagnostic runtime manifest has an unsafe contract.'
}
if (@($manifest.files).Count -ne 2 -or @($manifest.controls).Count -ne 2) { throw 'Diagnostic runtime manifest counts are invalid.' }
foreach ($file in @($manifest.files)) {
    $path = Join-Path $output ([string]$file.relativePath -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Diagnostic payload file is missing: $path" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$file.sha256) { throw "Diagnostic payload hash mismatch: $path" }
}
$ini = Get-Content -Raw -LiteralPath (Join-Path $output 'Mods\UE4EffectsGenerated.ini')
foreach ($required in @('key = no_modifiers VK_INSERT','key = no_modifiers VK_PAGEDOWN','x101 = 1.0, 0.75, 0.5, 0.25, 0.0','w101 = 0.0, 1.0','ps = RebirthPostSceneControls_ps.hlsl')) {
    if (-not $ini.Contains($required)) { throw "Diagnostic INI omitted: $required" }
}
if (([regex]::Matches($ini, '(?m)^hash = af6cd28a0108a18a\r?$')).Count -ne 1) { throw 'Diagnostic INI does not contain exactly one scene-post override.' }
if ($ini -match 'SceneSaturationL[0-3]|\$ue4fx_ff7remakeintergrade_scene_saturation') { throw 'Diagnostic INI retained static scene-saturation override state.' }
if ($ini -match '(?i)shift') { throw 'Diagnostic INI introduced a Shift-modified key.' }
if ($ini -match 'e2aa1c8cb39e0a55') { throw 'Blocked SSR composite leaked into the scene-post diagnostic.' }

Write-Output 'Intergrade scene-post diagnostic runtime tests passed.'
Write-Output "Manifest: $($result.Manifest)"
