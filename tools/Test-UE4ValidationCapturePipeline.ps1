[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$caseRoot = Join-Path $repoRoot 'artifacts\ue4-validation-capture-pipeline-test'
$shaderCache = Join-Path $caseRoot 'raw\ShaderCache'
$exe = Join-Path $caseRoot 'PipelineGame.exe'
$installManifest = Join-Path $caseRoot 'install.json'
$importOutput = Join-Path $repoRoot 'artifacts\validation-captures\pipeline-test'
$candidateOutput = Join-Path $repoRoot 'artifacts\generated-adapter-candidates\pipeline-test\candidate-report.json'
$reviewOutput = Join-Path $repoRoot 'artifacts\adapter-reviews\pipeline-test\review-workspace.json'
$utf8 = [Text.UTF8Encoding]::new($false)
if (Test-Path -LiteralPath $caseRoot) { Remove-Item -LiteralPath $caseRoot -Recurse -Force }
[IO.Directory]::CreateDirectory($shaderCache) | Out-Null
[IO.File]::WriteAllBytes($exe, [byte[]](5,10,15,20))
Copy-Item -LiteralPath (Join-Path $repoRoot 'artifacts\PostProcessSmoke_ps.cso') -Destination (Join-Path $shaderCache '2222222222222222-ps.bin')
$installFiles = foreach ($name in @('d3d11.dll','d3dcompiler_46.dll','nvapi64.dll','d3dx.ini')) {
    [ordered]@{relativePath=$name;hadOriginal=$false;originalSha256=$null;installedSha256=('A'*64)}
}
$install = [ordered]@{
    schemaVersion = 1; captureId = 'pipeline-test'; installedAtUtc='2026-08-30T00:00:00Z'
    gameExecutable = [ordered]@{ path=$exe; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash }; targetRoot=$caseRoot
    kitManifest='artifacts/ue4-validation-capture-kit/capture-kit-manifest.json'; kitManifestSha256=('A'*64)
    backupRoot=(Join-Path $repoRoot 'backups\UE4ValidationCaptureKit\pipeline-test\fixture'); files=@($installFiles)
}
[IO.File]::WriteAllText($installManifest, ($install | ConvertTo-Json -Depth 5)+[Environment]::NewLine, $utf8)

$result = & (Join-Path $repoRoot 'tools\Invoke-UE4ValidationCapturePipeline.ps1') `
    -CaptureDirectory (Join-Path $caseRoot 'raw') `
    -CaptureId 'pipeline-test' `
    -InstallManifestPath $installManifest `
    -ImportOutputDirectory $importOutput `
    -CandidateOutputPath $candidateOutput `
    -ReviewOutputPath $reviewOutput `
    -NearMatchLimitPerDescriptor 2
if ($result.Result -ne 'imported-scanned-review-pending-fail-closed' -or $result.RuntimeEligible -ne $false) {
    throw 'End-to-end capture pipeline did not fail closed.'
}
if (-not (Test-Path -LiteralPath (Join-Path $importOutput 'capture-manifest.json') -PathType Leaf)) { throw 'Pipeline import manifest is missing.' }
if (-not (Test-Path -LiteralPath $candidateOutput -PathType Leaf)) { throw 'Pipeline candidate report is missing.' }
if (-not (Test-Path -LiteralPath $reviewOutput -PathType Leaf)) { throw 'Pipeline review workspace is missing.' }
$candidate = Get-Content -Raw -LiteralPath $candidateOutput | ConvertFrom-Json
if ($candidate.runtimeEligible -ne $false -or $candidate.failClosed -ne $true) { throw 'Pipeline candidate report is not fail closed.' }
if ([int]$candidate.candidateCount -ne [int]$result.SemanticMatches) { throw 'Pipeline candidate count does not match semantic matches.' }
if ([string]$candidate.gameExecutable.sha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash) { throw 'Pipeline lost executable fingerprint provenance.' }
$review = Get-Content -Raw -LiteralPath $reviewOutput | ConvertFrom-Json
if ($review.runtimeEligible -ne $false -or $review.failClosed -ne $true -or $review.status -ne 'review-pending') {
    throw 'Pipeline review workspace is not fail closed.'
}
if ([int]$review.candidateReviewCount -ne [int]$candidate.candidateCount -or [int]$result.CompletedReviewGates -ne 0) {
    throw 'Pipeline review workspace did not preserve candidate count or pending gates.'
}
& (Join-Path $repoRoot 'tools\Assert-UE4AdapterReviewWorkspace.ps1') -Path $reviewOutput | Out-Null

Write-Output 'UE4 end-to-end validation capture pipeline test passed.'
