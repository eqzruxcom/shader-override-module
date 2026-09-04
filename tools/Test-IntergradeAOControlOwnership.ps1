[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-ao-control-ownership-test'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$runtimeRoot = Join-Path $repoRoot 'runtime\Intergrade\Mods'
$analyzer = Join-Path $repoRoot 'tools\Analyze-IntergradeAOControlOwnership.ps1'
$output = Join-Path $OutputDirectory 'report.json'

function Get-TreeHashes([string]$Root) {
    $result = [ordered]@{}
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName) {
        $result[$file.FullName.Substring($Root.Length + 1)] = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
    }
    $result
}
$before = Get-TreeHashes $runtimeRoot
& $analyzer -OutputPath $output
$after = Get-TreeHashes $runtimeRoot
if (($before.Keys -join "`n") -cne ($after.Keys -join "`n")) { throw 'Runtime inventory changed during ownership audit.' }
foreach ($key in $before.Keys) { if ($before[$key] -ne $after[$key]) { throw "Runtime file changed during ownership audit: $key" } }

$report = Get-Content -Raw -LiteralPath $output | ConvertFrom-Json
if ($report.result -ne 'pass' -or $report.integrationPreview.offlineReady -ne $true -or $report.integrationPreview.installed -ne $false) {
    throw 'Ownership audit did not prove offline integration readiness.'
}
if ($report.assertions.currentRuntimeF1ClaimCount -ne 0 -or $report.assertions.currentRuntimeF2ClaimCount -ne 0) {
    throw 'Reserved F1/F2 are already claimed.'
}
if ($report.assertions.currentRuntimeF3ClaimCount -ne 1 -or $report.assertions.currentRuntimeE2aaOwnerCount -ne 1) {
    throw 'Expected existing F3/e2aa owner topology changed.'
}
if ($report.assertions.conflictingVariantManifestCount -lt 2) { throw 'Stale variant control mappings were not detected.' }
Write-Output 'Intergrade Agent 2 AO control-ownership tests passed.'
Write-Output "Report: $output"
