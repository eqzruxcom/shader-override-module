[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $DxvkD3D9Path,
    [Parameter(Mandatory)][string] $FeederAddon32Path,
    [Parameter(Mandatory)][string] $FeederHost64Path,
    [Parameter(Mandatory)][string] $FeederEffectPath,
    [Parameter(Mandatory)][string] $FeedLayer32Path,
    [Parameter(Mandatory)][string] $FeedLayer32ManifestPath,
    [Parameter(Mandatory)][string] $ReShade32Path,
    [Parameter(Mandatory)][string] $ReShade32ManifestPath,
    [Parameter(Mandatory)][string] $ReShade64Path,
    [Parameter(Mandatory)][string] $ReShadeFrameworkRoot,
    [Parameter(Mandatory)][string] $LumeniteRoot,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')][string] $PackageId,
    [string] $OutputParent = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\fallout-new-vegas-dlss5-bundles')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$outputParentFull = [IO.Path]::GetFullPath($OutputParent).TrimEnd('\')
$finalRoot = Join-Path $outputParentFull $PackageId
$temporaryRoot = Join-Path $outputParentFull ('.staging-' + $PackageId + '-' + [Guid]::NewGuid().ToString('N'))
$assertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5Bundle.ps1'
$utf8 = [Text.UTF8Encoding]::new($false)
$moved = $false

function Resolve-InputFile {
    param([string] $Path, [string] $Description)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "$Description is not a file: $resolved"
    }
    return $resolved
}

