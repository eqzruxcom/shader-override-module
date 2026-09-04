[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildManifestPath,
    [Parameter(Mandatory)][string]$SmokeResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$patchPath = Join-Path $workspace 'src\Backends\DxvkD3D11\patches\dxvk-adeda663-d3d11-shader-overrides.patch'
$pinnedRevision = 'adeda6639a09ad1b6a1b7c4158a781ffaf68947d'

function Resolve-ArtifactFile {
    param([string]$Path, [string]$Context)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (-not $resolved.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Context must be below the workspace artifacts directory: $resolved"
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "$Context is not a file: $resolved"
    }
    $resolved
}

function Get-Sha256 {
    param([string]$Path)
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Assert-Sha256 {
    param([string]$Value, [string]$Context)
    if ($Value -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "$Context is not SHA-256: $Value"
    }
}

function Assert-X64Pe {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x88 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) {
        throw "Runtime DLL is not a PE image: $Path"
    }
    $pe = [BitConverter]::ToInt32($bytes, 0x3c)
    if ($pe -lt 0 -or $pe + 6 -gt $bytes.Length -or
        $bytes[$pe] -ne 0x50 -or $bytes[$pe + 1] -ne 0x45 -or
        $bytes[$pe + 2] -ne 0 -or $bytes[$pe + 3] -ne 0) {
        throw "Runtime DLL has an invalid PE header: $Path"
    }
    if ([BitConverter]::ToUInt16($bytes, $pe + 4) -ne 0x8664) {
        throw "Runtime DLL is not x64: $Path"
    }
}

$buildManifestFull = Resolve-ArtifactFile $BuildManifestPath 'DXVK build manifest'
$smokeResultFull = Resolve-ArtifactFile $SmokeResultPath 'DXVK smoke result'
$build = Get-Content -Raw -LiteralPath $buildManifestFull | ConvertFrom-Json
$smoke = Get-Content -Raw -LiteralPath $smokeResultFull | ConvertFrom-Json

if ($build.Schema -ne 1 -or $build.Backend -ne 'DXVK D3D11 shader replacement' -or
    $build.Architecture -ne 'x64' -or $build.SourceRevision -ne $pinnedRevision -or
    $build.Installed -ne $false -or $build.RuntimeEligible -ne $false) {
    throw 'DXVK build evidence does not match the pinned, non-installing x64 contract.'
}

$patchHash = Get-Sha256 $patchPath
if ([string]$build.PatchSha256 -ne $patchHash) {
    throw 'DXVK build evidence does not identify the current reviewed patch.'
}
foreach ($property in @('MesonWheelSha256', 'GlslangArchiveSha256',
                         'GlslangExecutableSha256', 'ToolchainInputManifestSha256',
                         'StagedToolchainManifestSha256')) {
    Assert-Sha256 ([string]$build.$property) "Build $property"
}

$runtimeFiles = [ordered]@{}
$buildFiles = @($build.Files)
if ($buildFiles.Count -ne 2) {
    throw 'DXVK build evidence must contain exactly d3d11.dll and dxgi.dll.'
}
foreach ($name in @('d3d11.dll', 'dxgi.dll')) {
    $matches = @($buildFiles | Where-Object { ([string]$_.Name).ToLowerInvariant() -eq $name })
    if ($matches.Count -ne 1) {
        throw "DXVK build evidence must contain exactly one $name."
    }
    Assert-Sha256 ([string]$matches[0].Sha256) "Build $name hash"
    $runtimePath = Resolve-ArtifactFile ([string]$matches[0].Path) "Build $name"
    if ((Get-Sha256 $runtimePath) -ne ([string]$matches[0].Sha256).ToUpperInvariant()) {
        throw "DXVK build $name hash mismatch."
    }
    Assert-X64Pe $runtimePath
    $runtimeFiles[$name] = $runtimePath
}

if ($smoke.Schema -ne 1 -or $smoke.Passed -ne $true -or $smoke.Installed -ne $false -or
    $smoke.CompatibleReplacementResult -ne 42 -or
    $smoke.MissingReplacementFallbackResult -ne 7 -or
    $smoke.CorruptReplacementFallbackResult -ne 7) {
    throw 'DXVK smoke evidence does not prove compatible load and fail-closed fallback.'
}
if ([string]$smoke.RuntimeD3D11Sha256 -ne (Get-Sha256 $runtimeFiles['d3d11.dll']) -or
    [string]$smoke.RuntimeDxgiSha256 -ne (Get-Sha256 $runtimeFiles['dxgi.dll'])) {
    throw 'DXVK smoke evidence does not identify the validated build outputs.'
}

$identity = [string]$smoke.ShaderIdentity
if ($identity -notmatch '^[0-9a-f]{16}-cs$') {
    throw "DXVK smoke identity is invalid: $identity"
}
$caseExpectations = [ordered]@{
    compatible = @($true, $false)
    missing = @($false, $false)
    corrupt = @($false, $true)
}
$cases = @($smoke.CaseEvidence)
if ($cases.Count -ne 3) {
    throw 'DXVK smoke evidence must contain exactly three case logs.'
}
$validatedLogs = [ordered]@{}
foreach ($caseName in $caseExpectations.Keys) {
    $matches = @($cases | Where-Object { [string]$_.Name -eq $caseName })
    if ($matches.Count -ne 1) {
        throw "DXVK smoke evidence must contain exactly one '$caseName' record."
    }
    $entry = $matches[0]
    $expected = $caseExpectations[$caseName]
    Assert-Sha256 ([string]$entry.LogSha256) "Smoke $caseName log hash"
    if ([bool]$entry.ReplacementLoaded -ne [bool]$expected[0] -or
        [bool]$entry.ReplacementRejected -ne [bool]$expected[1]) {
        throw "DXVK smoke '$caseName' flags do not match the required behavior."
    }
    $logPath = Resolve-ArtifactFile ([string]$entry.Log) "DXVK smoke '$caseName' log"
    if ((Get-Sha256 $logPath) -ne ([string]$entry.LogSha256).ToUpperInvariant()) {
        throw "DXVK smoke '$caseName' log hash mismatch."
    }
    $text = Get-Content -Raw -LiteralPath $logPath
    $loaded = 'D3D11: Loaded shader replacement ' + $identity + ' from'
    $rejected = 'D3D11: Rejecting shader replacement ' + $identity + ':'
    if ($caseName -eq 'compatible' -and (-not $text.Contains($loaded) -or $text.Contains($rejected))) {
        throw 'Compatible DXVK smoke log does not prove replacement acceptance.'
    }
    if ($caseName -eq 'missing' -and ($text.Contains($loaded) -or $text.Contains($rejected))) {
        throw 'Missing DXVK smoke log does not prove silent original fallback.'
    }
    if ($caseName -eq 'corrupt' -and (-not $text.Contains($rejected) -or $text.Contains($loaded))) {
        throw 'Corrupt DXVK smoke log does not prove rejection and original fallback.'
    }
    $validatedLogs[$caseName] = [ordered]@{
        Path = $logPath
        Sha256 = Get-Sha256 $logPath
    }
}

[pscustomobject]@{
    Valid = $true
    SourceRevision = $pinnedRevision
    BuildManifest = $buildManifestFull
    SmokeResult = $smokeResultFull
    RuntimeD3D11Sha256 = Get-Sha256 $runtimeFiles['d3d11.dll']
    RuntimeDxgiSha256 = Get-Sha256 $runtimeFiles['dxgi.dll']
    ShaderIdentity = $identity
    CaseLogs = $validatedLogs
    Installed = $false
    RuntimeEligible = $false
}
