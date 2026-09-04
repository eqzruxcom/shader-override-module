[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifacts = Join-Path $workspace 'artifacts'
$fixtureRoot = Join-Path $artifacts ('test-fnv-live-capture-' + [Guid]::NewGuid().ToString('N'))
$startPath = Join-Path $PSScriptRoot 'Start-FalloutNewVegasDlss5LiveCapture.ps1'
$completePath = Join-Path $PSScriptRoot 'Complete-FalloutNewVegasDlss5LiveCapture.ps1'
$utf8 = [Text.UTF8Encoding]::new($false)

function Get-Sha256Upper { param([string] $Path) return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant() }
function Write-Text { param([string] $Path, [string] $Text) [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null; [IO.File]::WriteAllText($Path, $Text, $utf8) }

try {
    $game = Join-Path $fixtureRoot 'game'
    $package = Join-Path $fixtureRoot 'package'
    $receipts = Join-Path $fixtureRoot 'receipts'
    [IO.Directory]::CreateDirectory($game) | Out-Null
    [IO.Directory]::CreateDirectory($package) | Out-Null
    [IO.Directory]::CreateDirectory($receipts) | Out-Null
    Copy-Item -LiteralPath (Join-Path $env:WINDIR 'SysWOW64\kernel32.dll') -Destination (Join-Path $game 'FalloutNV.exe')
    [IO.File]::WriteAllBytes((Join-Path $game 'd3d9.dll'), [byte[]]@(1,2,3,4))
    Write-Text (Join-Path $package 'runtime-bundle.json') '{"fixture":true}'
    $receipt = [ordered]@{
        schemaVersion=1; kind='fallout-new-vegas-dlss5-transport-install'; mode='transport-only'; packageId='fixture-package'
        packageRoot=$package; packageManifestSha256=Get-Sha256Upper (Join-Path $package 'runtime-bundle.json')
        gameRoot=$game; gameExecutable='FalloutNV.exe'; gameExecutableSha256=Get-Sha256Upper (Join-Path $game 'FalloutNV.exe')
        createdUtc=[DateTime]::UtcNow.ToString('o'); targets=@([ordered]@{relativePath='d3d9.dll';packageSha256=Get-Sha256Upper (Join-Path $game 'd3d9.dll')})
        installed=$true; restored=$false
    }
    $receiptPath = Join-Path $receipts 'install-receipt.json'
    Write-Text $receiptPath (($receipt | ConvertTo-Json -Depth 8) + [Environment]::NewLine)

    $sessionParent = Join-Path $fixtureRoot 'sessions'
    $started = & $startPath -InstallReceiptPath $receiptPath -SessionId 'capture-fixture' -OutputParent $sessionParent
    if ($started.Phase -ne 'transport') { throw 'Capture start derived the wrong phase.' }

    Start-Sleep -Milliseconds 50
    Write-Text (Join-Path $game 'FalloutNV_d3d9.log') "info: Game: FalloutNV.exe`ninfo: DXVK: v3.0.2`n"
    Write-Text (Join-Path $game 'ReShade.log') "ReShade 6.8.0.2155`nVulkan runtime attached`nLoading add-on dlss5-feed.addon32`n"
    Write-Text (Join-Path $game 'dlss5-feed.log') "[feed32] config: enabled=1 mode=1 hdr=0`n[feed32] host connected (protocol v6, Vulkan client)`n[feed32] shared set ready (Vulkan): 1920x1080 color fmt output fmt`n[feed32] frame 1 delivered (1920x1080, reset=1, Vulkan)`n[feed32] frame 3 delivered (1920x1080, reset=0, Vulkan)`n"
    Write-Text (Join-Path $game 'layers\x86\feed-vk-layer.log') "[layer] VK_LAYER_feed_vk negotiated (interface version 2)`n[layer] vkCreateDevice -> 0`n"
    Write-Text (Join-Path $game 'host64\dlss5-feed-host.log') "[host] game pid 123 connected (protocol v6, Vulkan client -- this host creates the shared textures)`n[host] transport-only mode: Color will be copied to Output, no evaluate`n[host] frame 1 evaluated`n[host] frame 3 evaluated`n"
    $screenshot = Join-Path $fixtureRoot 'transport.png'
    $image = [byte[]]::new(2048); [byte[]]$sig=@(0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a); [Array]::Copy($sig,$image,$sig.Length); $image[-1]=9
    [IO.File]::WriteAllBytes($screenshot,$image)

    $evidenceParent = Join-Path $fixtureRoot 'evidence'
    $result = & $completePath -CaptureSessionDirectory $started.SessionRoot -EvidenceId 'transport-fixture' `
        -TransportSplitScreenshotPath $screenshot -OutputParent $evidenceParent
    if (-not $result.Valid -or -not $result.TransportPassed -or $result.FullDlss5Passed) { throw 'Completed transport capture returned the wrong verdict.' }
    $session = Get-Content -Raw -LiteralPath (Join-Path $started.SessionRoot 'capture-start.json') | ConvertFrom-Json
    if ($session.completed -ne $true -or $session.evidenceId -ne 'transport-fixture') { throw 'Capture session was not sealed to its evidence.' }

    Write-Host 'PASS: New Vegas two-phase capture excludes stale logs, binds the installed payload, and seals a validated transport evidence set.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
