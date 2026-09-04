[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $RenoDxAddonPath,
    [Parameter(Mandatory)][string] $NvngxDlssPath,
    [Parameter(Mandatory)][string] $NvngxDlssNrPath,
    [Parameter(Mandatory)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedRenoDxSha256,
    [Parameter(Mandatory)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedDlssSha256,
    [Parameter(Mandatory)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedDlssNrSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-InputFile {
    param([string] $Path, [string] $Description)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "$Description is not a file: $resolved"
    }
    return $resolved
}

function Get-Sha256Upper {
    param([string] $Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Get-PeMachine {
    param([string] $Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x88 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) {
        throw "Expected a Windows PE image: $Path"
    }
    $pe = [BitConverter]::ToInt32($bytes, 0x3c)
    if ($pe -lt 0 -or $pe + 6 -gt $bytes.Length -or $bytes[$pe] -ne 0x50 -or $bytes[$pe + 1] -ne 0x45) {
        throw "Invalid Windows PE header: $Path"
    }
    return [BitConverter]::ToUInt16($bytes, $pe + 4)
}

function Get-NormalizedVersion {
    param([string] $Path)
    $raw = [string](Get-Item -LiteralPath $Path).VersionInfo.FileVersion
    $normalized = ($raw -replace ',', '.' -replace '\s', '')
    $match = [regex]::Match($normalized, '^\d+(?:\.\d+){1,3}')
    if (-not $match.Success) { return '' }
    return $match.Value
}

function Assert-NvidiaSignature {
    param([string] $Path, [string] $Description)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid) {
        throw "$Description Authenticode status must be Valid; got $($signature.Status)."
    }
    if ($null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch '(?i)(^|,\s*)O=NVIDIA Corporation(,|$)') {
        throw "$Description is not signed by NVIDIA Corporation."
    }
    return $signature
}

$renoDx = Resolve-InputFile $RenoDxAddonPath 'RenoDX DLSS5 add-on'
$dlss = Resolve-InputFile $NvngxDlssPath 'NVIDIA DLSS runtime'
$dlssNr = Resolve-InputFile $NvngxDlssNrPath 'NVIDIA DLSS Neural Rendering runtime'

if ((Split-Path -Leaf $renoDx) -notmatch '(?i)^renodx-dlss5.*\.addon64$') {
    throw "RenoDX add-on filename must match renodx-dlss5*.addon64: $renoDx"
}
if ((Split-Path -Leaf $dlss) -ine 'nvngx_dlss.dll') {
    throw "DLSS runtime must be named nvngx_dlss.dll: $dlss"
}
if ((Split-Path -Leaf $dlssNr) -ine 'nvngx_dlssnr.dll') {
    throw "Neural Rendering runtime must be named nvngx_dlssnr.dll: $dlssNr"
}
foreach ($entry in @(
    @($renoDx, 'RenoDX DLSS5 add-on'),
    @($dlss, 'NVIDIA DLSS runtime'),
    @($dlssNr, 'NVIDIA DLSS Neural Rendering runtime')
)) {
    if ((Get-PeMachine $entry[0]) -ne 0x8664) { throw "$($entry[1]) must be x64: $($entry[0])" }
}

$renoDxHash = Get-Sha256Upper $renoDx
$dlssHash = Get-Sha256Upper $dlss
$dlssNrHash = Get-Sha256Upper $dlssNr
if ($renoDxHash -ne $ExpectedRenoDxSha256.ToUpperInvariant()) { throw "RenoDX add-on SHA-256 mismatch: $renoDxHash" }
if ($dlssHash -ne $ExpectedDlssSha256.ToUpperInvariant()) { throw "NVIDIA DLSS runtime SHA-256 mismatch: $dlssHash" }
if ($dlssNrHash -ne $ExpectedDlssNrSha256.ToUpperInvariant()) { throw "NVIDIA Neural Rendering runtime SHA-256 mismatch: $dlssNrHash" }

$dlssSignature = Assert-NvidiaSignature $dlss 'NVIDIA DLSS runtime'
$dlssNrSignature = Assert-NvidiaSignature $dlssNr 'NVIDIA DLSS Neural Rendering runtime'
$dlssVersion = Get-NormalizedVersion $dlss
$dlssNrVersion = Get-NormalizedVersion $dlssNr
if ([string]::IsNullOrWhiteSpace($dlssVersion) -or ([version]$dlssVersion) -lt [version]'3.1.13.0') {
    throw "NVIDIA DLSS runtime must be version 3.1.13.0 or newer; got '$dlssVersion'."
}
if ($dlssNrVersion -ne '310.8.0.0') {
    throw "NVIDIA Neural Rendering runtime must be version 310.8.0.0; got '$dlssNrVersion'."
}

$renoDxSignature = Get-AuthenticodeSignature -LiteralPath $renoDx
[pscustomobject]@{
    Valid = $true
    RenoDx = [pscustomobject]@{
        FileName = Split-Path -Leaf $renoDx
        Sha256 = $renoDxHash
        Version = Get-NormalizedVersion $renoDx
        SignatureStatus = [string]$renoDxSignature.Status
    }
    Dlss = [pscustomobject]@{
        FileName = Split-Path -Leaf $dlss
        Sha256 = $dlssHash
        Version = $dlssVersion
        SignatureStatus = [string]$dlssSignature.Status
        Signer = $dlssSignature.SignerCertificate.Subject
    }
    DlssNr = [pscustomobject]@{
        FileName = Split-Path -Leaf $dlssNr
        Sha256 = $dlssNrHash
        Version = $dlssNrVersion
        SignatureStatus = [string]$dlssNrSignature.Status
        Signer = $dlssNrSignature.SignerCertificate.Subject
    }
}
