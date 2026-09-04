[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$caseRoot = Join-Path $repoRoot 'artifacts\ue4-adapter-review-test'
$captureRoot = Join-Path $caseRoot 'capture'
$candidatePath = Join-Path $repoRoot 'artifacts\generated-adapter-candidates\review-test\candidate-report.json'
$workspacePath = Join-Path $repoRoot 'artifacts\adapter-reviews\review-test\review-workspace.json'
$schemaPath = Join-Path $repoRoot 'src\Engine\UE4\AdapterReviews\schema.json'
$utf8 = [Text.UTF8Encoding]::new($false)
if (Test-Path -LiteralPath $caseRoot) { Remove-Item -LiteralPath $caseRoot -Recurse -Force }
[IO.Directory]::CreateDirectory((Join-Path $captureRoot 'dxbc')) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $captureRoot 'assembly')) | Out-Null
[IO.Directory]::CreateDirectory((Split-Path -Parent $candidatePath)) | Out-Null
$exe = Join-Path $caseRoot 'ReviewGame.exe'
$binary = Join-Path $captureRoot 'dxbc\a77b589dce5822d6-ps.bin'
$assembly = Join-Path $captureRoot 'assembly\a77b589dce5822d6-ps.asm'
$captureManifest = Join-Path $captureRoot 'capture-manifest.json'
$semanticReport = Join-Path $captureRoot 'semantic-matches.json'
$installManifest = Join-Path $caseRoot 'install.json'
[IO.File]::WriteAllBytes($exe, [byte[]](12,34,56,78))
[IO.File]::WriteAllBytes($binary, [byte[]](1,2,3,4))
[IO.File]::WriteAllText($assembly, "ps_5_0`nret`n", $utf8)
[IO.File]::WriteAllText($captureManifest, "{}`n", $utf8)
[IO.File]::WriteAllText($semanticReport, "{}`n", $utf8)
[IO.File]::WriteAllText($installManifest, "{}`n", $utf8)
$candidate = [ordered]@{
    schemaVersion=1; captureId='review-test'; status='scan-evidence-only'; runtimeEligible=$false; failClosed=$true
    gameExecutable=[ordered]@{name='ReviewGame.exe';path=$exe;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash}
    source=[ordered]@{
        captureManifest=$captureManifest;captureManifestSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $captureManifest).Hash
        semanticReport=$semanticReport;semanticReportSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $semanticReport).Hash
        installManifest=$installManifest;installManifestSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $installManifest).Hash
    }
    candidateCount=1
    candidates=@([ordered]@{
        candidateId='ue4-temporal-ssao-horizon-ps-sm5/a77b589dce5822d6-ps';descriptorId='ue4-temporal-ssao-horizon-ps-sm5'
        family='ambient-occlusion';displayName='UE4 temporal SSAO fixture';shaderHash='a77b589dce5822d6';stage='ps';shaderModel='ps_5_0'
        semanticChecksPassed=1;status='scan-evidence-only';runtimeEligible=$false
        missingGates=@('binding-contract','replacement-shader','control-pack','live-visual-validation','runtime-eligibility-review')
        fastPathAdapters=@();semanticEvidence=@([ordered]@{id='fixture';count=1;minCount=1;maxCount=1;satisfied=$true;meaning='Fixture evidence.'})
        capturedArtifacts=[ordered]@{
            binary='dxbc/a77b589dce5822d6-ps.bin';binarySha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $binary).Hash
            assembly='assembly/a77b589dce5822d6-ps.asm';assemblySha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $assembly).Hash
        }
    })
    generatedAtUtc='2026-08-30T00:00:00Z'
}
[IO.File]::WriteAllText($candidatePath, ($candidate | ConvertTo-Json -Depth 12)+[Environment]::NewLine, $utf8)

