[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CaptureDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')][string]$CaptureId,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$InstallManifestPath,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$captureRoot = (Resolve-Path -LiteralPath $CaptureDirectory).Path.TrimEnd('\')
$captureManifestPath = Join-Path $captureRoot 'capture-manifest.json'
$schemaPath = Join-Path $projectPath 'src\Engine\UE4\AdapterCandidates\schema.json'
if ([string]::IsNullOrWhiteSpace($InstallManifestPath)) {
    $InstallManifestPath = Join-Path $projectPath "artifacts\installed-validation-capture-kits\$CaptureId.json"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectPath "artifacts\generated-adapter-candidates\$CaptureId\candidate-report.json"
}
$installManifestFull = (Resolve-Path -LiteralPath $InstallManifestPath).Path
$outputFull = [IO.Path]::GetFullPath($OutputPath)
$allowedOutput = [IO.Path]::GetFullPath((Join-Path $projectPath 'artifacts\generated-adapter-candidates')).TrimEnd('\')
if (-not $outputFull.StartsWith($allowedOutput + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Adapter candidate output must remain below artifacts/generated-adapter-candidates.'
}
if (-not (Test-Path -LiteralPath $captureManifestPath -PathType Leaf)) { throw 'Capture manifest is missing.' }
if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) { throw 'Adapter-candidate schema is missing.' }

function Resolve-CaptureArtifact {
    param([Parameter(Mandatory)][string]$RelativePath)
    $resolved = [IO.Path]::GetFullPath((Join-Path $captureRoot ($RelativePath -replace '/', '\')))
    if (-not $resolved.StartsWith($captureRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Capture artifact escaped the capture directory: $RelativePath"
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Capture artifact is missing: $RelativePath" }
    return $resolved
}

$manifestValidator = Join-Path $PSScriptRoot 'Assert-UE4ValidationManifest.ps1'
$capture = & $manifestValidator -Kind Capture -Path $captureManifestPath -ProjectRoot $projectPath
$install = & $manifestValidator -Kind Install -Path $installManifestFull -ProjectRoot $projectPath
if ([string]$capture.captureId -ne $CaptureId) { throw 'Capture id does not match the capture manifest.' }
if ([string]$install.captureId -ne $CaptureId) { throw 'Capture id does not match the install manifest.' }
if (-not [bool]$capture.localResearchOnly -or [bool]$capture.redistributionAllowed) {
    throw 'Capture manifest does not satisfy the local-only research contract.'
}

$semanticReportPath = Resolve-CaptureArtifact ([string]$capture.semanticReport)
$semanticReportSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $semanticReportPath).Hash
if ($semanticReportSha -ne [string]$capture.semanticReportSha256) { throw 'Semantic report hash does not match the capture manifest.' }
$semantic = Get-Content -Raw -LiteralPath $semanticReportPath | ConvertFrom-Json
if (-not [bool]$semantic.shaders.replacementArtifactsExcluded) {
    throw 'Semantic report did not exclude replacement artifacts.'
}
if ([int]$semantic.schemaVersion -ne 1) { throw 'Unsupported semantic report schema version.' }
if (@($semantic.matches).Count -ne [int]$capture.semanticMatchCount) {
    throw 'Semantic match count does not match the capture manifest.'
}
if (@($semantic.nearMatches).Count -ne [int]$capture.nearMatchCount) {
    throw 'Semantic near-match count does not match the capture manifest.'
}
if ([int]$semantic.shaders.scanned -ne [int]$capture.capturedShaderCount) {
    throw 'Semantic scanned-shader count does not match the capture manifest.'
}
$reportedAssemblyRoot = [IO.Path]::GetFullPath([string]$semantic.shaders.directory).TrimEnd('\')
$expectedAssemblyRoot = [IO.Path]::GetFullPath((Join-Path $captureRoot 'assembly')).TrimEnd('\')
if (-not $reportedAssemblyRoot.Equals($expectedAssemblyRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Semantic report shader directory is not the captured assembly directory.'
}

$exePath = (Resolve-Path -LiteralPath ([string]$install.gameExecutable.path)).Path
$exeSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $exePath).Hash
if ($exeSha -ne [string]$install.gameExecutable.sha256) { throw 'Game executable fingerprint does not match the install manifest.' }

$missingGates = @(
    'binding-contract',
    'replacement-shader',
    'control-pack',
    'live-visual-validation',
    'runtime-eligibility-review'
)
$candidates = [Collections.Generic.List[object]]::new()
$seenCandidates = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($match in @($semantic.matches)) {
    $hash = ([string]$match.hash).ToLowerInvariant()
    $stage = ([string]$match.stage).ToLowerInvariant()
    if ($hash -notmatch '^[0-9a-f]{16}$' -or $stage -notmatch '^(ps|vs|cs|gs|hs|ds)$') {
        throw 'Semantic match contains an invalid shader identity.'
    }
    if ([string]$match.shaderModel -ne "${stage}_5_0") { throw "Semantic match is not SM5: $hash-$stage" }
    $recordId = "$hash-$stage"
    $candidateIdentity = "$([string]$match.descriptor)/$recordId"
    if (-not $seenCandidates.Add($candidateIdentity)) { throw "Duplicate semantic candidate identity: $candidateIdentity" }
    $record = @($capture.shaders | Where-Object { ([string]$_.shader).ToLowerInvariant() -eq $recordId })
    if ($record.Count -ne 1) { throw "Semantic match does not map to exactly one captured shader: $recordId" }
    $binaryPath = Resolve-CaptureArtifact ([string]$record[0].binary)
    $assemblyPath = Resolve-CaptureArtifact ([string]$record[0].assembly)
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $binaryPath).Hash -ne [string]$record[0].sourceSha256) {
        throw "Captured binary hash mismatch: $recordId"
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $assemblyPath).Hash -ne [string]$record[0].assemblySha256) {
        throw "Captured assembly hash mismatch: $recordId"
    }
    $reportedArtifacts = @($match.artifacts | ForEach-Object { [IO.Path]::GetFullPath([string]$_.file) })
    if ($reportedArtifacts.Count -ne 1 -or -not $reportedArtifacts[0].Equals($assemblyPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Semantic evidence is not the captured assembly artifact: $recordId"
    }
    if (@($match.evidence).Count -lt 1 -or @($match.evidence | Where-Object { $_.satisfied -ne $true }).Count) {
        throw "Semantic match contains incomplete evidence: $recordId"
    }
    if ([int]$match.semanticChecksPassed -ne @($match.evidence).Count -or [int]$match.artifacts[0].semanticChecksPassed -ne [int]$match.semanticChecksPassed) {
        throw "Semantic evidence count is inconsistent: $recordId"
    }
    $candidates.Add([ordered]@{
        candidateId = $candidateIdentity
        descriptorId = [string]$match.descriptor
        family = [string]$match.family
        displayName = [string]$match.displayName
        shaderHash = $hash
        stage = $stage
        shaderModel = [string]$match.shaderModel
        semanticChecksPassed = [int]$match.semanticChecksPassed
        status = 'scan-evidence-only'
        runtimeEligible = $false
        missingGates = $missingGates
        fastPathAdapters = @($match.fastPathAdapters | ForEach-Object { [string]$_ })
        semanticEvidence = @($match.evidence | ForEach-Object {
            [ordered]@{
                id = [string]$_.id
                count = [int]$_.count
                minCount = [int]$_.minCount
                maxCount = if ($null -eq $_.maxCount) { $null } else { [int]$_.maxCount }
                satisfied = $true
                meaning = [string]$_.meaning
            }
        })
        capturedArtifacts = [ordered]@{
            binary = [string]$record[0].binary
            binarySha256 = [string]$record[0].sourceSha256
            assembly = [string]$record[0].assembly
            assemblySha256 = [string]$record[0].assemblySha256
        }
    })
}

$report = [ordered]@{
    schemaVersion = 1
    captureId = $CaptureId
    status = 'scan-evidence-only'
    runtimeEligible = $false
    failClosed = $true
    gameExecutable = [ordered]@{
        name = [IO.Path]::GetFileName($exePath)
        path = $exePath
        sha256 = $exeSha
    }
    source = [ordered]@{
        captureManifest = $captureManifestPath
        captureManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $captureManifestPath).Hash
        semanticReport = $semanticReportPath
        semanticReportSha256 = $semanticReportSha
        installManifest = $installManifestFull
        installManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $installManifestFull).Hash
    }
    candidateCount = $candidates.Count
    candidates = @($candidates)
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
}
[IO.Directory]::CreateDirectory((Split-Path -Parent $outputFull)) | Out-Null
$json = ($report | ConvertTo-Json -Depth 15) + [Environment]::NewLine
if (-not ($json | Test-Json -SchemaFile $schemaPath -ErrorAction Stop)) { throw 'Generated adapter candidate report failed its schema.' }
[IO.File]::WriteAllText($outputFull, $json, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    CaptureId = $CaptureId
    Candidates = $candidates.Count
    RuntimeEligible = $false
    Output = $outputFull
    Sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputFull).Hash
    Result = 'scan-evidence-only'
}
