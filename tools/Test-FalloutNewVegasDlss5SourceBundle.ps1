[CmdletBinding()]
param([Parameter(Mandatory)][string] $ComponentBuildDirectory)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$testRoot = Join-Path $artifactsRoot ('fallout-new-vegas-source-bundle-test-' + [Guid]::NewGuid().ToString('N'))
$fixtureRoot = Join-Path $testRoot 'fixtures'
$bundleParent = Join-Path $testRoot 'bundles'
$componentAssertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5ComponentBuild.ps1'
$stagePath = Join-Path $PSScriptRoot 'New-FalloutNewVegasDlss5Bundle.ps1'
$bundleAssertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5Bundle.ps1'
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
    $component = & $componentAssertPath -BuildDirectory $ComponentBuildDirectory
    $componentRoot = [string]$component.BuildRoot

    $dxvk = Join-Path $fixtureRoot 'dxvk\d3d9.dll'
    $reshade32 = Join-Path $fixtureRoot 'reshade\ReShade32.dll'
    $reshade64 = Join-Path $fixtureRoot 'reshade\ReShade64.dll'
    Write-TestPe $dxvk x86 0x31
    Write-TestPe $reshade32 x86 0x32
    Write-TestPe $reshade64 x64 0x33

    $reshadeManifest = Join-Path $fixtureRoot 'reshade\ReShade32.json'
    Write-TextFile $reshadeManifest '{"file_format_version":"1.0.0","layer":{"name":"VK_LAYER_reshade","library_path":".\\ReShade32.dll"}}'
    $framework = Join-Path $fixtureRoot 'framework'
    foreach ($name in @('ReShade.fxh', 'ReShadeUI.fxh', 'DrawText.fxh')) {
        Write-TextFile (Join-Path $framework $name) ('// fixture ' + $name)
    }
    $lumenite = Join-Path $fixtureRoot 'lumenite'
    Write-TextFile (Join-Path $lumenite 'Shaders\lumenite_Kernel.fx') 'technique Lumenite_Kernel { pass { } }'
    Write-TextFile (Join-Path $lumenite 'Shaders\include\lumenite_Helpers.fxh') '// fixture include'

    $arguments = @{
        DxvkD3D9Path = $dxvk
        FeederAddon32Path = Join-Path $componentRoot 'bin\x86\dlss5-feed.addon32'
        FeederComponentBuildDirectory = $componentRoot
        FeederHost64Path = Join-Path $componentRoot 'bin\x64\dlss5-feed-host64.exe'
        FeederEffectPath = Join-Path $componentRoot 'assets\DLSS5_Feed.fx'
        FeedLayer32Path = Join-Path $componentRoot 'bin\x86\VkLayer_feed_vk32.dll'
        FeedLayer32ManifestPath = Join-Path $componentRoot 'config\x86\VkLayer_feed_vk32.json'
        ReShade32Path = $reshade32
        ReShade32ManifestPath = $reshadeManifest
        ReShade64Path = $reshade64
        ReShadeFrameworkRoot = $framework
        LumeniteRoot = $lumenite
        PackageId = 'source-built-positive'
        OutputParent = $bundleParent
    }
    $result = & $stagePath @arguments
    if (-not $result.Valid) { throw 'Source-built transport bundle did not validate.' }

    $bundle = Join-Path $bundleParent 'source-built-positive'
    $manifestPath = Join-Path $bundle 'runtime-bundle.json'
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    if ($manifest.componentBuild.buildId -ne $component.BuildId) {
        throw 'Transport bundle did not retain the validated component build identity.'
    }
    foreach ($relative in @('provenance/feeder-component-build.json', 'provenance/feeder-dependency-lock.json')) {
        if (@($manifest.files | Where-Object { $_.relativePath -eq $relative }).Count -ne 1) {
            throw "Source-built transport bundle did not inventory $relative"
        }
    }

    $payload = Join-Path $bundle 'dlss5-feed.addon32'
    $payloadBytes = [IO.File]::ReadAllBytes($payload)
    $payloadBytes[0x100] = $payloadBytes[0x100] -bxor 1
    [IO.File]::WriteAllBytes($payload, $payloadBytes)
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    $payloadRecord = @($manifest.files | Where-Object { $_.relativePath -eq 'dlss5-feed.addon32' })
    if ($payloadRecord.Count -ne 1) { throw 'Source-built bundle lost its Feeder payload record.' }
    $payloadRecord[0].sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $payload).Hash
    [IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 10) + [Environment]::NewLine), $utf8)
    $rejected = $false
    try { $null = & $bundleAssertPath -BundleDirectory $bundle } catch {
        $rejected = $_.Exception.Message -match 'does not match component-build provenance'
    }
    if (-not $rejected) {
        throw 'Bundle validator accepted a re-hashed substitution of a source-built Feeder payload.'
    }

    $wrongAddon = Join-Path $fixtureRoot 'wrong\dlss5-feed.addon32'
    Write-TestPe $wrongAddon x86 0x61
    $wrongArguments = $arguments.Clone()
    $wrongArguments.FeederAddon32Path = $wrongAddon
    $wrongArguments.PackageId = 'source-built-wrong-input'
    $rejected = $false
    try { $null = & $stagePath @wrongArguments } catch {
        $rejected = $_.Exception.Message -match 'does not come from the validated component build'
    }
    if (-not $rejected) {
        throw 'Bundle staging accepted a Feeder payload outside the validated component build.'
    }

    Write-Host 'PASS: the transport bundle inventories its source-build receipt, binds every Feeder payload to it, and rejects re-hashed substitution.'
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