function Resolve-InputDirectory {
    param([string] $Path, [string] $Description)
    $resolved = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "$Description is not a directory: $resolved"
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

function Assert-PeArchitecture {
    param([string] $Path, [ValidateSet('x86', 'x64')][string] $Architecture, [string] $Description)
    $expected = if ($Architecture -eq 'x86') { [uint16]0x014c } else { [uint16]0x8664 }
    $machine = Get-PeMachine $Path
    if ($machine -ne $expected) {
        throw ('{0} must be {1}; PE machine is 0x{2:X4}: {3}' -f $Description, $Architecture, $machine, $Path)
    }
}

function Copy-TrackedFile {
    param([string] $Source, [string] $RelativePath)
    $destination = Join-Path $temporaryRoot $RelativePath
    [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $destination
}

if (-not ($outputParentFull -eq $artifactsRoot -or $outputParentFull.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase))) {
    throw "Refusing New Vegas bundle output outside the workspace artifacts directory: $outputParentFull"
}
if (Test-Path -LiteralPath $finalRoot) {
    throw "Refusing to overwrite an existing New Vegas bundle: $finalRoot"
}

$inputs = [ordered]@{
    dxvkD3D9 = Resolve-InputFile $DxvkD3D9Path 'DXVK D3D9 runtime'
    feederAddon32 = Resolve-InputFile $FeederAddon32Path '32-bit Feeder add-on'
    feederHost64 = Resolve-InputFile $FeederHost64Path '64-bit Feeder helper'
    feederEffect = Resolve-InputFile $FeederEffectPath 'Feeder effect'
    feedLayer32 = Resolve-InputFile $FeedLayer32Path '32-bit Feeder Vulkan layer'
    feedLayer32Manifest = Resolve-InputFile $FeedLayer32ManifestPath '32-bit Feeder Vulkan layer manifest'
    reshade32 = Resolve-InputFile $ReShade32Path '32-bit ReShade Vulkan layer'
    reshade32Manifest = Resolve-InputFile $ReShade32ManifestPath '32-bit ReShade Vulkan manifest'
    reshade64 = Resolve-InputFile $ReShade64Path '64-bit ReShade host runtime'
}
$frameworkRoot = Resolve-InputDirectory $ReShadeFrameworkRoot 'ReShade framework root'
$lumeniteRootFull = Resolve-InputDirectory $LumeniteRoot 'LumeniteFX root'

foreach ($entry in @(
    @($inputs.dxvkD3D9, 'x86', 'DXVK D3D9 runtime'),
    @($inputs.feederAddon32, 'x86', 'Feeder add-on'),
    @($inputs.feedLayer32, 'x86', 'Feeder Vulkan layer'),
    @($inputs.reshade32, 'x86', 'ReShade Vulkan layer'),
    @($inputs.feederHost64, 'x64', 'Feeder helper'),
    @($inputs.reshade64, 'x64', 'ReShade host runtime')
)) {
    Assert-PeArchitecture -Path $entry[0] -Architecture $entry[1] -Description $entry[2]
}

$feedText = [IO.File]::ReadAllText($inputs.feederEffect)
if ($feedText -notmatch 'DLSS5_Feed') { throw 'Feeder effect does not expose the expected DLSS5_Feed technique.' }

$reshadeManifest = Get-Content -Raw -LiteralPath $inputs.reshade32Manifest | ConvertFrom-Json
if ($reshadeManifest.layer.name -ne 'VK_LAYER_reshade' -or $reshadeManifest.layer.library_path -notmatch '(?i)ReShade32\.dll$') {
    throw 'ReShade manifest does not identify the 32-bit VK_LAYER_reshade library.'
}
$feedLayerManifest = Get-Content -Raw -LiteralPath $inputs.feedLayer32Manifest | ConvertFrom-Json
if ($feedLayerManifest.layer.name -ne 'VK_LAYER_feed_vk' -or $feedLayerManifest.layer.library_path -notmatch '(?i)VkLayer_feed_vk32\.dll$') {
    throw 'Feeder layer manifest does not identify the 32-bit VK_LAYER_feed_vk library.'
}

$frameworkFiles = [ordered]@{}
foreach ($name in @('ReShade.fxh', 'ReShadeUI.fxh', 'DrawText.fxh')) {
    $candidate = Join-Path $frameworkRoot $name
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw "ReShade framework header is missing: $candidate" }
    $frameworkFiles[$name] = $candidate
}
$lumeniteKernel = Join-Path $lumeniteRootFull 'Shaders\lumenite_Kernel.fx'
$lumeniteInclude = Join-Path $lumeniteRootFull 'Shaders\include'
if (-not (Test-Path -LiteralPath $lumeniteKernel -PathType Leaf)) { throw "Lumenite Kernel effect is missing: $lumeniteKernel" }
if (-not (Test-Path -LiteralPath $lumeniteInclude -PathType Container)) { throw "Lumenite include directory is missing: $lumeniteInclude" }

