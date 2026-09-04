[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$matcher = Join-Path $repoRoot 'tools\Match-UE4SemanticPasses.ps1'
$fixtures = Join-Path $repoRoot 'src\Tests\Fixtures\UE4Semantic'
$reportPath = Join-Path $repoRoot 'artifacts\ue4-semantic-near-match-test\report.json'

& $matcher -ShaderDirectory $fixtures -OutputPath $reportPath -NearMatchLimitPerDescriptor 2 | Out-Null
$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
$near = @($report.nearMatches)

if ($report.nearMatchLimitPerDescriptor -ne 2) { throw 'Near-match limit was not recorded.' }
if (@($report.matches).Count -ne 8) { throw 'Near-match mode changed the eight full fixture matches.' }
if (-not $near.Count) { throw 'Expected metadata-only near-match candidates.' }
foreach ($group in @($near | Group-Object descriptor)) {
    if ($group.Count -gt 2) { throw "Descriptor $($group.Name) exceeded its near-match limit." }
}
foreach ($candidate in $near) {
    if ($candidate.coverage -le 0 -or $candidate.coverage -ge 1) {
        throw "Near-match coverage must be strictly between zero and one: $($candidate.coverage)"
    }
    if ($candidate.satisfiedChecks -ge $candidate.totalChecks) {
        throw 'A full semantic match leaked into near-match output.'
    }
    if (@($candidate.evidence).Count -ne $candidate.totalChecks) {
        throw 'Near-match evidence does not cover every descriptor check.'
    }
    if (@($candidate.evidence | Where-Object { $_.PSObject.Properties.Name -contains 'pattern' }).Count) {
        throw 'Near-match evidence exposed regex pattern text.'
    }
    if (-not @($candidate.evidence | Where-Object { -not $_.satisfied }).Count) {
        throw 'Near-match candidate has no failed semantic check.'
    }
}
if (@($report.matchTimeouts).Count) { throw 'Near-match test encountered a regex timeout.' }

Write-Output 'UE4 semantic near-match metadata test passed.'
Write-Output "Report: $reportPath"
