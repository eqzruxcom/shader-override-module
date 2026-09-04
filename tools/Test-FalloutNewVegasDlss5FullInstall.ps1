[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$testRoot = Join-Path $workspace ('artifacts\fallout-new-vegas-full-install-test-' + [Guid]::NewGuid().ToString('N'))
$fixtureRoot = Join-Path $testRoot 'fixtures'
$transportParent = Join-Path $testRoot 'transport'
$fullParent = Join-Path $testRoot 'full'
$receiptParent = Join-Path $testRoot 'receipts'
$gameRoot = Join-Path $testRoot 'game'
$transportStagePath = Join-Path $PSScriptRoot 'New-FalloutNewVegasDlss5Bundle.ps1'
$fullStagePath = Join-Path $PSScriptRoot 'New-FalloutNewVegasDlss5FullBundle.ps1'
$installPath = Join-Path $PSScriptRoot 'Install-FalloutNewVegasDlss5Bundle.ps1'
$restorePath = Join-Path $PSScriptRoot 'Restore-FalloutNewVegasDlss5Bundle.ps1'
$utf8 = [Text.UTF8Encoding]::new($false)

function Write-TestPe {
    param([string] $Path, [ValidateSet('x86', 'x64')][string] $Architecture, [byte] $Marker)
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    $bytes = [byte[]]::new(512)
    $bytes[0] = 0x4d; $bytes[1] = 0x5a
    [BitConverter]::GetBytes([int]0x80).CopyTo($bytes, 0x3c)
    $bytes[0x80] = 0x50; $bytes[0x81] = 0x45
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

    $null = & $transportStagePath `
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
        -PackageId 'full-install-transport' `
        -OutputParent $transportParent
    $transportBundle = Join-Path $transportParent 'full-install-transport'

    $renoDx = Join-Path $fixtureRoot 'neural\renodx-dlss5-4.7.addon64'
    $dlss = Join-Path $fixtureRoot 'neural\nvngx_dlss.dll'
    $dlssNr = Join-Path $fixtureRoot 'neural\nvngx_dlssnr.dll'
    Write-TestPe $renoDx x64 0x51
    Write-TestPe $dlss x64 0x52
    Write-TestPe $dlssNr x64 0x53
    $null = & $fullStagePath `
        -TransportBundleDirectory $transportBundle `
        -RenoDxAddonPath $renoDx `
        -NvngxDlssPath $dlss `
        -NvngxDlssNrPath $dlssNr `
        -PackageId 'full-install-candidate' `
        -OutputParent $fullParent
    $fullBundle = Join-Path $fullParent 'full-install-candidate'

    [IO.Directory]::CreateDirectory($gameRoot) | Out-Null
    $gameExe = Join-Path $gameRoot 'FalloutNV.exe'
    Write-TestPe $gameExe x86 0x77
    $gameExeHash = Get-Hash $gameExe
    $originalConfig = "user_setting = keep`r`n"
    [IO.File]::WriteAllText((Join-Path $gameRoot 'dxvk.conf'), $originalConfig, $utf8)
    $originalConfigHash = Get-Hash (Join-Path $gameRoot 'dxvk.conf')

    foreach ($parameters in @(
        @{},
        @{ AcknowledgeTransportOnly = $true },
        @{ AcknowledgeTransportOnly = $true; AcknowledgeFullNeuralCandidate = $true }
    )) {
        $rejected = $false
        try { $null = & $installPath -BundleDirectory $fullBundle -GameDirectory $gameRoot -ReceiptParent $receiptParent @parameters } catch { $rejected = $_.Exception.Message -match 'AcknowledgeFullNeuralCandidate' }
        if (-not $rejected) { throw 'Full installer accepted a missing, wrong, or ambiguous acknowledgement.' }
        if (Test-Path -LiteralPath (Join-Path $gameRoot 'd3d9.dll')) { throw 'Rejected full install changed the game directory.' }
    }

    $directoryCollision = Join-Path $gameRoot 'd3d9.dll'
    [IO.Directory]::CreateDirectory($directoryCollision) | Out-Null
    $rejected = $false
    try { $null = & $installPath -BundleDirectory $fullBundle -GameDirectory $gameRoot -AcknowledgeFullNeuralCandidate -ReceiptParent $receiptParent } catch { $rejected = $_.Exception.Message -match 'directory, not a file' }
    if (-not $rejected) { throw 'Full installer accepted a directory/file target collision.' }
    Remove-Item -LiteralPath $directoryCollision -Force
    if (Test-Path -LiteralPath (Join-Path $gameRoot 'ReShade.ini')) { throw 'Directory-collision preflight was not atomic.' }

    $installed = & $installPath -BundleDirectory $fullBundle -GameDirectory $gameRoot -AcknowledgeFullNeuralCandidate -ReceiptParent $receiptParent
    if (-not $installed.Installed -or $installed.RuntimeEligible -ne $false -or $installed.Mode -ne 'full-neural-candidate') { throw 'Full install did not return the guarded neural-candidate state.' }
    if ((Get-Hash $gameExe) -ne $gameExeHash) { throw 'Full installer changed FalloutNV.exe.' }
    if (-not (Test-Path -LiteralPath (Join-Path $gameRoot 'host64\renodx-dlss5-4.7.addon64') -PathType Leaf)) { throw 'Full installer omitted the RenoDX consumer.' }
    if (-not (Test-Path -LiteralPath (Join-Path $gameRoot 'host64\nvngx_dlssnr.dll') -PathType Leaf)) { throw 'Full installer omitted the neural-rendering runtime.' }
    if (Test-Path -LiteralPath (Join-Path $gameRoot 'README-DLSS5.md')) { throw 'Full installer copied packaging documentation into the game.' }

    $receipt = Get-Content -Raw -LiteralPath $installed.ReceiptPath | ConvertFrom-Json
    if ($receipt.kind -ne 'fallout-new-vegas-dlss5-full-install' -or $receipt.mode -ne 'full-neural-candidate') { throw 'Full install receipt lost its mode identity.' }
    $configRecord = @($receipt.targets | Where-Object { $_.relativePath -eq 'dxvk.conf' })
    if ($configRecord.Count -ne 1 -or -not $configRecord[0].existedBefore -or $configRecord[0].originalSha256 -ne $originalConfigHash) { throw 'Full install receipt did not preserve the original dxvk.conf.' }

    $receiptBytes = [IO.File]::ReadAllBytes($installed.ReceiptPath)
    $unsafeReceipt = Get-Content -Raw -LiteralPath $installed.ReceiptPath | ConvertFrom-Json
    $unsafeReceipt.targets[0].relativePath = '../outside-target.bin'
    [IO.File]::WriteAllText($installed.ReceiptPath, (($unsafeReceipt | ConvertTo-Json -Depth 8) + [Environment]::NewLine), $utf8)
    $rejected = $false
    try { $null = & $restorePath -ReceiptPath $installed.ReceiptPath } catch { $rejected = $_.Exception.Message -match 'Unsafe target path' }
    if (-not $rejected) { throw 'Restore accepted a traversal path in a modified receipt.' }
    if (-not (Test-Path -LiteralPath (Join-Path $gameRoot 'host64\nvngx_dlssnr.dll') -PathType Leaf)) { throw 'Unsafe-receipt preflight changed the installed package.' }
    [IO.File]::WriteAllBytes($installed.ReceiptPath, $receiptBytes)

    $restored = & $restorePath -ReceiptPath $installed.ReceiptPath
    if (-not $restored.Restored -or $restored.TargetCount -ne $installed.TargetCount) { throw 'Full restore did not complete all recorded targets.' }
    if ((Get-Hash $gameExe) -ne $gameExeHash -or (Get-Hash (Join-Path $gameRoot 'dxvk.conf')) -ne $originalConfigHash) { throw 'Full restore changed FalloutNV.exe or failed to recover dxvk.conf.' }
    foreach ($record in @($receipt.targets | Where-Object { -not $_.existedBefore })) {
        if (Test-Path -LiteralPath (Join-Path $gameRoot ([string]$record.relativePath).Replace('/', '\')) -PathType Leaf) { throw "Full restore left a package-created file behind: $($record.relativePath)" }
    }
    $restoreReceipt = Get-Content -Raw -LiteralPath $restored.RestoreReceiptPath | ConvertFrom-Json
    if ($restoreReceipt.kind -ne 'fallout-new-vegas-dlss5-full-restore' -or $restoreReceipt.mode -ne 'full-neural-candidate') { throw 'Full restore receipt lost its mode identity.' }

    Write-Host 'PASS: New Vegas full-neural install is separately acknowledgement-gated, path-contained, hash-verified, fully backed up, and exactly restorable.'
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