try {
    [IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null

    Copy-TrackedFile $inputs.dxvkD3D9 'd3d9.dll'
    Copy-TrackedFile $inputs.feederAddon32 'dlss5-feed.addon32'
    Copy-TrackedFile $inputs.feederHost64 'host64\dlss5-feed-host64.exe'
    Copy-TrackedFile $inputs.reshade64 'host64\dxgi.dll'
    Copy-TrackedFile $inputs.feederEffect 'reshade-shaders\Shaders\DLSS5_Feed.fx'
    Copy-TrackedFile $inputs.reshade32 'layers\x86\ReShade32.dll'
    Copy-TrackedFile $inputs.reshade32Manifest 'layers\x86\ReShade32.json'
    Copy-TrackedFile $inputs.feedLayer32 'layers\x86\VkLayer_feed_vk32.dll'
    Copy-TrackedFile $inputs.feedLayer32Manifest 'layers\x86\VkLayer_feed_vk32.json'
    foreach ($name in $frameworkFiles.Keys) {
        Copy-TrackedFile $frameworkFiles[$name] (Join-Path 'reshade-shaders\Shaders' $name)
    }
    Copy-TrackedFile $lumeniteKernel 'reshade-shaders\Shaders\lumenite_Kernel.fx'
    Get-ChildItem -LiteralPath $lumeniteInclude -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($lumeniteInclude.Length + 1)
        Copy-TrackedFile $_.FullName (Join-Path 'reshade-shaders\Shaders\include' $relative)
    }
    $textureRoot = Join-Path $lumeniteRootFull 'Textures'
    if (Test-Path -LiteralPath $textureRoot -PathType Container) {
        Get-ChildItem -LiteralPath $textureRoot -Recurse -File | ForEach-Object {
            $relative = $_.FullName.Substring($textureRoot.Length + 1)
            Copy-TrackedFile $_.FullName (Join-Path 'reshade-shaders\Textures' $relative)
        }
    }

    $dxvkConfig = @'
# Fallout: New Vegas transport-validation baseline.
# Keep exclusive fullscreen emulation disabled for the 32-bit Vulkan/ReShade path.
dxvk.allowFse = False
'@
    [IO.File]::WriteAllText((Join-Path $temporaryRoot 'dxvk.conf'), $dxvkConfig.TrimStart() + [Environment]::NewLine, $utf8)

    $reshadeIni = @'
[ADDON]
AddonPath=.\

[DEPTH]
DepthCopyBeforeClears=0

[GENERAL]
EffectSearchPaths=.\reshade-shaders\Shaders\**
TextureSearchPaths=.\reshade-shaders\Textures\**
IntermediateCachePath=
NoDebugInfo=1
NoEffectCache=0
NoReloadOnInit=0
PerformanceMode=0
PreprocessorDefinitions=
PresetPath=.\ReShadePreset.ini
SkipLoadingDisabledEffects=0

[INPUT]
ForceShortcutModifiers=1
InputProcessing=2
KeyEffects=222,0,0,0
KeyOverlay=36,0,0,0
KeyReload=0,0,0,0
KeyScreenshot=220,0,0,0

[OVERLAY]
TutorialProgress=4
'@
    [IO.File]::WriteAllText((Join-Path $temporaryRoot 'ReShade.ini'), $reshadeIni.TrimStart() + [Environment]::NewLine, $utf8)

    $preset = @'
Techniques=Lumenite_Kernel@lumenite_Kernel.fx,DLSS5_Feed@DLSS5_Feed.fx
TechniqueSorting=Lumenite_Kernel@lumenite_Kernel.fx,DLSS5_Feed@DLSS5_Feed.fx,DLSS5_Feed_Debug@DLSS5_Feed.fx

[DLSS5_Feed.fx]
DEBUG_VIEW=0
MV_SCALE=1.000000
MV_SIGN=1.000000,1.000000
PreprocessorDefinitions=DLSS5_MV_PROVIDER=3
'@
    [IO.File]::WriteAllText((Join-Path $temporaryRoot 'ReShadePreset.ini'), $preset.TrimStart() + [Environment]::NewLine, $utf8)

    $feedConfig = @'
enabled=1
mode=1
hdr=0
depth_inverted=-1
flags=-1
reset_every=0
warmup_rebuild=0
rebuild=0
log_frames=3
create_delay=60
host_window=1
work_resolution=100
async_home=0
mv_scale_x=1.000
mv_scale_y=1.000
'@
    [IO.File]::WriteAllText((Join-Path $temporaryRoot 'dlss5-feed.cfg'), $feedConfig.TrimStart() + [Environment]::NewLine, $utf8)
    [IO.File]::WriteAllText((Join-Path $temporaryRoot 'host64\ReShade.ini'), "[GENERAL]`r`nEffectSearchPaths=.\`r`nTextureSearchPaths=.\`r`n", $utf8)

    $launcher = @'
@echo off
setlocal
set "VK_LAYER_PATH=%~dp0layers\x86"
set "VK_INSTANCE_LAYERS=VK_LAYER_reshade;VK_LAYER_feed_vk"
if not exist "%~dp0FalloutNV.exe" (
  echo FalloutNV.exe was not found next to this launcher.
  exit /b 2
)
echo Starting Fallout: New Vegas with local 32-bit ReShade and Feeder Vulkan layers.
start "" /D "%~dp0" "%~dp0FalloutNV.exe" %*
endlocal
'@
    [IO.File]::WriteAllText((Join-Path $temporaryRoot 'Launch-FalloutNV-DLSS5.cmd'), $launcher.TrimStart() + "`r`n", [Text.Encoding]::ASCII)

    $readme = @'
# Fallout: New Vegas DLSS5 transport bundle

This is a non-installing, transport-only proof package. It deliberately sets
`mode=1`, which performs the 32-bit Vulkan to 64-bit helper round trip without
calling NGX. A successful run shows the feeder's split-screen transport result.

Copying this package into a game directory is a separate, not-yet-authorized
step. Back up every target first. Launch with `Launch-FalloutNV-DLSS5.cmd` so
both local explicit Vulkan layers are enabled without registry changes.

Expected evidence after a run:

- `ReShade.log` identifies Vulkan and contains no effect compile failures;
- `dlss5-feed.log` reports a Vulkan x86 client and connected host;
- `host64/dlss5-feed-host.log` reports the same IPC protocol and delivered frames;
- the on-screen transport split is visible.

This package contains no neural consumer and no `nvngx_dlssnr.dll`. Promotion
to `mode=2` is blocked until the transport evidence above is captured and a
single user-supplied neural consumer plus NVIDIA runtimes are hash-closed.
'@
    [IO.File]::WriteAllText((Join-Path $temporaryRoot 'README-TRANSPORT.md'), $readme.TrimStart() + [Environment]::NewLine, $utf8)

    $inputRecords = @(
        foreach ($key in $inputs.Keys) {
            [ordered]@{ role = $key; sourcePath = $inputs[$key]; sha256 = Get-Sha256Upper $inputs[$key] }
        }
        [ordered]@{ role = 'lumeniteKernel'; sourcePath = $lumeniteKernel; sha256 = Get-Sha256Upper $lumeniteKernel }
        foreach ($key in $frameworkFiles.Keys) {
            [ordered]@{ role = ('framework-' + $key); sourcePath = $frameworkFiles[$key]; sha256 = Get-Sha256Upper $frameworkFiles[$key] }
        }
    )
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
        mode = 'transport-only'
        stack = @('FalloutNV.exe', 'DXVK x86 D3D9', 'Vulkan x86', 'ReShade explicit layer x86', 'DLSS5-Feeder addon32', 'DLSS5-Feeder host64')
        configuration = [ordered]@{
            feederMode = 1
            motionProvider = 'LumeniteFX Kernel'
            motionProviderId = 3
            explicitLayers = @('VK_LAYER_reshade', 'VK_LAYER_feed_vk')
            dxvkAllowFse = $false
        }
        inputs = @($inputRecords)
        files = @($files)
        gates = [ordered]@{
            componentArchitectureValidated = $true
            bundleValidationPassed = $true
            gameInstalled = $false
            liveTransportPassed = $false
            neuralConsumerPresent = $false
            ngxRuntimePresent = $false
            fullDlss5Passed = $false
        }
        policy = [ordered]@{
            installed = $false
            runtimeEligible = $false
            automaticInstall = $false
            gameDirectoryTouched = $false
            registryTouched = $false
        }
    }
    [IO.File]::WriteAllText((Join-Path $temporaryRoot 'runtime-bundle.json'), (($manifest | ConvertTo-Json -Depth 10) + [Environment]::NewLine), $utf8)

    [IO.Directory]::CreateDirectory($outputParentFull) | Out-Null
    [IO.Directory]::Move($temporaryRoot, $finalRoot)
    $moved = $true
    $validated = & $assertPath -BundleDirectory $finalRoot
    Write-Host "PASS: staged Fallout: New Vegas transport bundle '$PackageId'."
    return $validated
}
catch {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
    if ($moved -and (Test-Path -LiteralPath $finalRoot -PathType Container)) {
        Remove-Item -LiteralPath $finalRoot -Recurse -Force
    }
    throw
}
