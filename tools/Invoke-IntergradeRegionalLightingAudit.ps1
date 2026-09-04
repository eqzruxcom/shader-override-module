[CmdletBinding()]
param(
    [string]$CaptureDirectory,
    [string]$ImportedCaptureDirectory,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')]
    [string]$CaptureId,
    [string]$PreviousLocalLightScanPath,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$FxcPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$project = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($ImportedCaptureDirectory)) {
    if ([string]::IsNullOrWhiteSpace($CaptureDirectory)) { throw 'CaptureDirectory is required when ImportedCaptureDirectory is not supplied.' }
    if ([string]::IsNullOrWhiteSpace($CaptureId)) { throw 'CaptureId is required when importing a new regional capture.' }
    $imported = Join-Path $project "artifacts\validation-captures\$CaptureId"
    $importArgs = @{
        CaptureDirectory = $CaptureDirectory
        CaptureId = $CaptureId
        ProjectRoot = $project
        OutputDirectory = $imported
        NearMatchLimitPerDescriptor = 10
    }
    if (-not [string]::IsNullOrWhiteSpace($FxcPath)) { $importArgs['FxcPath'] = $FxcPath }
    & (Join-Path $PSScriptRoot 'Import-UE4ValidationCapture.ps1') @importArgs | Out-Host
} else {
    $imported = (Resolve-Path -LiteralPath $ImportedCaptureDirectory -ErrorAction Stop).Path.TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($CaptureId)) { $CaptureId = Split-Path -Leaf $imported }
}

$allowed = [IO.Path]::GetFullPath((Join-Path $project 'artifacts\validation-captures')).TrimEnd('\')
$importedFull = [IO.Path]::GetFullPath($imported).TrimEnd('\')
if (-not $importedFull.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Imported capture must remain below artifacts/validation-captures.'
}

$assembly = Join-Path $importedFull 'assembly'
if (-not (Test-Path -LiteralPath $assembly -PathType Container)) { throw "Assembly directory missing: $assembly" }
$scanPath = Join-Path $importedFull 'local-light-radial-family-scan.json'
& (Join-Path $PSScriptRoot 'Find-IntergradeLocalLightRadialFamilies.ps1') `
    -AssemblyDirectory $assembly `
    -OutputPath $scanPath | Out-Host

$scan = Get-Content -Raw -LiteralPath $scanPath | ConvertFrom-Json
$previous = $null
if (-not [string]::IsNullOrWhiteSpace($PreviousLocalLightScanPath)) {
    $previousResolved = (Resolve-Path -LiteralPath $PreviousLocalLightScanPath -ErrorAction Stop).Path
    $previous = Get-Content -Raw -LiteralPath $previousResolved | ConvertFrom-Json
    if ([string]$previous.detector -ne 'ff7-remake-dxbc-local-light-radial-semantic-v1') {
        throw 'PreviousLocalLightScanPath is not a supported local-light family scan.'
    }
}

$currentHashes = @($scan.actualCompatibleHashes | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique)
$previousHashes = if ($null -eq $previous) { @() } else { @($previous.actualCompatibleHashes | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique) }
$newHashes = @($currentHashes | Where-Object { $_ -notin $previousHashes })
$missingHashes = @($previousHashes | Where-Object { $_ -notin $currentHashes })
$exceptions = @($scan.structuralExceptions)

$summary = [ordered]@{
    schemaVersion = 1
    audit = 'ff7-remake-regional-lighting-family-audit-v1'
    captureId = $CaptureId
    importedCapture = $importedFull
    scannedShaderCount = [int]$scan.sourceShaderCount
    compatibleLocalLightCount = [int]$scan.compatibleMatchCount
    structuralExceptionCount = [int]$scan.structuralExceptionCount
    compatibleHashes = $currentHashes
    previousCompatibleHashes = $previousHashes
    newCompatibleHashes = $newHashes
    missingPreviouslyCompatibleHashes = $missingHashes
    automaticTransformationEligible = ($exceptions.Count -eq 0)
    automaticTransformationQueue = @($scan.compatibleMatches | Where-Object { $_.hash -in $newHashes })
    manualReviewQueue = $exceptions
    familyScan = [ordered]@{
        path = $scanPath
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $scanPath).Hash.ToUpperInvariant()
    }
    policy = [ordered]@{
        exactCompatibleMatch = 'May enter the transformation queue after its original DXBC and generated replacement pass assembly/interface validation.'
        structuralException = 'Never patch automatically; retain original and require manual binding/dataflow review.'
        missingPreviousHash = 'Treat as a regional/cache observation, not proof that the shader family was removed from the game.'
    }
}

$summaryPath = Join-Path $importedFull 'lighting-family-audit-summary.json'
[IO.File]::WriteAllText(
    $summaryPath,
    (($summary | ConvertTo-Json -Depth 14) + [Environment]::NewLine),
    [Text.UTF8Encoding]::new($false)
)

[pscustomobject]@{
    CaptureId = $CaptureId
    ScannedShaders = $summary.scannedShaderCount
    CompatibleLocalLights = $summary.compatibleLocalLightCount
    StructuralExceptions = $summary.structuralExceptionCount
    NewCompatibleHashes = ($newHashes -join ',')
    AutomaticTransformationEligible = $summary.automaticTransformationEligible
    Summary = $summaryPath
}

