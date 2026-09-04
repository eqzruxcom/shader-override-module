[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CaptureDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')][string]$CaptureId,
    [Parameter(Mandatory)][string]$InstallManifestPath,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ImportOutputDirectory,
    [string]$CandidateOutputPath,
    [string]$ReviewOutputPath,
    [string]$FxcPath,
    [ValidateRange(0,100)][int]$NearMatchLimitPerDescriptor = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($ImportOutputDirectory)) {
    $ImportOutputDirectory = Join-Path $projectPath "artifacts\validation-captures\$CaptureId"
}
if ([string]::IsNullOrWhiteSpace($CandidateOutputPath)) {
    $CandidateOutputPath = Join-Path $projectPath "artifacts\generated-adapter-candidates\$CaptureId\candidate-report.json"
}
if ([string]::IsNullOrWhiteSpace($ReviewOutputPath)) {
    $ReviewOutputPath = Join-Path $projectPath "artifacts\adapter-reviews\$CaptureId\review-workspace.json"
}

$importParameters = @{
    CaptureDirectory = $CaptureDirectory
    CaptureId = $CaptureId
    ProjectRoot = $projectPath
    OutputDirectory = $ImportOutputDirectory
    NearMatchLimitPerDescriptor = $NearMatchLimitPerDescriptor
}
if (-not [string]::IsNullOrWhiteSpace($FxcPath)) { $importParameters.FxcPath = $FxcPath }
$importResult = & (Join-Path $PSScriptRoot 'Import-UE4ValidationCapture.ps1') @importParameters
$candidateResult = & (Join-Path $PSScriptRoot 'New-UE4AdapterCandidateReport.ps1') `
    -CaptureDirectory $ImportOutputDirectory `
    -CaptureId $CaptureId `
    -ProjectRoot $projectPath `
    -InstallManifestPath $InstallManifestPath `
    -OutputPath $CandidateOutputPath
$reviewResult = & (Join-Path $PSScriptRoot 'New-UE4AdapterReviewWorkspace.ps1') `
    -CandidateReportPath $candidateResult.Output `
    -ProjectRoot $projectPath `
    -OutputPath $ReviewOutputPath

[pscustomobject]@{
    CaptureId = $CaptureId
    CapturedShaders = [int]$importResult.Shaders
    SemanticMatches = [int]$importResult.SemanticMatches
    NearMatches = [int]$importResult.NearMatches
    Candidates = [int]$candidateResult.Candidates
    CandidateReviews = [int]$reviewResult.CandidateReviews
    CompletedReviewGates = [int]$reviewResult.CompletedGates
    RuntimeEligible = $false
    ImportedCapture = [string]$importResult.Output
    CandidateReport = [string]$candidateResult.Output
    ReviewWorkspace = [string]$reviewResult.Output
    Result = 'imported-scanned-review-pending-fail-closed'
}
