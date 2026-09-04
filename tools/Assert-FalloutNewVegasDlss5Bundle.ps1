[CmdletBinding()]
param([Parameter(Mandatory)][string] $BundleDirectory)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$bundleRoot = [IO.Path]::GetFullPath($BundleDirectory).TrimEnd('\')
$manifestPath = Join-Path $bundleRoot 'runtime-bundle.json'

if (-not $bundleRoot.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to validate a New Vegas bundle outside workspace artifacts: $bundleRoot"
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "New Vegas runtime-bundle.json is missing: $manifestPath"
}

function Get-Sha256Upper {
    param([string] $Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Get-PeMachine {
    param([string] $Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x88 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) { throw "Not a PE image: $Path" }
    $pe = [BitConverter]::ToInt32($bytes, 0x3c)
    if ($pe -lt 0 -or $pe + 6 -gt $bytes.Length -or $bytes[$pe] -ne 0x50 -or $bytes[$pe + 1] -ne 0x45) { throw "Invalid PE header: $Path" }
    return [BitConverter]::ToUInt16($bytes, $pe + 4)
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.adapter.id -ne 'FalloutNewVegas' -or $manifest.adapter.executable -ne 'FalloutNV.exe') {
    throw 'Bundle does not identify the Fallout: New Vegas adapter contract.'
}
if ($manifest.adapter.executableArchitecture -ne 'x86' -or $manifest.adapter.sourceApi -ne 'D3D9' -or $manifest.adapter.translatedApi -ne 'Vulkan') {
    throw 'Bundle renderer or architecture contract is invalid.'
}
if ($manifest.mode -ne 'transport-only' -or $manifest.configuration.feederMode -ne 1 -or $manifest.configuration.motionProviderId -ne 3) {
    throw 'Bundle is not the guarded transport-only Lumenite configuration.'
}
if (@($manifest.configuration.explicitLayers).Count -ne 2 -or @($manifest.configuration.explicitLayers) -notcontains 'VK_LAYER_reshade' -or @($manifest.configuration.explicitLayers) -notcontains 'VK_LAYER_feed_vk') {
    throw 'Bundle does not declare both required explicit Vulkan layers.'
}
if ($manifest.policy.installed -ne $false -or $manifest.policy.runtimeEligible -ne $false -or $manifest.policy.automaticInstall -ne $false -or $manifest.policy.gameDirectoryTouched -ne $false -or $manifest.policy.registryTouched -ne $false) {
    throw 'Bundle policy must remain non-installing, non-runtime-eligible, and registry-free.'
}
if ($manifest.gates.componentArchitectureValidated -ne $true -or $manifest.gates.bundleValidationPassed -ne $true -or $manifest.gates.liveTransportPassed -ne $false -or $manifest.gates.neuralConsumerPresent -ne $false -or $manifest.gates.ngxRuntimePresent -ne $false -or $manifest.gates.fullDlss5Passed -ne $false) {
    throw 'Bundle gates overstate the current transport-only evidence.'
}

$records = @($manifest.files)
if ($records.Count -lt 15) { throw 'Bundle file inventory is unexpectedly small.' }
$recordPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($record in $records) {
    $relative = [string]$record.relativePath
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative.Contains(':') -or $relative -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Unsafe bundle-relative path: $relative"
    }
    if (-not $recordPaths.Add($relative)) { throw "Duplicate bundle file record: $relative" }
    $path = Join-Path $bundleRoot $relative.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Listed bundle file is missing: $relative" }
    if ((Get-Sha256Upper $path) -ne ([string]$record.sha256).ToUpperInvariant()) { throw "Bundle file hash mismatch: $relative" }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$record.sizeBytes) { throw "Bundle file size mismatch: $relative" }
}

$actualPaths = @(
    Get-ChildItem -LiteralPath $bundleRoot -Recurse -File |
        Where-Object { $_.FullName -ne $manifestPath } |
        ForEach-Object { $_.FullName.Substring($bundleRoot.Length + 1).Replace('\', '/') }
)
$missingRecords = @($actualPaths | Where-Object { -not $recordPaths.Contains($_) })
if ($missingRecords.Count) { throw ('Bundle contains unlisted file(s): ' + ($missingRecords -join ', ')) }

$required = @(
    'd3d9.dll',
    'dxvk.conf',
    'dlss5-feed.addon32',
    'dlss5-feed.cfg',
    'ReShade.ini',
    'ReShadePreset.ini',
    'Launch-FalloutNV-DLSS5.cmd',
    'README-TRANSPORT.md',
    'host64/dlss5-feed-host64.exe',
    'host64/dxgi.dll',
    'host64/ReShade.ini',
    'layers/x86/ReShade32.dll',
    'layers/x86/ReShade32.json',
    'layers/x86/VkLayer_feed_vk32.dll',
    'layers/x86/VkLayer_feed_vk32.json',
    'reshade-shaders/Shaders/DLSS5_Feed.fx',
    'reshade-shaders/Shaders/lumenite_Kernel.fx',
    'reshade-shaders/Shaders/ReShade.fxh'
)
foreach ($relative in $required) {
    if (-not $recordPaths.Contains($relative)) { throw "Required bundle file is not inventoried: $relative" }
}

foreach ($relative in @('d3d9.dll', 'dlss5-feed.addon32', 'layers/x86/ReShade32.dll', 'layers/x86/VkLayer_feed_vk32.dll')) {
    if ((Get-PeMachine (Join-Path $bundleRoot $relative.Replace('/', '\'))) -ne 0x014c) { throw "Required x86 binary has the wrong architecture: $relative" }
}
foreach ($relative in @('host64/dlss5-feed-host64.exe', 'host64/dxgi.dll')) {
    if ((Get-PeMachine (Join-Path $bundleRoot $relative.Replace('/', '\'))) -ne 0x8664) { throw "Required x64 binary has the wrong architecture: $relative" }
}

$rootIni = Get-Content -Raw -LiteralPath (Join-Path $bundleRoot 'ReShade.ini')
if ($rootIni -match '(?im)^LoadFromDllMain\s*=') { throw 'Vulkan-layer ReShade.ini must not use LoadFromDllMain.' }
if ($rootIni -notmatch '(?im)^AddonPath=\.\\\s*$') { throw 'Vulkan-layer ReShade.ini is missing AddonPath=.\.' }
$preset = Get-Content -Raw -LiteralPath (Join-Path $bundleRoot 'ReShadePreset.ini')
if ($preset -notmatch '(?m)^Techniques=Lumenite_Kernel@lumenite_Kernel\.fx,DLSS5_Feed@DLSS5_Feed\.fx\s*$' -or $preset -notmatch '(?m)^PreprocessorDefinitions=DLSS5_MV_PROVIDER=3\s*$') {
    throw 'ReShade preset does not enable Lumenite Kernel before DLSS5 Feed with provider 3.'
}
$feedConfig = Get-Content -Raw -LiteralPath (Join-Path $bundleRoot 'dlss5-feed.cfg')
if ($feedConfig -notmatch '(?m)^mode=1\s*$' -or $feedConfig -notmatch '(?m)^async_home=0\s*$') {
    throw 'Feeder config is not a deterministic same-frame transport test.'
}
$launcher = Get-Content -Raw -LiteralPath (Join-Path $bundleRoot 'Launch-FalloutNV-DLSS5.cmd')
if ($launcher -notmatch 'VK_LAYER_reshade;VK_LAYER_feed_vk' -or $launcher -notmatch 'FalloutNV\.exe') {
    throw 'Launcher does not enable both local x86 layers for FalloutNV.exe.'
}
foreach ($file in Get-ChildItem -LiteralPath $bundleRoot -Recurse -File) {
    if ($file.Name -match '(?i)^(nvngx_dlss(nr|g)|renodx-dlss5.*|deep-fried-chicken.*|sl\.dlss_g|sl\.interposer)\.(dll|addon64)$') {
        throw "Transport-only bundle unexpectedly contains $($file.Name)"
    }
}

[pscustomobject]@{
    PackageId = [string]$manifest.packageId
    BundleRoot = $bundleRoot
    FileCount = $records.Count
    Mode = [string]$manifest.mode
    Valid = $true
    Installed = $false
    RuntimeEligible = $false
}
