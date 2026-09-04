[CmdletBinding()]
param(
    [string]$ControlPackPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\replacement-shaders\e2aa1c8cb39e0a55-ssr-composite-strength-control-pack.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')

function Resolve-WorkspaceFile([string]$Path) {
    $full = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    } else {
        [IO.Path]::GetFullPath((Join-Path $repoRoot ($Path -replace '/', '\')))
    }
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes the workspace: $full"
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Required file is missing: $full" }
    $full
}

$packPath = Resolve-WorkspaceFile $ControlPackPath
$pack = Get-Content -Raw -LiteralPath $packPath | ConvertFrom-Json
if ($pack.semanticDescriptor -ne 'ue4-reflection-environment-ssr-composite-ps-sm5') { throw 'Unexpected semantic descriptor.' }
if ($pack.shaderHash -ne 'e2aa1c8cb39e0a55' -or $pack.stage -ne 'ps') { throw 'Unexpected downstream composite identity.' }
if ($pack.runtimeAdapterEligible -ne $false) { throw 'Unvalidated downstream composite must remain runtime-ineligible.' }
if ($pack.status -ne 'live-diagnostic-amplified-response-verified-normal-range-current-scene-inconclusive') { throw 'Control pack does not record the amplified live response and inconclusive normal-range result.' }
if ($pack.liveGate -notmatch '^Blocked for runtime promotion in this scene:' -or $pack.liveGate -notmatch '0%-to-1600%' -or $pack.liveGate -notmatch 'before validating 50%') { throw 'Control pack live gate must preserve the amplified proof and the pending normal-range gate.' }
foreach ($evidence in @($pack.liveValidation.radiancePresence, $pack.liveValidation.neutral100Percent, $pack.liveValidation.zeroEndpoint, $pack.liveValidation.amplifiedDiagnostic1600Percent)) {
    Resolve-WorkspaceFile ([string]$evidence) | Out-Null
}
$isolationPath = Resolve-WorkspaceFile ([string]$pack.variantIsolationReport)
$isolation = Get-Content -Raw -LiteralPath $isolationPath | ConvertFrom-Json
if ($isolation.result -ne 'pass' -or $isolation.uniqueNormalizedBodies -ne 1 -or @($isolation.levels).Count -ne 5) { throw 'Variant-isolation evidence is incomplete.' }

$levels = @($pack.levels)
if ($levels.Count -ne 5) { throw "Expected five levels, found $($levels.Count)." }
$expected = @(0.0, 0.25, 0.5, 0.75, 1.0)
for ($i = 0; $i -lt $expected.Count; $i++) {
    $level = $levels[$i]
    if ([Math]::Abs([double]$level.strength - $expected[$i]) -gt 0.000001) {
        throw "Unexpected strength at index $($i): $($level.strength)."
    }
    foreach ($kind in @('source', 'object')) {
        $path = Resolve-WorkspaceFile ([string]$level.$kind)
        $hashProperty = $kind + 'Sha256'
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
        if ($actual -ne [string]$level.$hashProperty) { throw "$kind hash mismatch at strength $($level.strength)." }
    }
}
if ($levels[0].verification -ne 'live-no-observable-difference-current-scene' -or [string]::IsNullOrWhiteSpace([string]$levels[0].liveEvidence)) {
    throw 'The 0% endpoint must record its inconclusive live comparison evidence.'
}
if (@($levels.objectSha256 | Select-Object -Unique).Count -ne 5) { throw 'Expected five unique compiled objects.' }

$neutralObject = Resolve-WorkspaceFile 'artifacts/captured-shaders/e2aa1c8cb39e0a55-ps/e2aa1c8cb39e0a55-ps_recompiled.cso'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $neutralObject).Hash -ne $levels[4].objectSha256) {
    throw 'The 100% candidate does not match the independently strict-recompiled neutral object.'
}

$descriptorPath = Resolve-WorkspaceFile 'src/Engine/UE4/PassDescriptors/reflection-environment-ssr-composite-ps-sm5.json'
$semanticReportPath = Resolve-WorkspaceFile ([string]$pack.semanticSpecificityReport)
$semanticReport = Get-Content -Raw -LiteralPath $semanticReportPath | ConvertFrom-Json
$descriptorRecord = @($semanticReport.descriptors | Where-Object id -eq $pack.semanticDescriptor)
if ($descriptorRecord.Count -ne 1) { throw 'Semantic report does not contain exactly one descriptor record.' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $descriptorPath).Hash -ne $descriptorRecord[0].sha256) {
    throw 'Semantic specificity report is stale.'
}
$match = @($semanticReport.matches | Where-Object {
    $_.descriptor -eq $pack.semanticDescriptor -and $_.hash -eq $pack.shaderHash -and $_.stage -eq $pack.stage
})
if ($semanticReport.shaders.scanned -ne 184 -or $match.Count -ne 1 -or @($semanticReport.matches).Count -ne 1) {
    throw 'Semantic specificity report no longer proves a unique one-of-184 match.'
}
if ($match[0].semanticChecksPassed -ne 11 -or @($semanticReport.matchTimeouts).Count) {
    throw 'Semantic specificity evidence is incomplete or timed out.'
}

Write-Output 'Intergrade downstream SSR composite strength control-pack validation passed.'
[pscustomobject]@{
    ControlPackSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $packPath).Hash
    Levels = $levels.Count
    SemanticMatches = @($semanticReport.matches).Count
    RuntimeAdapterEligible = $pack.runtimeAdapterEligible
    Result = 'pass'
}
