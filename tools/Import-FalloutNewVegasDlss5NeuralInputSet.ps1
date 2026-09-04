[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $RenoDxAddonPath,
    [Parameter(Mandatory)][string] $NvngxDlssPath,
    [Parameter(Mandatory)][string] $NvngxDlssNrPath,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')][string] $InputSetId,
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedRenoDxSha256 = 'A2973900531D58FF7BEB21172828095BCE2281BC2A81E82191F9D89C983D6A21',
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedDlssSha256 = 'BE6E434A94CA32499515EB62CA0E6C274526055D568D0426E4C652DCDFB6EE6E',
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedDlssNrSha256 = 'E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E',
    [string] $OutputParent = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\fallout-new-vegas-dlss5-neural-inputs')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$outputParentFull = [IO.Path]::GetFullPath($OutputParent).TrimEnd('\')
$finalRoot = Join-Path $outputParentFull $InputSetId
$temporaryRoot = Join-Path $outputParentFull ('.staging-' + $InputSetId + '-' + [Guid]::NewGuid().ToString('N'))
$inputAssertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5NeuralInputs.ps1'
$setAssertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5NeuralInputSet.ps1'
$utf8 = [Text.UTF8Encoding]::new($false)
$moved = $false

if (-not ($outputParentFull -eq $artifactsRoot -or $outputParentFull.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase))) {
    throw "Refusing neural-input output outside workspace artifacts: $outputParentFull"
}
if (Test-Path -LiteralPath $finalRoot) { throw "Refusing to overwrite an existing neural-input set: $finalRoot" }
$reviewedHashes = @(
    'A2973900531D58FF7BEB21172828095BCE2281BC2A81E82191F9D89C983D6A21',
    'BE6E434A94CA32499515EB62CA0E6C274526055D568D0426E4C652DCDFB6EE6E',
    'E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E'
)
if ($ExpectedRenoDxSha256.ToUpperInvariant() -ne $reviewedHashes[0] -or $ExpectedDlssSha256.ToUpperInvariant() -ne $reviewedHashes[1] -or $ExpectedDlssNrSha256.ToUpperInvariant() -ne $reviewedHashes[2]) { throw 'Requested hashes do not match the reviewed native-resolution neural-input profile.' }

function Get-Sha256Upper {
    param([string] $Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

$validated = & $inputAssertPath `
    -RenoDxAddonPath $RenoDxAddonPath `
    -NvngxDlssPath $NvngxDlssPath `
    -NvngxDlssNrPath $NvngxDlssNrPath `
    -ExpectedRenoDxSha256 $ExpectedRenoDxSha256 `
    -ExpectedDlssSha256 $ExpectedDlssSha256 `
    -ExpectedDlssNrSha256 $ExpectedDlssNrSha256

try {
    [IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
    $copies = @(
        [ordered]@{ role = 'renoDxDlss5'; source = (Resolve-Path -LiteralPath $RenoDxAddonPath).Path; relativePath = 'renodx-dlss5.addon64'; validation = $validated.RenoDx },
        [ordered]@{ role = 'nvngxDlss'; source = (Resolve-Path -LiteralPath $NvngxDlssPath).Path; relativePath = 'nvngx_dlss.dll'; validation = $validated.Dlss },
        [ordered]@{ role = 'nvngxDlssNr'; source = (Resolve-Path -LiteralPath $NvngxDlssNrPath).Path; relativePath = 'nvngx_dlssnr.dll'; validation = $validated.DlssNr }
    )
    foreach ($copy in $copies) { Copy-Item -LiteralPath $copy.source -Destination (Join-Path $temporaryRoot $copy.relativePath) }

    # Revalidate the copies, not just the original paths, before recording the set.
    $copiedValidation = & $inputAssertPath `
        -RenoDxAddonPath (Join-Path $temporaryRoot 'renodx-dlss5.addon64') `
        -NvngxDlssPath (Join-Path $temporaryRoot 'nvngx_dlss.dll') `
        -NvngxDlssNrPath (Join-Path $temporaryRoot 'nvngx_dlssnr.dll') `
        -ExpectedRenoDxSha256 $ExpectedRenoDxSha256 `
        -ExpectedDlssSha256 $ExpectedDlssSha256 `
        -ExpectedDlssNrSha256 $ExpectedDlssNrSha256

    $files = @($copies | ForEach-Object {
        $path = Join-Path $temporaryRoot $_.relativePath
        $v = $_.validation
        [ordered]@{
            role = $_.role
            relativePath = $_.relativePath
            sha256 = Get-Sha256Upper $path
            sizeBytes = [long](Get-Item -LiteralPath $path).Length
            version = [string]$v.Version
            signatureStatus = [string]$v.SignatureStatus
            signer = if ($v.PSObject.Properties.Name -contains 'Signer') { [string]$v.Signer } else { $null }
        }
    })
    $manifest = [ordered]@{
        schemaVersion = 1
        kind = 'fallout-new-vegas-dlss5-neural-input-set'
        inputSetId = $InputSetId
        createdUtc = [DateTime]::UtcNow.ToString('o')
        targetAdapter = 'FalloutNewVegas'
        profile = [ordered]@{
            name = 'RenoDX-DLSS5-NR-310.8-native-resolution'
            dlssNrVersion = [string]$copiedValidation.DlssNr.Version
            dlssNrSha256 = [string]$copiedValidation.DlssNr.Sha256
            resolutionContract = 'DLAA-1:1-carrier-no-upscaling'
        }
        files = $files
        policy = [ordered]@{
            operatorSupplied = $true
            sourcePathsRetained = $false
            redistributionAuthorized = $false
            installable = $false
        }
    }
    [IO.File]::WriteAllText((Join-Path $temporaryRoot 'neural-input-set.json'), (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine), $utf8)

    [IO.Directory]::CreateDirectory($outputParentFull) | Out-Null
    [IO.Directory]::Move($temporaryRoot, $finalRoot)
    $moved = $true
    $result = & $setAssertPath -InputSetDirectory $finalRoot
    Write-Host "PASS: imported authenticated neural-input set '$InputSetId' without retaining source paths."
    return $result
}
catch {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
    if ($moved -and (Test-Path -LiteralPath $finalRoot -PathType Container)) { Remove-Item -LiteralPath $finalRoot -Recurse -Force }
    throw
}
