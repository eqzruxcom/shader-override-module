[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CandidateReportPath,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$candidatePath = (Resolve-Path -LiteralPath $CandidateReportPath).Path
$candidateSchema = Join-Path $projectPath 'src\Engine\UE4\AdapterCandidates\schema.json'
$reviewSchema = Join-Path $projectPath 'src\Engine\UE4\AdapterReviews\schema.json'
$candidateAllowedRoot = [IO.Path]::GetFullPath((Join-Path $projectPath 'artifacts\generated-adapter-candidates')).TrimEnd('\')
if (-not $candidatePath.StartsWith($candidateAllowedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Candidate report must remain below artifacts/generated-adapter-candidates.'
}
if (-not (Test-Path -LiteralPath $candidateSchema -PathType Leaf)) { throw 'Adapter-candidate schema is missing.' }
if (-not (Test-Path -LiteralPath $reviewSchema -PathType Leaf)) { throw 'Adapter-review schema is missing.' }

$candidateJson = Get-Content -Raw -LiteralPath $candidatePath
if (-not ($candidateJson | Test-Json -SchemaFile $candidateSchema -ErrorAction Stop)) {
    throw 'Candidate report failed its schema.'
}
$report = $candidateJson | ConvertFrom-Json
if ([int]$report.candidateCount -ne @($report.candidates).Count) {
    throw 'Candidate report count is inconsistent.'
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectPath "artifacts\adapter-reviews\$([string]$report.captureId)\review-workspace.json"
}
$outputFull = [IO.Path]::GetFullPath($OutputPath)
$reviewAllowedRoot = [IO.Path]::GetFullPath((Join-Path $projectPath 'artifacts\adapter-reviews')).TrimEnd('\')
if (-not $outputFull.StartsWith($reviewAllowedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Adapter review output must remain below artifacts/adapter-reviews.'
}

foreach ($sourceName in @('captureManifest','semanticReport','installManifest')) {
    $sourcePath = (Resolve-Path -LiteralPath ([string]$report.source.$sourceName)).Path
    $hashName = "${sourceName}Sha256"
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash -ne [string]$report.source.$hashName) {
        throw "Candidate source hash changed: $sourceName"
    }
}
$exePath = (Resolve-Path -LiteralPath ([string]$report.gameExecutable.path)).Path
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $exePath).Hash -ne [string]$report.gameExecutable.sha256) {
    throw 'Candidate executable fingerprint changed.'
}

$captureManifestPath = (Resolve-Path -LiteralPath ([string]$report.source.captureManifest)).Path
$captureRoot = (Split-Path -Parent $captureManifestPath).TrimEnd('\')
function Resolve-CapturedReviewArtifact {
    param([Parameter(Mandatory)][string]$RelativePath)
    $full = [IO.Path]::GetFullPath((Join-Path $captureRoot ($RelativePath -replace '/', '\')))
    if (-not $full.StartsWith($captureRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Candidate artifact escaped the imported capture: $RelativePath"
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Candidate artifact is missing: $RelativePath" }
    return $full
}

$requiredGates = @(
    'binding-contract',
    'replacement-shader',
    'control-pack',
    'live-visual-validation',
    'runtime-eligibility-review'
)
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$candidateReviews = [Collections.Generic.List[object]]::new()
foreach ($candidate in @($report.candidates)) {
    if (-not $seen.Add([string]$candidate.candidateId)) { throw "Duplicate candidate identity: $($candidate.candidateId)" }
    $missing = @($candidate.missingGates | ForEach-Object { [string]$_ })
    if ($missing.Count -ne $requiredGates.Count -or @($requiredGates | Where-Object { $missing -notcontains $_ }).Count) {
        throw "Candidate does not declare the exact required gate set: $($candidate.candidateId)"
    }
    $binary = Resolve-CapturedReviewArtifact ([string]$candidate.capturedArtifacts.binary)
    $assembly = Resolve-CapturedReviewArtifact ([string]$candidate.capturedArtifacts.assembly)
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $binary).Hash -ne [string]$candidate.capturedArtifacts.binarySha256) {
        throw "Candidate binary hash changed: $($candidate.candidateId)"
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $assembly).Hash -ne [string]$candidate.capturedArtifacts.assemblySha256) {
        throw "Candidate assembly hash changed: $($candidate.candidateId)"
    }
    $gates = foreach ($gate in $requiredGates) {
        [ordered]@{
            id = $gate
            status = 'pending'
            evidence = $null
            evidenceSha256 = $null
            reviewedBy = $null
            reviewedAtUtc = $null
            notes = $null
        }
    }
    $candidateReviews.Add([ordered]@{
        candidateId = [string]$candidate.candidateId
        descriptorId = [string]$candidate.descriptorId
        family = [string]$candidate.family
        shaderHash = [string]$candidate.shaderHash
        stage = [string]$candidate.stage
        shaderModel = [string]$candidate.shaderModel
        status = 'review-pending'
        runtimeEligible = $false
        completedGateCount = 0
        gates = @($gates)
    })
}

$workspace = [ordered]@{
    schemaVersion = 1
    reviewWorkspaceId = [string]$report.captureId
    captureId = [string]$report.captureId
    status = 'review-pending'
    runtimeEligible = $false
    failClosed = $true
    sourceCandidateReport = [ordered]@{
        path = $candidatePath
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidatePath).Hash
        status = 'scan-evidence-only'
        candidateCount = [int]$report.candidateCount
    }
    gameExecutable = [ordered]@{
        name = [string]$report.gameExecutable.name
        path = $exePath
        sha256 = [string]$report.gameExecutable.sha256
    }
    requiredGates = $requiredGates
    candidateReviewCount = $candidateReviews.Count
    candidates = @($candidateReviews)
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
}

[IO.Directory]::CreateDirectory((Split-Path -Parent $outputFull)) | Out-Null
$json = ($workspace | ConvertTo-Json -Depth 12) + [Environment]::NewLine
if (-not ($json | Test-Json -SchemaFile $reviewSchema -ErrorAction Stop)) {
    throw 'Generated adapter review workspace failed its schema.'
}
[IO.File]::WriteAllText($outputFull, $json, [Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'Assert-UE4AdapterReviewWorkspace.ps1') -Path $outputFull -ProjectRoot $projectPath | Out-Null

[pscustomobject]@{
    CaptureId = [string]$report.captureId
    CandidateReviews = $candidateReviews.Count
    CompletedGates = 0
    RuntimeEligible = $false
    Output = $outputFull
    Sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputFull).Hash
    Result = 'review-pending-fail-closed'
}
