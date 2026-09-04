[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$workspacePath = (Resolve-Path -LiteralPath $Path).Path
$reviewRoot = [IO.Path]::GetFullPath((Join-Path $projectPath 'artifacts\adapter-reviews')).TrimEnd('\')
if (-not $workspacePath.StartsWith($reviewRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Adapter review workspace must remain below artifacts/adapter-reviews.'
}
$reviewSchema = Join-Path $projectPath 'src\Engine\UE4\AdapterReviews\schema.json'
$candidateSchema = Join-Path $projectPath 'src\Engine\UE4\AdapterCandidates\schema.json'
$json = Get-Content -Raw -LiteralPath $workspacePath
if (-not ($json | Test-Json -SchemaFile $reviewSchema -ErrorAction Stop)) { throw 'Adapter review workspace failed its schema.' }
$workspace = $json | ConvertFrom-Json

$candidatePath = (Resolve-Path -LiteralPath ([string]$workspace.sourceCandidateReport.path)).Path
$candidateRoot = [IO.Path]::GetFullPath((Join-Path $projectPath 'artifacts\generated-adapter-candidates')).TrimEnd('\')
if (-not $candidatePath.StartsWith($candidateRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Review source candidate report escaped artifacts/generated-adapter-candidates.'
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $candidatePath).Hash -ne [string]$workspace.sourceCandidateReport.sha256) {
    throw 'Review source candidate report hash changed.'
}
$candidateJson = Get-Content -Raw -LiteralPath $candidatePath
if (-not ($candidateJson | Test-Json -SchemaFile $candidateSchema -ErrorAction Stop)) { throw 'Review source candidate report failed its schema.' }
$report = $candidateJson | ConvertFrom-Json
if ([string]$workspace.captureId -ne [string]$report.captureId -or [string]$workspace.reviewWorkspaceId -ne [string]$report.captureId) {
    throw 'Review workspace capture identity does not match its candidate report.'
}
if ([int]$workspace.sourceCandidateReport.candidateCount -ne [int]$report.candidateCount -or [int]$workspace.candidateReviewCount -ne @($workspace.candidates).Count) {
    throw 'Review workspace candidate count is inconsistent.'
}
if ([int]$workspace.candidateReviewCount -ne [int]$report.candidateCount) {
    throw 'Review workspace candidate count does not match its source report.'
}
$exePath = (Resolve-Path -LiteralPath ([string]$workspace.gameExecutable.path)).Path
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $exePath).Hash -ne [string]$workspace.gameExecutable.sha256) {
    throw 'Review workspace executable fingerprint changed.'
}
if ([string]$workspace.gameExecutable.sha256 -ne [string]$report.gameExecutable.sha256) {
    throw 'Review workspace executable does not match its source report.'
}

$required = @('binding-contract','replacement-shader','control-pack','live-visual-validation','runtime-eligibility-review')
$declared = @($workspace.requiredGates | ForEach-Object { [string]$_ })
if ($declared.Count -ne $required.Count -or @($required | Where-Object { $declared -notcontains $_ }).Count) {
    throw 'Review workspace does not declare the exact required gate set.'
}
$sourceById = @{}
foreach ($candidate in @($report.candidates)) {
    $id = [string]$candidate.candidateId
    if ($sourceById.ContainsKey($id)) { throw "Duplicate source candidate identity: $id" }
    $sourceById[$id] = $candidate
}
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($review in @($workspace.candidates)) {
    $id = [string]$review.candidateId
    if (-not $seen.Add($id)) { throw "Duplicate review candidate identity: $id" }
    if (-not $sourceById.ContainsKey($id)) { throw "Review candidate is absent from the source report: $id" }
    $source = $sourceById[$id]
    foreach ($field in @('descriptorId','family','shaderHash','stage','shaderModel')) {
        if ([string]$review.$field -ne [string]$source.$field) { throw "Review candidate field changed ($field): $id" }
    }
    $gateIds = @($review.gates | ForEach-Object { [string]$_.id })
    if ($gateIds.Count -ne $required.Count -or @($required | Where-Object { $gateIds -notcontains $_ }).Count) {
        throw "Review candidate does not contain the exact gate set: $id"
    }
    if (@($gateIds | Group-Object | Where-Object Count -ne 1).Count) { throw "Review candidate contains duplicate gates: $id" }
    foreach ($gate in @($review.gates)) {
        if ([string]$gate.status -ne 'pending' -or $null -ne $gate.evidence -or $null -ne $gate.evidenceSha256 -or $null -ne $gate.reviewedBy -or $null -ne $gate.reviewedAtUtc -or $null -ne $gate.notes) {
            throw "Initial review gate contains unverified state: $id/$($gate.id)"
        }
    }
}
if ($seen.Count -ne $sourceById.Count) { throw 'Review workspace omitted one or more source candidates.' }

$workspace
