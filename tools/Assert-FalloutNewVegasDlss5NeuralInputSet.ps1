[CmdletBinding()]
param([Parameter(Mandatory)][string] $InputSetDirectory)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$root = [IO.Path]::GetFullPath($InputSetDirectory).TrimEnd('\')
$manifestPath = Join-Path $root 'neural-input-set.json'
$inputAssertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5NeuralInputs.ps1'

if (-not $root.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing neural-input validation outside workspace artifacts: $root"
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "neural-input-set.json is missing: $manifestPath"
}

function Get-Sha256Upper {
    param([string] $Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.kind -ne 'fallout-new-vegas-dlss5-neural-input-set') {
    throw 'Manifest does not identify a Fallout: New Vegas DLSS5 neural-input set.'
}
if ([string]::IsNullOrWhiteSpace([string]$manifest.inputSetId) -or $manifest.targetAdapter -ne 'FalloutNewVegas') {
    throw 'Neural-input set identity is incomplete.'
}
if ($manifest.policy.sourcePathsRetained -ne $false -or $manifest.policy.redistributionAuthorized -ne $false -or
    $manifest.policy.operatorSupplied -ne $true -or $manifest.policy.installable -ne $false) {
    throw 'Neural-input policy is missing or unsafe.'
}
if ($manifest.PSObject.Properties.Name -contains 'sourcePath' -or
    ($manifest | ConvertTo-Json -Depth 10) -match '(?i)\"sourcePath\"') {
    throw 'Neural-input manifest must not retain source paths.'
}

$records = @($manifest.files)
if ($records.Count -ne 3) { throw 'Neural-input set must inventory exactly three files.' }
$supportedHashes = @{
    renoDxDlss5 = 'A2973900531D58FF7BEB21172828095BCE2281BC2A81E82191F9D89C983D6A21'
    nvngxDlss = 'BE6E434A94CA32499515EB62CA0E6C274526055D568D0426E4C652DCDFB6EE6E'
    nvngxDlssNr = 'E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E'
}
if ([string]$manifest.profile.name -ne 'RenoDX-DLSS5-NR-310.8-native-resolution') { throw 'Neural-input set does not use the reviewed native-resolution profile.' }
$expectedRoles = @('renoDxDlss5', 'nvngxDlss', 'nvngxDlssNr')
$expectedPaths = @('renodx-dlss5.addon64', 'nvngx_dlss.dll', 'nvngx_dlssnr.dll')
$seenRoles = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$seenPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($record in $records) {
    $relative = [string]$record.relativePath
    $role = [string]$record.role
    if ($role -notin $expectedRoles -or -not $seenRoles.Add($role)) { throw "Unexpected or duplicate neural-input role: $role" }
    if ($relative -notin $expectedPaths -or -not $seenPaths.Add($relative)) { throw "Unexpected or duplicate neural-input path: $relative" }
    if ([IO.Path]::IsPathRooted($relative) -or $relative.Contains(':') -or $relative -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Unsafe neural-input path: $relative"
    }
    $path = Join-Path $root $relative
    if (([string]$record.sha256).ToUpperInvariant() -ne $supportedHashes[$role]) {
        throw "Neural-input role '$role' does not match the reviewed hash profile."
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Neural-input file is missing: $relative" }
    if ((Get-Sha256Upper $path) -ne ([string]$record.sha256).ToUpperInvariant()) { throw "Neural-input hash mismatch: $relative" }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$record.sizeBytes) { throw "Neural-input size mismatch: $relative" }
}
$actual = @(Get-ChildItem -LiteralPath $root -File | Where-Object Name -ne 'neural-input-set.json')
if ($actual.Count -ne 3 -or @($actual | Where-Object { -not $seenPaths.Contains($_.Name) }).Count -ne 0) {
    throw 'Neural-input set contains an unlisted or missing payload.'
}

$byRole = @{}
foreach ($record in $records) { $byRole[[string]$record.role] = $record }
$validation = & $inputAssertPath `
    -RenoDxAddonPath (Join-Path $root ([string]$byRole.renoDxDlss5.relativePath)) `
    -NvngxDlssPath (Join-Path $root ([string]$byRole.nvngxDlss.relativePath)) `
    -NvngxDlssNrPath (Join-Path $root ([string]$byRole.nvngxDlssNr.relativePath)) `
    -ExpectedRenoDxSha256 ([string]$byRole.renoDxDlss5.sha256) `
    -ExpectedDlssSha256 ([string]$byRole.nvngxDlss.sha256) `
    -ExpectedDlssNrSha256 ([string]$byRole.nvngxDlssNr.sha256)

if (-not $validation.Valid -or $validation.Dlss.SignatureStatus -ne 'Valid' -or $validation.DlssNr.SignatureStatus -ne 'Valid') {
    throw 'Neural-input payload failed its nested authenticity validation.'
}
if ([string]$manifest.profile.dlssNrVersion -ne [string]$validation.DlssNr.Version -or
    ([string]$manifest.profile.dlssNrSha256).ToUpperInvariant() -ne [string]$validation.DlssNr.Sha256) {
    throw 'Neural-input profile does not match the validated DLSSNR payload.'
}

[pscustomobject]@{
    InputSetId = [string]$manifest.inputSetId
    InputSetRoot = $root
    DlssNrVersion = [string]$validation.DlssNr.Version
    DlssNrSha256 = [string]$validation.DlssNr.Sha256
    FileCount = 3
    SourcePathsRetained = $false
    RedistributionAuthorized = $false
    Valid = $true
}
