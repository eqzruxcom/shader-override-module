[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\generated-adapter-test')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$generator = Join-Path $repoRoot 'tools\New-UE4GeneratedAdapter.ps1'
$bindingSource = Join-Path $repoRoot 'src\Adapters\FF7RemakeIntergrade\adapter-bindings.json'
$reportSource = Join-Path $repoRoot 'artifacts\ue4-semantic-all-captured.json'

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$positiveOutput = Join-Path $OutputDirectory 'positive'
$positive = & $generator -BindingPath $bindingSource -SemanticReport $reportSource -OutputDirectory $positiveOutput
if ($positive.Passes -ne 3 -or $positive.BlockedPasses -ne 1 -or -not (Test-Path -LiteralPath $positive.Output -PathType Leaf)) {
    throw 'Positive generated-adapter case failed.'
}
$positiveAdapter = Get-Content -Raw -LiteralPath $positive.Output | ConvertFrom-Json
if ($positiveAdapter.configuredPasses -ne 4 -or @($positiveAdapter.passes).Count -ne 3 -or @($positiveAdapter.blockedPasses).Count -ne 1) {
    throw 'Generated adapter pass accounting is invalid.'
}
if (@($positiveAdapter.passes.descriptorId) -notcontains 'ue4-temporal-ssao-horizon-ps-sm5') {
    throw 'Live-eligible AO pass was not emitted.'
}
$temporalPass = @($positiveAdapter.passes | Where-Object integration -eq 'temporal-volume-post')
if ($temporalPass.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$temporalPass[0].evidence.temporalBlendContract) -or [string]$temporalPass[0].evidence.temporalBlendContractSha256 -notmatch '^[0-9A-F]{64}$') {
    throw 'Generated temporal pass is missing auditable blend-contract evidence.'
}
$blockedSsr = @($positiveAdapter.blockedPasses | Where-Object descriptorId -eq 'ue4-reflection-environment-ssr-composite-ps-sm5')
if ($blockedSsr.Count -ne 1 -or $blockedSsr[0].reason -ne 'control-pack-runtime-adapter-ineligible') {
    throw 'Live-ineligible SSR pass was not reported as blocked.'
}

function Assert-Rejected {
    param(
        [string]$Name,
        [scriptblock]$MutateBinding,
        [scriptblock]$MutateReport,
        [string]$ExpectedMessage
    )
    $caseRoot = Join-Path $OutputDirectory ("negative-$Name")
    New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
    $binding = Get-Content -Raw -LiteralPath $bindingSource | ConvertFrom-Json
    $report = Get-Content -Raw -LiteralPath $reportSource | ConvertFrom-Json
    if ($MutateBinding) { & $MutateBinding $binding }
    if ($MutateReport) { & $MutateReport $report }
    $bindingPath = Join-Path $caseRoot 'bindings.json'
    $reportPath = Join-Path $caseRoot 'report.json'
    $binding | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $bindingPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding UTF8

    $caught = $null
    try {
        & $generator -BindingPath $bindingPath -SemanticReport $reportPath -OutputDirectory (Join-Path $caseRoot 'output') | Out-Null
    }
    catch { $caught = $_.Exception.Message }
    if (-not $caught) { throw "Negative generated-adapter case '$Name' was unexpectedly accepted." }
    if ($caught -notmatch $ExpectedMessage) { throw "Negative case '$Name' failed for the wrong reason: $caught" }
}

Assert-Rejected 'stale-descriptor' $null {
    param($report)
    @($report.descriptors | Where-Object id -eq 'ue4-volumetric-scattering-history-sm5')[0].sha256 = '0000000000000000000000000000000000000000000000000000000000000000'
} 'report is stale'

Assert-Rejected 'temporal-weight-mismatch' {
    param($binding)
    $binding.passes[0].bindings.temporalCurrentWeight = 0.2
    $binding.passes[0].bindings.temporalHistoryWeight = 0.8
} $null 'descriptor current weight mismatch'

Assert-Rejected 'licensed-report' $null {
    param($report)
    $report.licensedRegexDependency = $true
} 'licensed regex input'

Assert-Rejected 'duplicate-pass' {
    param($binding)
    $binding.passes = @($binding.passes[0], $binding.passes[0])
} $null 'Duplicate adapter descriptor'

Assert-Rejected 'scene-output-mismatch' {
    param($binding)
    $binding.passes[1].bindings.output = 'ps-o1'
} $null 'Shader-map output binding mismatch'

