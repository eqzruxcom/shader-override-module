[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$caseRoot = Join-Path $repoRoot 'artifacts\ue4-adapter-candidate-test'
$captureRoot = Join-Path $caseRoot 'capture'
$binaryRoot = Join-Path $captureRoot 'dxbc'
$assemblyRoot = Join-Path $captureRoot 'assembly'
$exe = Join-Path $caseRoot 'CandidateGame.exe'
$installManifest = Join-Path $caseRoot 'install.json'
$output = Join-Path $repoRoot 'artifacts\generated-adapter-candidates\candidate-test\candidate-report.json'
$generator = Join-Path $repoRoot 'tools\New-UE4AdapterCandidateReport.ps1'
$schema = Join-Path $repoRoot 'src\Engine\UE4\AdapterCandidates\schema.json'
$utf8 = [Text.UTF8Encoding]::new($false)
if (Test-Path -LiteralPath $caseRoot) { Remove-Item -LiteralPath $caseRoot -Recurse -Force }
[IO.Directory]::CreateDirectory($binaryRoot) | Out-Null
[IO.Directory]::CreateDirectory($assemblyRoot) | Out-Null
[IO.File]::WriteAllBytes($exe, [byte[]](11,22,33,44))
$hash = 'a77b589dce5822d6'
$stage = 'ps'
$binary = Join-Path $binaryRoot "$hash-$stage.bin"
$assembly = Join-Path $assemblyRoot "$hash-$stage.asm"
[IO.File]::WriteAllBytes($binary, [byte[]](1,3,3,7))
Copy-Item -LiteralPath (Join-Path $repoRoot "src\Tests\Fixtures\UE4Semantic\$hash-$stage.asm") -Destination $assembly
$evidence = [ordered]@{ id='fixture-check'; count=1; minCount=1; maxCount=1; satisfied=$true; meaning='Fixture semantic evidence.' }
$semantic = [ordered]@{
    schemaVersion = 1
    shaders = [ordered]@{ directory=$assemblyRoot; scanned=1; replacementArtifactsExcluded=$true }
    matches = @([ordered]@{
        descriptor='ue4-temporal-ssao-horizon-ps-sm5'; family='ambient-occlusion'; displayName='UE4 temporal SSAO fixture'
        hash=$hash; stage=$stage; shaderModel='ps_5_0'; semanticChecksPassed=1; fastPathAdapters=@('FF7RemakeIntergrade')
        evidence=@($evidence); artifacts=@([ordered]@{ file=$assembly; semanticChecksPassed=1 })
    })
    nearMatches = @()
}
$semanticPath = Join-Path $captureRoot 'semantic-matches.json'
[IO.File]::WriteAllText($semanticPath, ($semantic | ConvertTo-Json -Depth 10)+[Environment]::NewLine, $utf8)
$capture = [ordered]@{
    schemaVersion=1; captureId='candidate-test'; importedAtUtc='2026-08-30T00:00:00Z'; source=(Join-Path $caseRoot 'source\ShaderCache')
    localResearchOnly=$true; redistributionAllowed=$false; fxc=[ordered]@{path='C:\SDK\fxc.exe';sha256=('A'*64)}
    capturedShaderCount=1; semanticMatchCount=1; nearMatchCount=0
    semanticReport='semantic-matches.json'; semanticReportSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $semanticPath).Hash
    shaders=@([ordered]@{
        shader="$hash-$stage"; sourceSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $binary).Hash
        binary="dxbc/$hash-$stage.bin"; assembly="assembly/$hash-$stage.asm"; assemblySha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $assembly).Hash
    })
}
$capturePath = Join-Path $captureRoot 'capture-manifest.json'
[IO.File]::WriteAllText($capturePath, ($capture | ConvertTo-Json -Depth 10)+[Environment]::NewLine, $utf8)
$installFiles = foreach ($name in @('d3d11.dll','d3dcompiler_46.dll','nvapi64.dll','d3dx.ini')) {
    [ordered]@{relativePath=$name;hadOriginal=$false;originalSha256=$null;installedSha256=('A'*64)}
}
$install = [ordered]@{
    schemaVersion=1; captureId='candidate-test'; installedAtUtc='2026-08-30T00:00:00Z'
    gameExecutable=[ordered]@{ path=$exe; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash }; targetRoot=$caseRoot
    kitManifest='artifacts/ue4-validation-capture-kit/capture-kit-manifest.json'; kitManifestSha256=('A'*64)
    backupRoot=(Join-Path $repoRoot 'backups\UE4ValidationCaptureKit\candidate-test\fixture'); files=@($installFiles)
}
[IO.File]::WriteAllText($installManifest, ($install|ConvertTo-Json -Depth 5)+[Environment]::NewLine, $utf8)

& $generator -CaptureDirectory $captureRoot -CaptureId 'candidate-test' -InstallManifestPath $installManifest -OutputPath $output | Out-Null
$json = Get-Content -Raw -LiteralPath $output
if (-not ($json | Test-Json -SchemaFile $schema -ErrorAction Stop)) { throw 'Candidate report does not satisfy its schema.' }
$report = $json | ConvertFrom-Json
if ($report.runtimeEligible -ne $false -or $report.failClosed -ne $true -or $report.status -ne 'scan-evidence-only') { throw 'Candidate report did not fail closed.' }
if ([int]$report.candidateCount -ne 1 -or @($report.candidates).Count -ne 1) { throw 'Candidate report did not contain exactly one candidate.' }
$candidate = $report.candidates[0]
if ($candidate.runtimeEligible -ne $false -or $candidate.status -ne 'scan-evidence-only') { throw 'Semantic match was incorrectly promoted to runtime eligibility.' }
foreach ($gate in @('binding-contract','replacement-shader','control-pack','live-visual-validation','runtime-eligibility-review')) {
    if (@($candidate.missingGates) -notcontains $gate) { throw "Candidate omitted required gate: $gate" }
}

