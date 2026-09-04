[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$testRoot = Join-Path $workspace ('artifacts\fallout-new-vegas-install-test-' + [Guid]::NewGuid().ToString('N'))
$fixtureRoot = Join-Path $testRoot 'fixtures'
$bundleParent = Join-Path $testRoot 'bundles'
$receiptParent = Join-Path $testRoot 'receipts'
$gameRoot = Join-Path $testRoot 'game'
$stagePath = Join-Path $PSScriptRoot 'New-FalloutNewVegasDlss5Bundle.ps1'
$installPath = Join-Path $PSScriptRoot 'Install-FalloutNewVegasDlss5Bundle.ps1'
$restorePath = Join-Path $PSScriptRoot 'Restore-FalloutNewVegasDlss5Bundle.ps1'
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

function Get-Hash {
    param([string] $Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

try {
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
    foreach ($name in @('ReShade.fxh', 'ReShadeUI.fxh', 'DrawText.fxh')) { Write-TextFile (Join-Path $framework $name) ('// ' + $name) }
    $lumenite = Join-Path $fixtureRoot 'lumenite'
    Write-TextFile (Join-Path $lumenite 'Shaders\lumenite_Kernel.fx') 'technique Lumenite_Kernel { pass { } }'
    Write-TextFile (Join-Path $lumenite 'Shaders\include\lumenite_Helpers.fxh') '// include'
    Write-TextFile (Join-Path $lumenite 'Textures\lumenite_bluenoise256.png') 'texture'

    $null = & $stagePath `
        -DxvkD3D9Path $dxvk `
        -FeederAddon32Path $addon `
        -FeederHost64Path $hostExe `
        -FeederEffectPath $feedEffect `
        -FeedLayer32Path $feedLayer `
        -FeedLayer32ManifestPath $feedManifest `
        -ReShade32Path $reshade32 `
        -ReShade32ManifestPath $reshadeManifest `
        -ReShade64Path $reshade64 `
        -ReShadeFrameworkRoot $framework `
        -LumeniteRoot $lumenite `
        -PackageId 'install-fixture' `
        -OutputParent $bundleParent
    $bundle = Join-Path $bundleParent 'install-fixture'

    [IO.Directory]::CreateDirectory($gameRoot) | Out-Null
    $gameExe = Join-Path $gameRoot 'FalloutNV.exe'
    Write-TestPe $gameExe x86 0x77
    $gameExeHash = Get-Hash $gameExe
    $originalConfig = "user_setting = keep`r`n"
    [IO.File]::WriteAllText((Join-Path $gameRoot 'dxvk.conf'), $originalConfig, $utf8)
    $originalConfigHash = Get-Hash (Join-Path $gameRoot 'dxvk.conf')

    $rejected = $false
    try { $null = & $installPath -BundleDirectory $bundle -GameDirectory $gameRoot -ReceiptParent $receiptParent } catch { $rejected = $_.Exception.Message -match 'AcknowledgeTransportOnly' }
    if (-not $rejected) { throw 'Installer did not require explicit transport-only acknowledgement.' }
    if (Test-Path -LiteralPath (Join-Path $gameRoot 'd3d9.dll')) { throw 'Rejected install changed the game directory.' }

    $installed = & $installPath -BundleDirectory $bundle -GameDirectory $gameRoot -AcknowledgeTransportOnly -ReceiptParent $receiptParent
    if (-not $installed.Installed -or $installed.RuntimeEligible -ne $false -or $installed.TargetCount -lt 20) { throw 'Install did not return the guarded transport receipt.' }
    if ((Get-Hash $gameExe) -ne $gameExeHash) { throw 'Installer changed FalloutNV.exe.' }
    $receipt = Get-Content -Raw -LiteralPath $installed.ReceiptPath | ConvertFrom-Json
    $configRecord = @($receipt.targets | Where-Object { $_.relativePath -eq 'dxvk.conf' })
    if ($configRecord.Count -ne 1 -or -not $configRecord[0].existedBefore -or $configRecord[0].originalSha256 -ne $originalConfigHash) {
        throw 'Install receipt did not preserve the pre-existing dxvk.conf provenance.'
    }

    $installedD3D9 = Join-Path $gameRoot 'd3d9.dll'
    $originalD3D9Bytes = [IO.File]::ReadAllBytes($installedD3D9)
    $tampered = [byte[]]$originalD3D9Bytes.Clone()
    $tampered[0x100] = 0xee
    [IO.File]::WriteAllBytes($installedD3D9, $tampered)
    $rejected = $false
    try { $null = & $restorePath -ReceiptPath $installed.ReceiptPath } catch { $rejected = $_.Exception.Message -match 'drifted' }
    if (-not $rejected) { throw 'Restore accepted a drifted installed runtime.' }
    if ((Get-Hash (Join-Path $gameRoot 'dxvk.conf')) -eq $originalConfigHash) { throw 'Restore was not atomic; it changed an earlier target before detecting later drift.' }
    [IO.File]::WriteAllBytes($installedD3D9, $originalD3D9Bytes)

    $restored = & $restorePath -ReceiptPath $installed.ReceiptPath
    if (-not $restored.Restored -or $restored.TargetCount -ne $installed.TargetCount) { throw 'Restore did not complete all recorded targets.' }
    if ((Get-Hash $gameExe) -ne $gameExeHash) { throw 'Restore changed FalloutNV.exe.' }
    if ((Get-Hash (Join-Path $gameRoot 'dxvk.conf')) -ne $originalConfigHash) { throw 'Restore did not recover the original dxvk.conf.' }
    if ([IO.File]::ReadAllText((Join-Path $gameRoot 'dxvk.conf')) -ne $originalConfig) { throw 'Restored dxvk.conf content differs from the original.' }
    foreach ($record in @($receipt.targets | Where-Object { -not $_.existedBefore })) {
        if (Test-Path -LiteralPath (Join-Path $gameRoot ([string]$record.relativePath).Replace('/', '\')) -PathType Leaf) {
            throw "Restore left a package-created file behind: $($record.relativePath)"
        }
    }

    foreach ($path in @($installPath, $restorePath)) {
        $text = [IO.File]::ReadAllText($path)
        foreach ($forbidden in @('Invoke-WebRequest', 'Start-BitsTransfer', 'HKCU:', 'HKLM:', 'C:\Games')) {
            if ($text.Contains($forbidden)) { throw "Install/restore tooling unexpectedly contains network, registry, or hard-coded game behavior: $forbidden" }
        }
    }

    Write-Host 'PASS: New Vegas transport install is acknowledgement-gated, fully backed up, hash-verified, drift-safe, atomic on preflight, and exactly restorable.'
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
