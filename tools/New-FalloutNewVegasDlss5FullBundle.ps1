[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $TransportBundleDirectory,
    [Parameter(Mandatory)][string] $RenoDxAddonPath,
    [Parameter(Mandatory)][string] $NvngxDlssPath,
    [Parameter(Mandatory)][string] $NvngxDlssNrPath,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')][string] $PackageId,
    [string] $OutputParent = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\fallout-new-vegas-dlss5-full-bundles')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$outputParentFull = [IO.Path]::GetFullPath($OutputParent).TrimEnd('\')
$finalRoot = Join-Path $outputParentFull $PackageId
$temporaryRoot = Join-Path $outputParentFull ('.staging-' + $PackageId + '-' + [Guid]::NewGuid().ToString('N'))
$transportAssertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5Bundle.ps1'
$fullAssertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5FullBundle.ps1'
$utf8 = [Text.UTF8Encoding]::new($false)
$moved = $false

function Get-Sha256Upper {
    param([string] $Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Resolve-InputFile {
    param([string] $Path, [string] $Description)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "$Description is not a file: $resolved" }
    return $resolved
}

function Get-PeMachine {
    param([string] $Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x88 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) { throw "Expected a Windows PE image: $Path" }
    $pe = [BitConverter]::ToInt32($bytes, 0x3c)
    if ($pe -lt 0 -or $pe + 6 -gt $bytes.Length -or $bytes[$pe] -ne 0x50 -or $bytes[$pe + 1] -ne 0x45) { throw "Invalid Windows PE header: $Path" }
    return [BitConverter]::ToUInt16($bytes, $pe + 4)
}

function Assert-X64Pe {
    param([string] $Path, [string] $Description)
    $machine = Get-PeMachine $Path
    if ($machine -ne 0x8664) { throw ('{0} must be x64; PE machine is 0x{1:X4}: {2}' -f $Description, $machine, $Path) }
}

if (-not ($outputParentFull -eq $artifactsRoot -or $outputParentFull.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase))) {
    throw "Refusing full New Vegas bundle output outside workspace artifacts: $outputParentFull"
}
if (Test-Path -LiteralPath $finalRoot) { throw "Refusing to overwrite an existing full New Vegas bundle: $finalRoot" }

$transportValidation = & $transportAssertPath -BundleDirectory $TransportBundleDirectory
$transportRoot = [IO.Path]::GetFullPath($transportValidation.BundleRoot).TrimEnd('\')
$transportManifestPath = Join-Path $transportRoot 'runtime-bundle.json'
$transportManifest = Get-Content -Raw -LiteralPath $transportManifestPath | ConvertFrom-Json

$renoDx = Resolve-InputFile $RenoDxAddonPath 'RenoDX DLSS5 add-on'
$dlss = Resolve-InputFile $NvngxDlssPath 'NVIDIA DLSS runtime'
$dlssNr = Resolve-InputFile $NvngxDlssNrPath 'NVIDIA DLSS neural-rendering runtime'
if ((Split-Path -Leaf $renoDx) -notmatch '(?i)^renodx-dlss5.*\.addon64$') {
    throw "RenoDX consumer filename must match renodx-dlss5*.addon64: $renoDx"
}
if ((Split-Path -Leaf $dlss) -ine 'nvngx_dlss.dll') { throw "DLSS runtime must be named nvngx_dlss.dll: $dlss" }
if ((Split-Path -Leaf $dlssNr) -ine 'nvngx_dlssnr.dll') { throw "Neural-rendering runtime must be named nvngx_dlssnr.dll: $dlssNr" }
Assert-X64Pe $renoDx 'RenoDX DLSS5 add-on'
Assert-X64Pe $dlss 'NVIDIA DLSS runtime'
Assert-X64Pe $dlssNr 'NVIDIA DLSS neural-rendering runtime'

try {
    [IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
    foreach ($entry in @($transportManifest.files)) {
        $relative = [string]$entry.relativePath
        if ($relative -eq 'README-TRANSPORT.md') { continue }
        $source = Join-Path $transportRoot $relative.Replace('/', '\')
        $destination = Join-Path $temporaryRoot $relative.Replace('/', '\')
        [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
    }

    $transportProvenance = Join-Path $temporaryRoot 'provenance\transport-runtime-bundle.json'
    [IO.Directory]::CreateDirectory((Split-Path -Parent $transportProvenance)) | Out-Null
    Copy-Item -LiteralPath $transportManifestPath -Destination $transportProvenance

    $consumerName = Split-Path -Leaf $renoDx
    Copy-Item -LiteralPath $renoDx -Destination (Join-Path $temporaryRoot ('host64\' + $consumerName))
    Copy-Item -LiteralPath $dlss -Destination (Join-Path $temporaryRoot 'host64\nvngx_dlss.dll')
    Copy-Item -LiteralPath $dlssNr -Destination (Join-Path $temporaryRoot 'host64\nvngx_dlssnr.dll')

    $feedConfigPath = Join-Path $temporaryRoot 'dlss5-feed.cfg'
    $feedConfig = [IO.File]::ReadAllText($feedConfigPath)
    foreach ($change in @(
        @('(?m)^mode=1\s*$', 'mode=2'),
        @('(?m)^async_home=0\s*$', 'async_home=1'),
        @('(?m)^host_window=1\s*$', 'host_window=0'),
        @('(?m)^warmup_rebuild=0\s*$', 'warmup_rebuild=180')
    )) {
        if ([regex]::Matches($feedConfig, $change[0]).Count -ne 1) { throw "Transport config does not contain one expected setting: $($change[0])" }
        $replacement = [regex]::new($change[0])
        $feedConfig = $replacement.Replace($feedConfig, $change[1], 1)
    }
    [IO.File]::WriteAllText($feedConfigPath, $feedConfig, $utf8)

    $readme = @'
# Fallout: New Vegas DLSS5 full-neural candidate

This non-installing candidate was promoted from a validated mode-1 transport
bundle. It contains exactly one x64 RenoDX DLSS5 neural consumer plus
`nvngx_dlss.dll` and `nvngx_dlssnr.dll`, and switches the Feeder to mode 2 with
the pipelined x86-to-x64 handoff enabled.

It is not runtime-eligible until the parent mode-1 bundle passes in New Vegas.
After installation, success requires all of the following retained evidence:

- ReShade attaches to the DXVK Vulkan device and both local layers load;
- the x86 Feeder and x64 host negotiate the same IPC version;
- Lumenite motion-vector and Generic Depth probes are non-empty;
- the host's ReShade log reports Feature 18 creation and successful inline
  Feature 18 evaluation;
- the neural-rendered frame counter grows while the game remains stable.

This package intentionally contains no DLSS Frame Generation/Streamline plugin.
Frame generation is a separate presentation-owning milestone.
'@
    [IO.File]::WriteAllText((Join-Path $temporaryRoot 'README-DLSS5.md'), $readme.TrimStart() + [Environment]::NewLine, $utf8)

    $files = @(
        Get-ChildItem -LiteralPath $temporaryRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
            [ordered]@{
                relativePath = $_.FullName.Substring($temporaryRoot.Length + 1).Replace('\', '/')
                sha256 = Get-Sha256Upper $_.FullName
                sizeBytes = [long]$_.Length
            }
        }
    )
    $manifest = [ordered]@{
        schemaVersion = 1
        packageId = $PackageId
        createdUtc = [DateTime]::UtcNow.ToString('o')
        adapter = [ordered]@{
            id = 'FalloutNewVegas'
            executable = 'FalloutNV.exe'
            executableArchitecture = 'x86'
            sourceApi = 'D3D9'
            translatedApi = 'Vulkan'
        }
        mode = 'full-neural-candidate'
        stack = @('FalloutNV.exe', 'DXVK x86 D3D9', 'Vulkan x86', 'ReShade explicit layer x86', 'DLSS5-Feeder addon32', 'DLSS5-Feeder host64', 'RenoDX DLSS5', 'NVIDIA NGX DLSS/Neural Rendering')
        parentTransport = [ordered]@{
            packageId = [string]$transportManifest.packageId
            manifest = 'provenance/transport-runtime-bundle.json'
            manifestSha256 = Get-Sha256Upper $transportProvenance
        }
        configuration = [ordered]@{
            feederMode = 2
            asyncHome = $true
            motionProvider = 'LumeniteFX Kernel'
            motionProviderId = 3
            neuralConsumer = 'RenoDX DLSS5'
            neuralConsumerFile = ('host64/' + $consumerName)
            explicitLayers = @('VK_LAYER_reshade', 'VK_LAYER_feed_vk')
            dxvkAllowFse = $false
        }
        neuralInputs = @(
            [ordered]@{ role = 'renoDxDlss5'; sourcePath = $renoDx; sha256 = Get-Sha256Upper $renoDx },
            [ordered]@{ role = 'nvngxDlss'; sourcePath = $dlss; sha256 = Get-Sha256Upper $dlss },
            [ordered]@{ role = 'nvngxDlssNr'; sourcePath = $dlssNr; sha256 = Get-Sha256Upper $dlssNr }
        )
        files = @($files)
        gates = [ordered]@{
            parentTransportBundleValidated = $true
            componentArchitectureValidated = $true
            bundleValidationPassed = $true
            gameInstalled = $false
            liveTransportPassed = $false
            neuralConsumerPresent = $true
            ngxRuntimePresent = $true
            fullDlss5Passed = $false
        }
        policy = [ordered]@{
            installed = $false
            runtimeEligible = $false
            automaticInstall = $false
            gameDirectoryTouched = $false
            registryTouched = $false
            frameGenerationIncluded = $false
        }
    }
    [IO.File]::WriteAllText((Join-Path $temporaryRoot 'runtime-bundle.json'), (($manifest | ConvertTo-Json -Depth 10) + [Environment]::NewLine), $utf8)

    [IO.Directory]::CreateDirectory($outputParentFull) | Out-Null
    [IO.Directory]::Move($temporaryRoot, $finalRoot)
    $moved = $true
    $validated = & $fullAssertPath -BundleDirectory $finalRoot
    Write-Host "PASS: staged Fallout: New Vegas full-neural candidate '$PackageId'."
    return $validated
}
catch {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
    if ($moved -and (Test-Path -LiteralPath $finalRoot -PathType Container)) { Remove-Item -LiteralPath $finalRoot -Recurse -Force }
    throw
}
