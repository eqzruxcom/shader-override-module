[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$testRoot = Join-Path $workspace ('artifacts\fallout-new-vegas-dlss5-test-' + [Guid]::NewGuid().ToString('N'))
$fixtureRoot = Join-Path $testRoot 'fixtures'
$outputRoot = Join-Path $testRoot 'bundles'
$stagePath = Join-Path $PSScriptRoot 'New-FalloutNewVegasDlss5Bundle.ps1'
$assertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5Bundle.ps1'
$utf8 = [Text.UTF8Encoding]::new($false)

function Write-TestPe {
    param([string] $Path, [ValidateSet('x86', 'x64')][string] $Architecture, [byte] $Marker)
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    $bytes = [byte[]]::new(512)
    $bytes[0] = 0x4d
    $bytes[1] = 0x5a
    [BitConverter]::GetBytes([int]0x80).CopyTo($bytes, 0x3c)
    $bytes[0x80] = 0x50
    $bytes[0x81] = 0x45
    $machine = if ($Architecture -eq 'x86') { [uint16]0x014c } else { [uint16]0x8664 }
    [BitConverter]::GetBytes($machine).CopyTo($bytes, 0x84)
    $bytes[0x100] = $Marker
    [IO.File]::WriteAllBytes($Path, $bytes)
}

function Write-TextFile {
    param([string] $Path, [string] $Text)
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text + [Environment]::NewLine, $utf8)
}

try {
    [IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
    $dxvk = Join-Path $fixtureRoot 'dxvk\d3d9.dll'
    $addon = Join-Path $fixtureRoot 'feeder\dlss5-feed.addon32'
    $hostExe = Join-Path $fixtureRoot 'feeder\host64\dlss5-feed-host64.exe'
    $feedLayer = Join-Path $fixtureRoot 'feeder\layer\x86\VkLayer_feed_vk32.dll'
    $reshade32 = Join-Path $fixtureRoot 'reshade\ReShade32.dll'
    $reshade64 = Join-Path $fixtureRoot 'reshade\ReShade64.dll'
    Write-TestPe $dxvk x86 0x01
    Write-TestPe $addon x86 0x02
    Write-TestPe $hostExe x64 0x03
    Write-TestPe $feedLayer x86 0x04
    Write-TestPe $reshade32 x86 0x05
    Write-TestPe $reshade64 x64 0x06

    $feedEffect = Join-Path $fixtureRoot 'feeder\DLSS5_Feed.fx'
    Write-TextFile $feedEffect 'technique DLSS5_Feed { pass { } }'
    $feedManifest = Join-Path $fixtureRoot 'feeder\layer\x86\VkLayer_feed_vk32.json'
    Write-TextFile $feedManifest '{"file_format_version":"1.2.0","layer":{"name":"VK_LAYER_feed_vk","library_path":".\\VkLayer_feed_vk32.dll"}}'
    $reshadeManifest = Join-Path $fixtureRoot 'reshade\ReShade32.json'
    Write-TextFile $reshadeManifest '{"file_format_version":"1.0.0","layer":{"name":"VK_LAYER_reshade","library_path":".\\ReShade32.dll"}}'

    $framework = Join-Path $fixtureRoot 'framework'
    foreach ($name in @('ReShade.fxh', 'ReShadeUI.fxh', 'DrawText.fxh')) {
        Write-TextFile (Join-Path $framework $name) ('// fixture ' + $name)
    }
    $lumenite = Join-Path $fixtureRoot 'lumenite'
    Write-TextFile (Join-Path $lumenite 'Shaders\lumenite_Kernel.fx') 'technique Lumenite_Kernel { pass { } }'
    Write-TextFile (Join-Path $lumenite 'Shaders\include\lumenite_Helpers.fxh') '// fixture include'
    Write-TextFile (Join-Path $lumenite 'Textures\lumenite_bluenoise256.png') 'fixture texture'

    $arguments = @{
        DxvkD3D9Path = $dxvk
        FeederAddon32Path = $addon
        FeederHost64Path = $hostExe
        FeederEffectPath = $feedEffect
        FeedLayer32Path = $feedLayer
        FeedLayer32ManifestPath = $feedManifest
        ReShade32Path = $reshade32
        ReShade32ManifestPath = $reshadeManifest
        ReShade64Path = $reshade64
        ReShadeFrameworkRoot = $framework
        LumeniteRoot = $lumenite
        PackageId = 'positive'
        OutputParent = $outputRoot
    }
    $result = & $stagePath @arguments
    if (-not $result.Valid -or $result.Mode -ne 'transport-only' -or $result.Installed -ne $false -or $result.RuntimeEligible -ne $false) {
        throw 'Positive transport bundle did not return the guarded validation result.'
    }
    $bundle = Join-Path $outputRoot 'positive'
    $null = & $assertPath -BundleDirectory $bundle

    $feedConfig = Get-Content -Raw -LiteralPath (Join-Path $bundle 'dlss5-feed.cfg')
    if ($feedConfig -notmatch '(?m)^mode=1\s*$') { throw 'Positive fixture was not staged in transport-only mode.' }
    if (Get-ChildItem -LiteralPath $bundle -Recurse -File | Where-Object { $_.Name -match '(?i)nvngx|renodx|deep-fried' }) {
        throw 'Positive fixture unexpectedly contains neural runtime files.'
    }

    $tamperPath = Join-Path $bundle 'd3d9.dll'
    $original = [IO.File]::ReadAllBytes($tamperPath)
    $changed = [byte[]]$original.Clone()
    $changed[0x100] = 0xff
    [IO.File]::WriteAllBytes($tamperPath, $changed)
    $rejected = $false
    try { $null = & $assertPath -BundleDirectory $bundle } catch { $rejected = $_.Exception.Message -match 'hash mismatch' }
    if (-not $rejected) { throw 'Validator accepted a tampered DXVK runtime.' }
    [IO.File]::WriteAllBytes($tamperPath, $original)

    Write-TextFile (Join-Path $bundle 'unexpected.txt') 'unexpected'
    $rejected = $false
    try { $null = & $assertPath -BundleDirectory $bundle } catch { $rejected = $_.Exception.Message -match 'unlisted file' }
    if (-not $rejected) { throw 'Validator accepted an unlisted bundle file.' }
    Remove-Item -LiteralPath (Join-Path $bundle 'unexpected.txt') -Force

    $badDxvk = Join-Path $fixtureRoot 'bad\d3d9.dll'
    Write-TestPe $badDxvk x64 0x44
    $badArguments = $arguments.Clone()
    $badArguments.DxvkD3D9Path = $badDxvk
    $badArguments.PackageId = 'wrong-architecture'
    $rejected = $false
    try { $null = & $stagePath @badArguments } catch { $rejected = $_.Exception.Message -match 'must be x86' }
    if (-not $rejected) { throw 'Bundle staging accepted an x64 D3D9 runtime for the x86 game.' }

    $stageText = [IO.File]::ReadAllText($stagePath)
    foreach ($forbidden in @('Invoke-WebRequest', 'Start-BitsTransfer', 'HKCU:', 'HKLM:', 'Program Files (x86)\Steam')) {
        if ($stageText.Contains($forbidden)) { throw "Bundle stage unexpectedly contains network, registry, or live-game behavior: $forbidden" }
    }

    Write-Host 'PASS: Fallout New Vegas DLSS5 transport bundle is x86/x64-checked, hash-closed, local-layered, non-installing, and neural-runtime-free.'
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
