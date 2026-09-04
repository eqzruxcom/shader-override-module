[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$testRoot = Join-Path $workspace ('artifacts\fallout-new-vegas-full-bundle-test-' + [Guid]::NewGuid().ToString('N'))
$fixtureRoot = Join-Path $testRoot 'fixtures'
$transportParent = Join-Path $testRoot 'transport'
$fullParent = Join-Path $testRoot 'full'
$transportStagePath = Join-Path $PSScriptRoot 'New-FalloutNewVegasDlss5Bundle.ps1'
$fullStagePath = Join-Path $PSScriptRoot 'New-FalloutNewVegasDlss5FullBundle.ps1'
$fullAssertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5FullBundle.ps1'
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
        -PackageId 'transport-parent' `
        -OutputParent $transportParent
    $transportBundle = Join-Path $transportParent 'transport-parent'

    $renoDx = Join-Path $fixtureRoot 'neural\renodx-dlss5-4.7.addon64'
    $dlss = Join-Path $fixtureRoot 'neural\nvngx_dlss.dll'
    $dlssNr = Join-Path $fixtureRoot 'neural\nvngx_dlssnr.dll'
    Write-TestPe $renoDx x64 0x51
    Write-TestPe $dlss x64 0x52
    Write-TestPe $dlssNr x64 0x53

    $result = & $fullStagePath -TransportBundleDirectory $transportBundle -RenoDxAddonPath $renoDx -NvngxDlssPath $dlss -NvngxDlssNrPath $dlssNr -PackageId 'full-positive' -OutputParent $fullParent
    if (-not $result.Valid -or $result.Mode -ne 'full-neural-candidate' -or $result.RuntimeEligible -ne $false -or $result.FrameGenerationIncluded -ne $false) { throw 'Positive full bundle did not return its guarded state.' }
    $fullBundle = Join-Path $fullParent 'full-positive'
    $null = & $fullAssertPath -BundleDirectory $fullBundle

    $config = Get-Content -Raw -LiteralPath (Join-Path $fullBundle 'dlss5-feed.cfg')
    foreach ($expected in @('(?m)^mode=2\s*$', '(?m)^async_home=1\s*$', '(?m)^host_window=0\s*$')) {
        if ($config -notmatch $expected) { throw "Full fixture is missing config state: $expected" }
    }
    if (Get-ChildItem -LiteralPath $fullBundle -Recurse -File | Where-Object { $_.Name -match '(?i)dlssg|sl\.interposer|deep-fried' }) { throw 'Full fixture contains a conflicting consumer or frame-generation file.' }

    $fullManifestPath = Join-Path $fullBundle 'runtime-bundle.json'
    $manifestBytes = [IO.File]::ReadAllBytes($fullManifestPath)
    $inheritedD3D9 = Join-Path $fullBundle 'd3d9.dll'
    $inheritedBytes = [IO.File]::ReadAllBytes($inheritedD3D9)
    $changedInherited = [byte[]]$inheritedBytes.Clone(); $changedInherited[0x100] = 0xef
    [IO.File]::WriteAllBytes($inheritedD3D9, $changedInherited)
    $rehashManifest = Get-Content -Raw -LiteralPath $fullManifestPath | ConvertFrom-Json
    $d3d9Record = @($rehashManifest.files | Where-Object { $_.relativePath -eq 'd3d9.dll' })
    if ($d3d9Record.Count -ne 1) { throw 'Full fixture lost its inherited d3d9 record.' }
    $d3d9Record[0].sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $inheritedD3D9).Hash
    [IO.File]::WriteAllText($fullManifestPath, (($rehashManifest | ConvertTo-Json -Depth 10) + [Environment]::NewLine), $utf8)
    $rejected = $false
    try { $null = & $fullAssertPath -BundleDirectory $fullBundle } catch { $rejected = $_.Exception.Message -match 'changed immutable parent transport payload' }
    if (-not $rejected) { throw 'Full-bundle validator accepted a rehashed mutation of inherited transport payload.' }
    [IO.File]::WriteAllBytes($inheritedD3D9, $inheritedBytes)
    [IO.File]::WriteAllBytes($fullManifestPath, $manifestBytes)

    $consumer = Join-Path $fullBundle 'host64\renodx-dlss5-4.7.addon64'
    $original = [IO.File]::ReadAllBytes($consumer)
    $changed = [byte[]]$original.Clone(); $changed[0x100] = 0xee
    [IO.File]::WriteAllBytes($consumer, $changed)
    $rejected = $false
    try { $null = & $fullAssertPath -BundleDirectory $fullBundle } catch { $rejected = $_.Exception.Message -match 'hash mismatch' }
    if (-not $rejected) { throw 'Full-bundle validator accepted a tampered RenoDX consumer.' }
    [IO.File]::WriteAllBytes($consumer, $original)

    $badDlssNr = Join-Path $fixtureRoot 'bad\nvngx_dlssnr.dll'
    Write-TestPe $badDlssNr x86 0x61
    $rejected = $false
    try { $null = & $fullStagePath -TransportBundleDirectory $transportBundle -RenoDxAddonPath $renoDx -NvngxDlssPath $dlss -NvngxDlssNrPath $badDlssNr -PackageId 'wrong-neural-architecture' -OutputParent $fullParent } catch { $rejected = $_.Exception.Message -match 'must be x64' }
    if (-not $rejected) { throw 'Full-bundle staging accepted an x86 neural-rendering runtime.' }

    $stageText = [IO.File]::ReadAllText($fullStagePath)
    foreach ($forbidden in @('Invoke-WebRequest', 'Start-BitsTransfer', 'HKCU:', 'HKLM:', 'FalloutNV.exe"')) {
        if ($stageText.Contains($forbidden)) { throw "Full-bundle stage unexpectedly contains network, registry, or game-launch behavior: $forbidden" }
    }

    Write-Host 'PASS: New Vegas full-neural promotion requires one x64 RenoDX consumer, x64 NGX runtimes, validated immutable transport provenance, mode 2, and no frame-generation payload.'
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
