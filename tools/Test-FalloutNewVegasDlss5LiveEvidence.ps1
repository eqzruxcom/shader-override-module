[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifacts = Join-Path $workspace 'artifacts'
$fixtureRoot = Join-Path $artifacts ('test-fnv-live-evidence-' + [Guid]::NewGuid().ToString('N'))
$assertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5LiveEvidence.ps1'
$utf8 = [Text.UTF8Encoding]::new($false)

function Get-Sha256Upper { param([string] $Path) return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant() }
function New-PngFixture {
    param([string] $Path, [byte] $Marker)
    $bytes = [byte[]]::new(2048)
    [byte[]]$signature = @(0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a)
    [Array]::Copy($signature, $bytes, $signature.Length)
    $bytes[$bytes.Length - 1] = $Marker
    [IO.File]::WriteAllBytes($Path, $bytes)
}
function New-EvidenceFixture {
    param([string] $Name, [ValidateSet('transport','neural')][string] $Phase, [bool] $IncludeGuides = $true, [bool] $UseSuperResolution = $false)
    $root = Join-Path $fixtureRoot $Name
    [IO.Directory]::CreateDirectory((Join-Path $root 'logs')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $root 'screenshots')) | Out-Null
    $files = [Collections.Generic.List[object]]::new()
    $texts = [ordered]@{
        dxvkLog = "info: Game: FalloutNV.exe`ninfo: DXVK: v3.0.2`n"
        gameReShadeLog = "ReShade 6.8.0.2155`nVulkan runtime attached`nLoading add-on dlss5-feed.addon32`n"
        feedLayerLog = "[layer] VK_LAYER_feed_vk negotiated (interface version 2)`n[layer] vkCreateDevice -> 0`n"
        feedLog = "[feed32] config: enabled=1 mode=$(if($Phase -eq 'transport'){1}else{2}) hdr=0`n[feed32] host connected (protocol v6, Vulkan client)`n[feed32] shared set ready (Vulkan): 3840x2160 color fmt output fmt`n[feed32] frame 1 delivered (3840x2160, reset=1, Vulkan)`n[feed32] frame 3 delivered (3840x2160, reset=0, Vulkan)`n"
        hostLog = "[host] game pid 123 connected (protocol v6, Vulkan client -- this host creates the shared textures)`n[host] frame 1 evaluated`n[host] frame 3 evaluated`n"
    }
    if ($Phase -eq 'transport') { $texts.hostLog += "[host] transport-only mode: Color will be copied to Output, no evaluate`n" }
    else {
        $texts.hostLog += if ($UseSuperResolution) { "[host] feature ready: 1920x1080 -> 3840x2160 DLSS Quality (synthetic jitter) flags=0`n" } else { "[host] feature ready: 3840x2160 DLAA flags=0`n" }
        if ($IncludeGuides) {
            $texts.feedLog += "[feed] MV probe (centre 64x64, frame 600): mean |mv| 1.5 px, max 20 px, 80% non-zero`n"
            $texts.feedLog += "[feed] Depth probe (4x 32x32, frame 600): min 0.1, max 1, mean 0.5, variance 0.03, 100% finite`n"
        }
        $texts.hostReShadeLog = "signed DLSSNR 310.8.0 NVIDIA runtime initialized`nfeature 18 created via the signed snippet`ninline feature 18 evaluation succeeded (count=1)`ninline feature 18 evaluation succeeded (count=60)`n"
    }
    foreach ($entry in $texts.GetEnumerator()) {
        $path = Join-Path $root ('logs\' + $entry.Key + '.log')
        [IO.File]::WriteAllText($path, [string]$entry.Value, $utf8)
        $files.Add([ordered]@{ role=$entry.Key; relativePath=('logs/' + $entry.Key + '.log'); sha256=Get-Sha256Upper $path; sizeBytes=[long](Get-Item $path).Length })
    }
    if ($Phase -eq 'transport') {
        $path = Join-Path $root 'screenshots\transport.png'; New-PngFixture $path 1
        $files.Add([ordered]@{ role='transportSplitScreenshot'; relativePath='screenshots/transport.png'; sha256=Get-Sha256Upper $path; sizeBytes=[long](Get-Item $path).Length })
    }
    else {
        $off = Join-Path $root 'screenshots\off.png'; $on = Join-Path $root 'screenshots\on.png'
        New-PngFixture $off 2; New-PngFixture $on 3
        $files.Add([ordered]@{ role='neuralOffScreenshot'; relativePath='screenshots/off.png'; sha256=Get-Sha256Upper $off; sizeBytes=[long](Get-Item $off).Length })
        $files.Add([ordered]@{ role='neuralOnScreenshot'; relativePath='screenshots/on.png'; sha256=Get-Sha256Upper $on; sizeBytes=[long](Get-Item $on).Length })
    }
    $manifest = [ordered]@{
        schemaVersion=1; kind='fallout-new-vegas-dlss5-live-evidence'; evidenceId=$Name; adapter='FalloutNewVegas'; phase=$Phase
        capturedUtc=[DateTime]::UtcNow.ToString('o')
        run=[ordered]@{ startedUtc=[DateTime]::UtcNow.AddMinutes(-2).ToString('o'); endedUtc=[DateTime]::UtcNow.AddMinutes(-1).ToString('o') }
        binding=[ordered]@{ packageId='fixture'; packageManifestSha256=('A'*64); installReceiptSha256=('B'*64); gameExecutableSha256=('C'*64); captureStartSha256=('D'*64) }
        files=@($files)
        policy=[ordered]@{ synthetic=$false; gameDirectoryRetained=$false; rawLogsRetained=$true; frameGenerationIncluded=$false }
    }
    [IO.File]::WriteAllText((Join-Path $root 'live-evidence.json'), (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine), $utf8)
    return $root
}

try {
    [IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
    $transport = New-EvidenceFixture 'transport' transport
    $transportResult = & $assertPath -EvidenceDirectory $transport
    if (-not $transportResult.Valid -or -not $transportResult.TransportPassed -or $transportResult.FullDlss5Passed) { throw 'Transport fixture verdict is incorrect.' }

    $neural = New-EvidenceFixture 'neural' neural
    $neuralResult = & $assertPath -EvidenceDirectory $neural
    if (-not $neuralResult.NeuralExecutionPassed -or -not $neuralResult.InputGuidesPassed -or -not $neuralResult.FullDlss5Passed -or
        -not $neuralResult.NativeResolution -or $neuralResult.SuperResolutionUsed) { throw 'Native-resolution neural fixture verdict is incorrect.' }

    $noGuides = New-EvidenceFixture 'neural-no-guides' neural $false
    $noGuidesResult = & $assertPath -EvidenceDirectory $noGuides
    if (-not $noGuidesResult.NeuralExecutionPassed -or $noGuidesResult.InputGuidesPassed -or $noGuidesResult.FullDlss5Passed) {
        throw 'Neural evidence without guide probes was incorrectly promoted to full DLSS5 success.'
    }

    $sr = New-EvidenceFixture 'neural-sr' neural $true $true
    $rejected = $false
    try { $null = & $assertPath -EvidenceDirectory $sr } catch { $rejected = $_.Exception.Message -match 'native-resolution DLAA carrier|Super Resolution' }
    if (-not $rejected) { throw 'Live evidence accepted a Super Resolution carrier.' }

    Add-Content -LiteralPath (Join-Path $transport 'logs\feedLog.log') -Value 'tamper'
    $rejected = $false
    try { $null = & $assertPath -EvidenceDirectory $transport } catch { $rejected = $_.Exception.Message -match 'hash mismatch' }
    if (-not $rejected) { throw 'Live evidence accepted a tampered retained log.' }

    Write-Host 'PASS: New Vegas live evidence is run-bounded, hash-closed, native-resolution-only, and keeps guide validation separate from Feature 18 execution.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