$prematureRoot = Join-Path $OutputDirectory 'negative-premature-runtime-eligibility'
New-Item -ItemType Directory -Path $prematureRoot -Force | Out-Null
$prematurePack = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'artifacts\replacement-shaders\e2aa1c8cb39e0a55-ssr-composite-strength-control-pack.json') | ConvertFrom-Json
$prematurePack.runtimeAdapterEligible = $true
$prematurePackPath = Join-Path $prematureRoot 'ssr-pack.json'
$prematurePack | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $prematurePackPath -Encoding UTF8
$prematureBinding = Get-Content -Raw -LiteralPath $bindingSource | ConvertFrom-Json
$prematureBinding.passes[3].controlPack = [IO.Path]::GetRelativePath($repoRoot, $prematurePackPath).Replace('\','/')
$prematureBindingPath = Join-Path $prematureRoot 'bindings.json'
$prematureBinding | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $prematureBindingPath -Encoding UTF8
$prematureError = $null
try {
    & $generator -BindingPath $prematureBindingPath -SemanticReport $reportSource -OutputDirectory (Join-Path $prematureRoot 'output') | Out-Null
}
catch { $prematureError = $_.Exception.Message }
if (-not $prematureError -or $prematureError -notmatch 'lacks live-verified status') {
    throw "Premature SSR runtime eligibility was not rejected correctly: $prematureError"
}
Assert-Rejected 'ssr-composite-input-mismatch' {
    param($binding)
    $binding.passes[3].bindings.ssrInput = 'ps-t10'
} $null 'SSR composite binding contract mismatch'

$isolationRoot = Join-Path $OutputDirectory 'negative-ssr-composite-isolation-mismatch'
New-Item -ItemType Directory -Path $isolationRoot -Force | Out-Null
$isolationEvidence = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'artifacts\ssr-composite-strength-variant-isolation.json') | ConvertFrom-Json
$isolationEvidence.uniqueNormalizedBodies = 2
$isolationEvidencePath = Join-Path $isolationRoot 'variant-isolation.json'
$isolationEvidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $isolationEvidencePath -Encoding UTF8
$isolationPack = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'artifacts\replacement-shaders\e2aa1c8cb39e0a55-ssr-composite-strength-control-pack.json') | ConvertFrom-Json
$isolationPack.variantIsolationReport = [IO.Path]::GetRelativePath($repoRoot, $isolationEvidencePath).Replace('\','/')
$isolationPackPath = Join-Path $isolationRoot 'ssr-pack.json'
$isolationPack | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $isolationPackPath -Encoding UTF8
$isolationMap = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\Adapters\FF7RemakeIntergrade\shader-map.json') | ConvertFrom-Json
$isolationMapPass = @($isolationMap.passes | Where-Object id -eq 'reflection_environment')
$isolationMapPass[0].discoveryHints.strengthControlPack = [IO.Path]::GetRelativePath($repoRoot, $isolationPackPath).Replace('\','/')
$isolationMapPath = Join-Path $isolationRoot 'shader-map.json'
$isolationMap | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $isolationMapPath -Encoding UTF8
$isolationBinding = Get-Content -Raw -LiteralPath $bindingSource | ConvertFrom-Json
$isolationBinding.passes[3].controlPack = [IO.Path]::GetRelativePath($repoRoot, $isolationPackPath).Replace('\','/')
$isolationBinding.passes[3].evidence.shaderMap = [IO.Path]::GetRelativePath($repoRoot, $isolationMapPath).Replace('\','/')
$isolationBindingPath = Join-Path $isolationRoot 'bindings.json'
$isolationBinding | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $isolationBindingPath -Encoding UTF8
$isolationError = $null
try {
    & $generator -BindingPath $isolationBindingPath -SemanticReport $reportSource -OutputDirectory (Join-Path $isolationRoot 'output') | Out-Null
}
catch { $isolationError = $_.Exception.Message }
if (-not $isolationError -or $isolationError -notmatch 'variant-isolation evidence mismatch') {
    throw "Tampered SSR variant-isolation evidence was not rejected correctly: $isolationError"
}

$dynamicRoot = Join-Path $OutputDirectory 'negative-dynamic-temporal-contract'
New-Item -ItemType Directory -Path $dynamicRoot -Force | Out-Null
$dynamicContract = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'artifacts\temporal-blend-contracts\ef7fe8d9c4e9ad15.json') | ConvertFrom-Json
$dynamicContract.temporalBlend.status = 'dynamic'
$dynamicContract.temporalBlend.historyWeight = $null
$dynamicContract.temporalBlend.currentWeight = $null
$dynamicContract.temporalBlend.steadyStateCompensationEligible = $false
$dynamicContractPath = Join-Path $dynamicRoot 'temporal-contract.json'
$dynamicContract | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $dynamicContractPath -Encoding UTF8
$dynamicBinding = Get-Content -Raw -LiteralPath $bindingSource | ConvertFrom-Json
$dynamicBinding.passes[0].evidence.temporalBlendContract = [IO.Path]::GetRelativePath($repoRoot, $dynamicContractPath).Replace('\','/')
$dynamicBindingPath = Join-Path $dynamicRoot 'bindings.json'
$dynamicBinding | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $dynamicBindingPath -Encoding UTF8
$dynamicError = $null
try {
    & $generator -BindingPath $dynamicBindingPath -SemanticReport $reportSource -OutputDirectory (Join-Path $dynamicRoot 'output') | Out-Null
}
catch { $dynamicError = $_.Exception.Message }
if (-not $dynamicError -or $dynamicError -notmatch 'not fixed and compensation-eligible') {
    throw "Dynamic temporal contract was not rejected correctly: $dynamicError"
}

$summary = [ordered]@{
    schemaVersion = 1
    positive = 'pass'
    negativeCases = @('stale-descriptor','temporal-weight-mismatch','licensed-report','duplicate-pass','scene-output-mismatch','premature-runtime-eligibility','ssr-composite-input-mismatch','ssr-composite-isolation-mismatch','dynamic-temporal-contract')
    result = 'pass'
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$summaryPath = Join-Path $OutputDirectory 'report.json'
[IO.File]::WriteAllText($summaryPath,(($summary | ConvertTo-Json -Depth 6)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))

Write-Output 'UE4 generated-adapter tests passed.'
Write-Output "Report: $summaryPath"
