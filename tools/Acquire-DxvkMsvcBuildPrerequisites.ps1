[CmdletBinding()]
param(
    [switch]$AllowNetwork,
    [switch]$Stage,
    [string]$InputManifest = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Backends\DxvkD3D11\toolchain-inputs.json'),
    [string]$DownloadRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\downloads\dxvk-msvc')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $root 'artifacts'))
$resolvedDownloadRoot = [IO.Path]::GetFullPath($DownloadRoot)
$inputManifestPath = [IO.Path]::GetFullPath($InputManifest)
$expectedInputManifestSha256 = '312ADA81DFE69B63948DD14469B74F5315ACCC0BAD78FD200DFF05FB5F97840A'
$allowedHosts = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
[void]$allowedHosts.Add('files.pythonhosted.org')
[void]$allowedHosts.Add('github.com')

if (-not $resolvedDownloadRoot.StartsWith($artifactsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing downloads outside the workspace artifacts directory: $resolvedDownloadRoot"
}
if (-not (Test-Path -LiteralPath $inputManifestPath -PathType Leaf)) {
    throw "Pinned toolchain input manifest is missing: $inputManifestPath"
}
if ((Get-FileHash -LiteralPath $inputManifestPath -Algorithm SHA256).Hash -ne $expectedInputManifestSha256) {
    throw 'Pinned toolchain input manifest changed; review it and update the acquisition script hash deliberately'
}

$inputs = Get-Content -Raw -LiteralPath $inputManifestPath | ConvertFrom-Json
if ($inputs.policy.automaticDownload -or $inputs.policy.systemInstall -or $inputs.policy.gameInstall) {
    throw 'Pinned toolchain input policy unexpectedly permits automatic download or installation'
}
if (-not $AllowNetwork) {
    throw 'Network acquisition is disabled by default. Re-run explicitly with -AllowNetwork after reviewing the pinned manifest.'
}

function Assert-PinnedInput {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][string]$Sha256
    )

    $uri = [Uri]$Url
    if ($uri.Scheme -ne 'https' -or -not $allowedHosts.Contains($uri.Host)) {
        throw "Pinned input URL is not on the HTTPS allowlist: $Url"
    }
    if ([IO.Path]::GetFileName($FileName) -ne $FileName) {
        throw "Pinned input filename is not a basename: $FileName"
    }
    if ($Sha256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw "Pinned input is missing a valid SHA-256: $FileName"
    }
}

function Get-PinnedFile {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][string]$Sha256,
        [Nullable[long]]$ExpectedSize
    )

    Assert-PinnedInput $Url $FileName $Sha256
    $destination = Join-Path $resolvedDownloadRoot $FileName
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        $existingHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        if ($existingHash -ne $Sha256.ToUpperInvariant()) {
            throw "Refusing to overwrite an existing file with the wrong hash: $destination"
        }
        if ($ExpectedSize.HasValue -and (Get-Item -LiteralPath $destination).Length -ne $ExpectedSize.Value) {
            throw "Existing pinned input has the wrong byte length: $destination"
        }
        return [pscustomobject]@{ Path = $destination; Downloaded = $false; Sha256 = $existingHash }
    }

    New-Item -ItemType Directory -Force -Path $resolvedDownloadRoot | Out-Null
    $partial = Join-Path $resolvedDownloadRoot ('.partial-' + [guid]::NewGuid().ToString('N'))
    try {
        Invoke-WebRequest -Uri $Url -OutFile $partial -UseBasicParsing
        if ($ExpectedSize.HasValue -and (Get-Item -LiteralPath $partial).Length -ne $ExpectedSize.Value) {
            throw "Downloaded pinned input has the wrong byte length: $FileName"
        }
        $actualHash = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash
        if ($actualHash -ne $Sha256.ToUpperInvariant()) {
            throw "Downloaded pinned input SHA-256 mismatch for $FileName`: expected $Sha256, got $actualHash"
        }
        Move-Item -LiteralPath $partial -Destination $destination
        return [pscustomobject]@{ Path = $destination; Downloaded = $true; Sha256 = $actualHash }
    }
    finally {
        if (Test-Path -LiteralPath $partial -PathType Leaf) {
            Remove-Item -LiteralPath $partial -Force
        }
    }
}

$meson = Get-PinnedFile `
    -Url $inputs.meson.url `
    -FileName $inputs.meson.fileName `
    -Sha256 $inputs.meson.sha256 `
    -ExpectedSize ([long]$inputs.meson.sizeBytes)
$glslang = Get-PinnedFile `
    -Url $inputs.glslangValidator.archiveUrl `
    -FileName $inputs.glslangValidator.archiveFileName `
    -Sha256 $inputs.glslangValidator.archiveSha256

$acquisitionManifest = [ordered]@{
    Schema = 1
    InputManifest = $inputManifestPath
    InputManifestSha256 = $expectedInputManifestSha256
    Files = @(
        [ordered]@{ Name = $inputs.meson.fileName; Path = $meson.Path; Sha256 = $meson.Sha256; Downloaded = $meson.Downloaded },
        [ordered]@{ Name = $inputs.glslangValidator.archiveFileName; Path = $glslang.Path; Sha256 = $glslang.Sha256; Downloaded = $glslang.Downloaded }
    )
    NetworkExplicitlyAllowed = $true
    SystemInstalled = $false
    GameInstalled = $false
}
$acquisitionManifestPath = Join-Path $resolvedDownloadRoot 'manifest.json'
$acquisitionManifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $acquisitionManifestPath -Encoding utf8

$stageResult = $null
if ($Stage) {
    $stageScript = Join-Path $PSScriptRoot 'Stage-DxvkMsvcBuildPrerequisites.ps1'
    $stageResult = & $stageScript `
        -MesonWheel $meson.Path `
        -GlslangArchive $glslang.Path `
        -ExpectedMesonSha256 $inputs.meson.sha256 `
        -ExpectedGlslangArchiveSha256 $inputs.glslangValidator.archiveSha256 `
        -InputManifest $inputManifestPath
}

[pscustomobject]@{
    DownloadRoot = $resolvedDownloadRoot
    ManifestPath = $acquisitionManifestPath
    MesonPath = $meson.Path
    GlslangArchivePath = $glslang.Path
    Staged = [bool]$Stage
    StageResult = $stageResult
    SystemInstalled = $false
    GameInstalled = $false
}
