[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $TransportBundleDirectory,
    [Parameter(Mandatory)][string] $NeuralInputSetDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')][string] $PackageId,
    [string] $OutputParent = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\fallout-new-vegas-dlss5-full-bundles')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$setAssertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5NeuralInputSet.ps1'
$fullStagePath = Join-Path $PSScriptRoot 'New-FalloutNewVegasDlss5FullBundle.ps1'
$fullAssertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5FullBundle.ps1'
$utf8 = [Text.UTF8Encoding]::new($false)
$validated = & $setAssertPath -InputSetDirectory $NeuralInputSetDirectory
$root = [IO.Path]::GetFullPath($validated.InputSetRoot)
$createdRoot = $null

function Get-Sha256Upper {
    param([string] $Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

try {
    $staged = & $fullStagePath `
        -TransportBundleDirectory $TransportBundleDirectory `
        -RenoDxAddonPath (Join-Path $root 'renodx-dlss5.addon64') `
        -NvngxDlssPath (Join-Path $root 'nvngx_dlss.dll') `
        -NvngxDlssNrPath (Join-Path $root 'nvngx_dlssnr.dll') `
        -PackageId $PackageId `
        -OutputParent $OutputParent
    $createdRoot = [IO.Path]::GetFullPath($staged.BundleRoot).TrimEnd('\')
    $sourceReceipt = Join-Path $root 'neural-input-set.json'
    $provenanceRelative = 'provenance/neural-input-set.json'
    $provenancePath = Join-Path $createdRoot $provenanceRelative.Replace('/', '\')
    Copy-Item -LiteralPath $sourceReceipt -Destination $provenancePath

    $manifestPath = Join-Path $createdRoot 'runtime-bundle.json'
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    foreach ($input in @($manifest.neuralInputs)) {
        $input.PSObject.Properties.Remove('sourcePath')
        $input | Add-Member -NotePropertyName inputSetId -NotePropertyValue ([string]$validated.InputSetId)
    }
    $manifest | Add-Member -NotePropertyName neuralInputSet -NotePropertyValue ([pscustomobject][ordered]@{
        inputSetId = [string]$validated.InputSetId
        manifest = $provenanceRelative
        manifestSha256 = Get-Sha256Upper $provenancePath
        sourcePathsRetained = $false
        redistributionAuthorized = $false
    })
    $provenanceRecord = [pscustomobject][ordered]@{
        relativePath = $provenanceRelative
        sha256 = Get-Sha256Upper $provenancePath
        sizeBytes = [long](Get-Item -LiteralPath $provenancePath).Length
    }
    $manifest.files = @($manifest.files) + $provenanceRecord
    [IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 10) + [Environment]::NewLine), $utf8)

    $result = & $fullAssertPath -BundleDirectory $createdRoot
    $result | Add-Member -NotePropertyName NeuralInputSetId -NotePropertyValue ([string]$validated.InputSetId)
    $result | Add-Member -NotePropertyName NeuralInputSourcePathsRetained -NotePropertyValue $false
    return $result
}
catch {
    if ($null -ne $createdRoot -and (Test-Path -LiteralPath $createdRoot -PathType Container)) {
        Remove-Item -LiteralPath $createdRoot -Recurse -Force
    }
    throw
}
