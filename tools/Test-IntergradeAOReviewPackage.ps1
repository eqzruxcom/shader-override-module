[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-reviewed-integration-test'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$generator = Join-Path $repoRoot 'tools\New-IntergradeAOReviewPackage.ps1'
$first = Join-Path $OutputDirectory 'package'
& $generator -OutputDirectory $first
$firstManifest = Join-Path $first 'review-manifest.json'
$firstHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $firstManifest).Hash
& $generator -OutputDirectory $first
$secondHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $firstManifest).Hash
if ($firstHash -ne $secondHash) { throw 'AO review manifest is not deterministic.' }
$manifest = Get-Content -Raw -LiteralPath $firstManifest | ConvertFrom-Json
if ($manifest.bindingsEmitted -ne $false -or $manifest.iniFilesEmitted -ne $false -or $manifest.installerEmitted -ne $false -or $manifest.liveGameTouched -ne $false -or $manifest.dxvkTouched -ne $false) { throw 'AO review package escaped the offline boundary.' }
if ($manifest.controls.F1 -ne 'Original/native AO' -or $manifest.controls.F2 -ne 'Balanced' -or $manifest.controls.F3 -ne 'Strong') { throw 'AO control mapping changed.' }
if ($manifest.candidates.Count -ne 2 -or @($manifest.candidates.objectSha256 | Sort-Object -Unique).Count -ne 2) { throw 'AO review package candidate inventory changed.' }
$unexpectedIni = @(Get-ChildItem -LiteralPath $first -Recurse -File -Filter '*.ini')
if ($unexpectedIni.Count -ne 0) { throw 'AO review package emitted an INI.' }
if (-not (Test-Path -LiteralPath (Join-Path $first 'live-test-plan.md') -PathType Leaf)) { throw 'AO live-test plan is missing.' }
Write-Host 'PASS: AO review package is deterministic, offline-only, and binding-free.'
