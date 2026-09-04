[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$BaselinePath,
    [Parameter(Mandatory)]
    [string]$CandidatePath,
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\remake-area-inventory-delta.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-Inventory {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label inventory does not exist: $Path"
    }
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $report = Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json
    if ($report.schemaVersion -ne 1 -or $report.reportType -ne 'RebirthDonorRemakeCaptureInventory') {
        throw "$Label inventory has an unsupported schema or report type."
    }
    if ($null -eq $report.donor -or $null -eq $report.capture) {
        throw "$Label inventory is missing donor or capture data."
    }

    $shaderKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $stageCounts = [ordered]@{ vs = 0; ps = 0; cs = 0; gs = 0; hs = 0; ds = 0 }
    foreach ($shader in @($report.capture.shaders)) {
        $key = [string]$shader.shader
        if ($key -notmatch '^[0-9a-fA-F]{16}-(vs|ps|cs|gs|hs|ds)$') {
            throw "$Label inventory contains invalid shader key '$key'."
        }
        if (-not $shaderKeys.Add($key)) { throw "$Label inventory contains duplicate shader '$key'." }
        $stageCounts[[string]$shader.stage]++
    }
    if ($shaderKeys.Count -ne [int]$report.capture.shaderCount) {
        throw "$Label inventory shader count does not match its shader array."
    }
    foreach ($stage in $stageCounts.Keys) {
        if ($stageCounts[$stage] -ne [int]$report.capture.stageShaderCounts.$stage) {
            throw "$Label inventory stage count for $stage is inconsistent."
        }
    }

    $semanticKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($match in @($report.capture.semanticMatches)) {
        $shaderKey = "$($match.hash)-$($match.stage)"
        if (-not $shaderKeys.Contains($shaderKey)) {
            throw "$Label semantic match references absent shader '$shaderKey'."
        }
        $key = "$($match.descriptor)|$shaderKey"
        if (-not $semanticKeys.Add($key)) { throw "$Label inventory contains duplicate semantic match '$key'." }
    }
    if ($semanticKeys.Count -ne [int]$report.capture.semanticMatchCount) {
        throw "$Label inventory semantic count is inconsistent."
    }

    $familySignature = @($report.donor.families | Sort-Object family | ForEach-Object {
        "$($_.family)|$($_.stage)|$($_.packageCount)|$($_.targetCount)|$(@($_.versionGroups) -join ',')"
    })

    [pscustomobject]@{
        Path = $resolved
        Report = $report
        ShaderKeys = $shaderKeys
        SemanticKeys = $semanticKeys
        FamilySignature = $familySignature
    }
}

function Get-SetDifference {
    param(
        [Collections.Generic.HashSet[string]]$Left,
        [Collections.Generic.HashSet[string]]$Right
    )
    @($Left | Where-Object { -not $Right.Contains($_) } | Sort-Object)
}

function Get-StageCounts {
    param([string[]]$ShaderKeys)
    $counts = [ordered]@{ vs = 0; ps = 0; cs = 0; gs = 0; hs = 0; ds = 0 }
    foreach ($key in @($ShaderKeys)) {
        $stage = $key.Substring($key.Length - 2)
        $counts[$stage]++
    }
    [pscustomobject]$counts
}

$baseline = Read-Inventory $BaselinePath 'Baseline'
$candidate = Read-Inventory $CandidatePath 'Candidate'
if (Compare-Object $baseline.FamilySignature $candidate.FamilySignature) {
    throw 'The donor family/package identity differs between inventories; regenerate both with the same donor version.'
}

$addedShaders = @(Get-SetDifference $candidate.ShaderKeys $baseline.ShaderKeys)
$removedShaders = @(Get-SetDifference $baseline.ShaderKeys $candidate.ShaderKeys)
$addedSemantic = @(Get-SetDifference $candidate.SemanticKeys $baseline.SemanticKeys)
$removedSemantic = @(Get-SetDifference $baseline.SemanticKeys $candidate.SemanticKeys)

$report = [pscustomobject][ordered]@{
    schemaVersion = 1
    reportType = 'RemakeRegionalShaderInventoryDelta'
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{
        captureId = [string]$baseline.Report.capture.captureId
        inventory = $baseline.Path
        shaderCount = [int]$baseline.Report.capture.shaderCount
        semanticMatchCount = [int]$baseline.Report.capture.semanticMatchCount
    }
    candidate = [pscustomobject][ordered]@{
        captureId = [string]$candidate.Report.capture.captureId
        inventory = $candidate.Path
        shaderCount = [int]$candidate.Report.capture.shaderCount
        semanticMatchCount = [int]$candidate.Report.capture.semanticMatchCount
    }
    shaderDelta = [pscustomobject][ordered]@{
        addedCount = $addedShaders.Count
        removedCount = $removedShaders.Count
        addedStageCounts = Get-StageCounts $addedShaders
        removedStageCounts = Get-StageCounts $removedShaders
        added = $addedShaders
        removed = $removedShaders
    }
    semanticDelta = [pscustomobject][ordered]@{
        addedCount = $addedSemantic.Count
        removedCount = $removedSemantic.Count
        added = $addedSemantic
        removed = $removedSemantic
    }
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    [void](New-Item -ItemType Directory -Force -Path $outputDirectory)
}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding utf8

[pscustomobject]@{
    OutputPath = (Resolve-Path -LiteralPath $OutputPath).Path
    Baseline = $report.baseline.captureId
    Candidate = $report.candidate.captureId
    AddedShaders = $addedShaders.Count
    RemovedShaders = $removedShaders.Count
    AddedSemanticMatches = $addedSemantic.Count
    RemovedSemanticMatches = $removedSemantic.Count
}
