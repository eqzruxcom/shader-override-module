[CmdletBinding()]
param([Parameter(Mandatory)][string] $BundleDirectory)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$bundleRoot = [IO.Path]::GetFullPath($BundleDirectory).TrimEnd('\')
$manifestPath = Join-Path $bundleRoot 'runtime-bundle.json'
if (-not $bundleRoot.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing full-bundle validation outside workspace artifacts: $bundleRoot" }
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Full New Vegas runtime-bundle.json is missing: $manifestPath" }

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
if ($manifest.schemaVersion -ne 1 -or $manifest.adapter.id -ne 'FalloutNewVegas' -or $manifest.adapter.executable -ne 'FalloutNV.exe') { throw 'Full bundle does not identify the New Vegas adapter.' }
if ($manifest.adapter.executableArchitecture -ne 'x86' -or $manifest.adapter.sourceApi -ne 'D3D9' -or $manifest.adapter.translatedApi -ne 'Vulkan') { throw 'Full bundle renderer contract is invalid.' }
if ($manifest.mode -ne 'full-neural-candidate' -or $manifest.configuration.feederMode -ne 2 -or $manifest.configuration.asyncHome -ne $true -or $manifest.configuration.motionProviderId -ne 3 -or $manifest.configuration.neuralConsumer -ne 'RenoDX DLSS5') { throw 'Full bundle configuration is invalid.' }
if (@($manifest.configuration.explicitLayers).Count -ne 2 -or @($manifest.configuration.explicitLayers) -notcontains 'VK_LAYER_reshade' -or @($manifest.configuration.explicitLayers) -notcontains 'VK_LAYER_feed_vk' -or $manifest.configuration.dxvkAllowFse -ne $false) { throw 'Full bundle Vulkan-layer configuration is invalid.' }
if ($manifest.policy.installed -ne $false -or $manifest.policy.runtimeEligible -ne $false -or $manifest.policy.automaticInstall -ne $false -or $manifest.policy.gameDirectoryTouched -ne $false -or $manifest.policy.registryTouched -ne $false -or $manifest.policy.frameGenerationIncluded -ne $false) { throw 'Full bundle policy overstates deployment or includes frame generation.' }
if ($manifest.gates.parentTransportBundleValidated -ne $true -or $manifest.gates.componentArchitectureValidated -ne $true -or $manifest.gates.bundleValidationPassed -ne $true -or $manifest.gates.gameInstalled -ne $false -or $manifest.gates.liveTransportPassed -ne $false -or $manifest.gates.neuralConsumerPresent -ne $true -or $manifest.gates.ngxRuntimePresent -ne $true -or $manifest.gates.fullDlss5Passed -ne $false) { throw 'Full bundle gates do not match an offline neural candidate.' }

$records = @($manifest.files)
$recordPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($record in $records) {
    $relative = [string]$record.relativePath
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative.Contains(':') -or $relative -match '(^|[\\/])\.\.([\\/]|$)') { throw "Unsafe full-bundle path: $relative" }
    if (-not $recordPaths.Add($relative)) { throw "Duplicate full-bundle file record: $relative" }
    $path = Join-Path $bundleRoot $relative.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Listed full-bundle file is missing: $relative" }
    if ((Get-Sha256Upper $path) -ne ([string]$record.sha256).ToUpperInvariant()) { throw "Full-bundle file hash mismatch: $relative" }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$record.sizeBytes) { throw "Full-bundle file size mismatch: $relative" }
}
$actual = @(Get-ChildItem -LiteralPath $bundleRoot -Recurse -File | Where-Object { $_.FullName -ne $manifestPath } | ForEach-Object { $_.FullName.Substring($bundleRoot.Length + 1).Replace('\', '/') })
$unlisted = @($actual | Where-Object { -not $recordPaths.Contains($_) })
if ($unlisted.Count) { throw ('Full bundle contains unlisted file(s): ' + ($unlisted -join ', ')) }

$parentRelative = [string]$manifest.parentTransport.manifest
if ($parentRelative -ne 'provenance/transport-runtime-bundle.json' -or -not $recordPaths.Contains($parentRelative)) { throw 'Full bundle is missing its parent transport manifest.' }
$parentPath = Join-Path $bundleRoot $parentRelative.Replace('/', '\')
if ((Get-Sha256Upper $parentPath) -ne ([string]$manifest.parentTransport.manifestSha256).ToUpperInvariant()) { throw 'Parent transport manifest hash mismatch.' }
$parent = Get-Content -Raw -LiteralPath $parentPath | ConvertFrom-Json
if ($parent.schemaVersion -ne 1 -or $parent.adapter.id -ne 'FalloutNewVegas' -or $parent.mode -ne 'transport-only' -or $parent.packageId -ne $manifest.parentTransport.packageId -or $parent.configuration.feederMode -ne 1 -or $parent.policy.runtimeEligible -ne $false -or $parent.gates.bundleValidationPassed -ne $true) { throw 'Parent manifest is not a validated transport-only package.' }
foreach ($parentRecord in @($parent.files | Where-Object { [string]$_.relativePath -ne 'README-TRANSPORT.md' })) {
    $relative = [string]$parentRecord.relativePath
    if (-not $recordPaths.Contains($relative)) { throw "Full bundle omitted parent transport payload: $relative" }
    if ($relative -ne 'dlss5-feed.cfg') {
        $currentRecord = @($records | Where-Object { [string]$_.relativePath -ieq $relative })
        if ($currentRecord.Count -ne 1 -or ([string]$currentRecord[0].sha256).ToUpperInvariant() -ne ([string]$parentRecord.sha256).ToUpperInvariant()) {
            throw "Full bundle changed immutable parent transport payload: $relative"
        }
    }
}

$consumerFiles = @(Get-ChildItem -LiteralPath (Join-Path $bundleRoot 'host64') -File | Where-Object { $_.Name -match '(?i)^renodx-dlss5.*\.addon64$' })
if ($consumerFiles.Count -ne 1) { throw 'Full bundle must contain exactly one RenoDX DLSS5 add-on.' }
if (Get-ChildItem -LiteralPath (Join-Path $bundleRoot 'host64') -File | Where-Object { $_.Name -match '(?i)^(deep-fried-chicken.*|alexs-toolkit.*|renodx-dlss\.addon64)$' }) { throw 'Full bundle contains a conflicting neural consumer.' }
$consumerRelative = 'host64/' + $consumerFiles[0].Name
if ($manifest.configuration.neuralConsumerFile -ne $consumerRelative -or -not $recordPaths.Contains($consumerRelative)) { throw 'Manifest does not identify the sole RenoDX consumer.' }

foreach ($relative in @($consumerRelative, 'host64/nvngx_dlss.dll', 'host64/nvngx_dlssnr.dll')) {
    if (-not $recordPaths.Contains($relative)) { throw "Required neural file is not inventoried: $relative" }
    if ((Get-PeMachine (Join-Path $bundleRoot $relative.Replace('/', '\'))) -ne 0x8664) { throw "Required neural file is not x64: $relative" }
}
if (Get-ChildItem -LiteralPath $bundleRoot -Recurse -File | Where-Object { $_.Name -match '(?i)^(nvngx_dlssg|sl\.dlss_g|sl\.interposer)\.dll$' }) { throw 'Full neural-rendering bundle unexpectedly contains frame-generation/Streamline files.' }

$feedConfig = Get-Content -Raw -LiteralPath (Join-Path $bundleRoot 'dlss5-feed.cfg')
foreach ($expected in @('(?m)^mode=2\s*$', '(?m)^async_home=1\s*$', '(?m)^host_window=0\s*$', '(?m)^warmup_rebuild=180\s*$')) {
    if ($feedConfig -notmatch $expected) { throw "Full bundle Feeder config is missing: $expected" }
}
$rootIni = Get-Content -Raw -LiteralPath (Join-Path $bundleRoot 'ReShade.ini')
if ($rootIni -match '(?im)^LoadFromDllMain\s*=') { throw 'Vulkan game-side ReShade.ini must not use LoadFromDllMain.' }

[pscustomobject]@{
    PackageId = [string]$manifest.packageId
    BundleRoot = $bundleRoot
    FileCount = $records.Count
    Mode = [string]$manifest.mode
    NeuralConsumerFile = $consumerRelative
    Valid = $true
    Installed = $false
    RuntimeEligible = $false
    FrameGenerationIncluded = $false
}
