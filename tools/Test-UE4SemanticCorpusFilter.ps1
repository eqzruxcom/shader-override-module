[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$caseRoot = Join-Path $repoRoot 'artifacts\ue4-semantic-corpus-filter-test'
$shaderRoot = Join-Path $caseRoot 'shaders'
$reportPath = Join-Path $caseRoot 'report.json'
$matcher = Join-Path $repoRoot 'tools\Match-UE4SemanticPasses.ps1'
$fixture = Join-Path $repoRoot 'src\Tests\Fixtures\UE4Semantic\af6cd28a0108a18a-ps.asm'

if (Test-Path -LiteralPath $caseRoot) {
    Remove-Item -LiteralPath $caseRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $shaderRoot -Force | Out-Null
Copy-Item -LiteralPath $fixture -Destination (Join-Path $shaderRoot 'af6cd28a0108a18a-ps.asm')
Copy-Item -LiteralPath $fixture -Destination (Join-Path $shaderRoot 'af6cd28a0108a18a-ps_replace.asm')

& $matcher -ShaderDirectory $shaderRoot -OutputPath $reportPath -ExcludeReplacementArtifacts | Out-Null
$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json

if ($report.shaders.replacementArtifactsExcluded -ne $true) {
    throw 'Report did not record replacement-artifact exclusion.'
}
if ($report.shaders.scanned -ne 1) {
    throw "Expected one captured assembly after filtering, scanned $($report.shaders.scanned)."
}
$matches = @($report.matches)
if ($matches.Count -ne 1) { throw "Expected one semantic match, found $($matches.Count)." }
if (@($matches[0].artifacts).Count -ne 1) { throw 'Replacement artifact leaked into match evidence.' }
if ($matches[0].artifacts[0].file -match '(?i)_replace\.') {
    throw 'Replacement artifact was reported as captured evidence.'
}

Write-Output 'UE4 semantic corpus replacement filter test passed.'
Write-Output "Report: $reportPath"