$result = & (Join-Path $repoRoot 'tools\New-UE4AdapterReviewWorkspace.ps1') -CandidateReportPath $candidatePath -OutputPath $workspacePath
if ($result.Result -ne 'review-pending-fail-closed' -or $result.RuntimeEligible -ne $false -or [int]$result.CompletedGates -ne 0) {
    throw 'Review generator did not fail closed.'
}
$workspaceJson = Get-Content -Raw -LiteralPath $workspacePath
if (-not ($workspaceJson | Test-Json -SchemaFile $schemaPath -ErrorAction Stop)) { throw 'Review workspace failed its schema.' }
$workspace = $workspaceJson | ConvertFrom-Json
if ($workspace.runtimeEligible -ne $false -or $workspace.failClosed -ne $true -or $workspace.status -ne 'review-pending') {
    throw 'Review workspace was not initialized fail closed.'
}
if ([int]$workspace.candidateReviewCount -ne 1 -or [int]$workspace.candidates[0].completedGateCount -ne 0) {
    throw 'Review workspace initialized an invalid candidate count or completed gate.'
}
foreach ($gate in @($workspace.candidates[0].gates)) {
    if ($gate.status -ne 'pending' -or $null -ne $gate.evidence) { throw "Review gate was not pending: $($gate.id)" }
}
& (Join-Path $repoRoot 'tools\Assert-UE4AdapterReviewWorkspace.ps1') -Path $workspacePath | Out-Null

$unsafe = $workspaceJson | ConvertFrom-Json
$unsafe.runtimeEligible = $true
$schemaErrors = @()
if (($unsafe | ConvertTo-Json -Depth 12) | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue -ErrorVariable +schemaErrors) {
    throw 'Review schema accepted runtimeEligible=true.'
}
$unsafe = $workspaceJson | ConvertFrom-Json
$unsafe.candidates[0].gates[0].status = 'passed'
$unsafe.candidates[0].completedGateCount = 1
[IO.File]::WriteAllText($workspacePath, ($unsafe | ConvertTo-Json -Depth 12)+[Environment]::NewLine, $utf8)
$refusedPreverified = $false
try { & (Join-Path $repoRoot 'tools\Assert-UE4AdapterReviewWorkspace.ps1') -Path $workspacePath | Out-Null }
catch { $refusedPreverified = $_.Exception.Message -match 'schema|unverified' }
if (-not $refusedPreverified) { throw 'Review verifier accepted a pre-verified gate without evidence.' }
[IO.File]::WriteAllText($workspacePath, $workspaceJson, $utf8)

$duplicate = $workspaceJson | ConvertFrom-Json
$duplicate.candidates = @($duplicate.candidates[0], $duplicate.candidates[0])
$duplicate.candidateReviewCount = 2
[IO.File]::WriteAllText($workspacePath, ($duplicate | ConvertTo-Json -Depth 12)+[Environment]::NewLine, $utf8)
$refusedDuplicate = $false
try { & (Join-Path $repoRoot 'tools\Assert-UE4AdapterReviewWorkspace.ps1') -Path $workspacePath | Out-Null }
catch { $refusedDuplicate = $_.Exception.Message -match 'count|Duplicate' }
if (-not $refusedDuplicate) { throw 'Review verifier accepted a duplicate candidate.' }
[IO.File]::WriteAllText($workspacePath, $workspaceJson, $utf8)

$candidateOriginal = Get-Content -Raw -LiteralPath $candidatePath
[IO.File]::WriteAllText($candidatePath, $candidateOriginal + " `n", $utf8)
$refusedChangedSource = $false
try { & (Join-Path $repoRoot 'tools\Assert-UE4AdapterReviewWorkspace.ps1') -Path $workspacePath | Out-Null }
catch { $refusedChangedSource = $_.Exception.Message -match 'source candidate report hash changed' }
if (-not $refusedChangedSource) { throw 'Review verifier accepted a changed source candidate report.' }
[IO.File]::WriteAllText($candidatePath, $candidateOriginal, $utf8)

$exeOriginal = [IO.File]::ReadAllBytes($exe)
[IO.File]::WriteAllBytes($exe, [byte[]](99,88,77))
$refusedExe = $false
try { & (Join-Path $repoRoot 'tools\Assert-UE4AdapterReviewWorkspace.ps1') -Path $workspacePath | Out-Null }
catch { $refusedExe = $_.Exception.Message -match 'executable fingerprint' }
if (-not $refusedExe) { throw 'Review verifier accepted a changed executable.' }
[IO.File]::WriteAllBytes($exe, $exeOriginal)

Write-Output 'UE4 fail-closed adapter review workspace tests passed.'