$semantic.matches = @($semantic.matches[0], $semantic.matches[0])
$capture.semanticMatchCount = 2
[IO.File]::WriteAllText($semanticPath, ($semantic | ConvertTo-Json -Depth 10)+[Environment]::NewLine, $utf8)
$capture.semanticReportSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $semanticPath).Hash
[IO.File]::WriteAllText($capturePath, ($capture | ConvertTo-Json -Depth 10)+[Environment]::NewLine, $utf8)
$refusedDuplicate = $false
try { & $generator -CaptureDirectory $captureRoot -CaptureId 'candidate-test' -InstallManifestPath $installManifest -OutputPath $output | Out-Null }
catch { $refusedDuplicate = $_.Exception.Message -match 'Duplicate semantic candidate identity' }
if (-not $refusedDuplicate) { throw 'Generator accepted a duplicate semantic candidate identity.' }
$semantic.matches = @($semantic.matches[0])
$capture.semanticMatchCount = 1
[IO.File]::WriteAllText($semanticPath, ($semantic | ConvertTo-Json -Depth 10)+[Environment]::NewLine, $utf8)
$capture.semanticReportSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $semanticPath).Hash
[IO.File]::WriteAllText($capturePath, ($capture | ConvertTo-Json -Depth 10)+[Environment]::NewLine, $utf8)

$capture.capturedShaderCount = 2
[IO.File]::WriteAllText($capturePath, ($capture | ConvertTo-Json -Depth 10)+[Environment]::NewLine, $utf8)
$refusedCount = $false
try { & $generator -CaptureDirectory $captureRoot -CaptureId 'candidate-test' -InstallManifestPath $installManifest -OutputPath $output | Out-Null }
catch { $refusedCount = $_.Exception.Message -match 'Captured shader count' }
if (-not $refusedCount) { throw 'Generator accepted a mismatched captured-shader count.' }
$capture.capturedShaderCount = 1
[IO.File]::WriteAllText($capturePath, ($capture | ConvertTo-Json -Depth 10)+[Environment]::NewLine, $utf8)

$unsafe = $json | ConvertFrom-Json
$unsafe.runtimeEligible = $true
$unsafeJson = $unsafe | ConvertTo-Json -Depth 15
$schemaErrors = @()
if ($unsafeJson | Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue -ErrorVariable +schemaErrors) {
    throw 'Candidate schema accepted runtimeEligible=true.'
}

$semantic.shaders.replacementArtifactsExcluded = $false
[IO.File]::WriteAllText($semanticPath, ($semantic | ConvertTo-Json -Depth 10)+[Environment]::NewLine, $utf8)
$capture.semanticReportSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $semanticPath).Hash
[IO.File]::WriteAllText($capturePath, ($capture | ConvertTo-Json -Depth 10)+[Environment]::NewLine, $utf8)
$refusedReplacementEvidence = $false
try { & $generator -CaptureDirectory $captureRoot -CaptureId 'candidate-test' -InstallManifestPath $installManifest -OutputPath $output | Out-Null }
catch { $refusedReplacementEvidence = $_.Exception.Message -match 'exclude replacement artifacts' }
if (-not $refusedReplacementEvidence) { throw 'Generator accepted semantic evidence that included replacement artifacts.' }

$semantic.shaders.replacementArtifactsExcluded = $true
[IO.File]::WriteAllText($semanticPath, ($semantic | ConvertTo-Json -Depth 10)+[Environment]::NewLine, $utf8)
$capture.semanticReportSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $semanticPath).Hash
[IO.File]::WriteAllText($capturePath, ($capture | ConvertTo-Json -Depth 10)+[Environment]::NewLine, $utf8)
$originalExe = [IO.File]::ReadAllBytes($exe)
[IO.File]::WriteAllBytes($exe, [byte[]](99,88,77))
$refusedFingerprint = $false
try { & $generator -CaptureDirectory $captureRoot -CaptureId 'candidate-test' -InstallManifestPath $installManifest -OutputPath $output | Out-Null }
catch { $refusedFingerprint = $_.Exception.Message -match 'fingerprint' }
if (-not $refusedFingerprint) { throw 'Generator accepted a changed executable fingerprint.' }
[IO.File]::WriteAllBytes($exe, $originalExe)

$install.captureId = 'wrong-capture'
$install.backupRoot = Join-Path $repoRoot 'backups\UE4ValidationCaptureKit\wrong-capture\fixture'
[IO.File]::WriteAllText($installManifest, ($install|ConvertTo-Json -Depth 7)+[Environment]::NewLine, $utf8)
$refusedCaptureId = $false
try { & $generator -CaptureDirectory $captureRoot -CaptureId 'candidate-test' -InstallManifestPath $installManifest -OutputPath $output | Out-Null }
catch { $refusedCaptureId = $_.Exception.Message -match 'install manifest' }
if (-not $refusedCaptureId) { throw 'Generator accepted a mismatched install-manifest capture id.' }

Write-Output 'UE4 fail-closed adapter candidate report tests passed.'
