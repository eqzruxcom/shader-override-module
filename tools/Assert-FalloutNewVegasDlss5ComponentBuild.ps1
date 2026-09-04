[CmdletBinding()]
param([Parameter(Mandatory)][string] $BuildDirectory)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$buildRoot = [IO.Path]::GetFullPath($BuildDirectory).TrimEnd('\')
$manifestPath = Join-Path $buildRoot 'component-build.json'
if (-not $buildRoot.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing component validation outside workspace artifacts: $buildRoot" }
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "component-build.json is missing: $manifestPath" }

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
if ($manifest.schemaVersion -ne 1 -or $manifest.kind -ne 'fallout-new-vegas-dlss5-component-build' -or $manifest.adapter -ne 'FalloutNewVegas') { throw 'Component manifest identity is invalid.' }
if ($manifest.reproducibility.passCount -ne 2 -or $manifest.reproducibility.byteIdentical -ne $true -or $manifest.reproducibility.deterministicLinkOption -ne '/Brepro') { throw 'Component build is not proven byte-identical across two deterministic passes.' }
if ([string]::IsNullOrWhiteSpace([string]$manifest.toolchain.msvcToolset) -or [string]::IsNullOrWhiteSpace([string]$manifest.toolchain.clFileVersion) -or [string]::IsNullOrWhiteSpace([string]$manifest.toolchain.linkFileVersion)) { throw 'Component build does not identify the compiler and linker versions.' }

$records = @($manifest.files)
$recordPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($record in $records) {
    $relative = [string]$record.relativePath
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative.Contains(':') -or $relative -match '(^|[\\/])\.\.([\\/]|$)') { throw "Unsafe component-relative path: $relative" }
    if (-not $recordPaths.Add($relative)) { throw "Duplicate component file record: $relative" }
    $path = Join-Path $buildRoot $relative.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Listed component file is missing: $relative" }
    if ((Get-Sha256Upper $path) -ne ([string]$record.sha256).ToUpperInvariant()) { throw "Component file hash mismatch: $relative" }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$record.sizeBytes) { throw "Component file size mismatch: $relative" }
}
$actual = @(Get-ChildItem -LiteralPath $buildRoot -Recurse -File | Where-Object { $_.FullName -ne $manifestPath } | ForEach-Object { $_.FullName.Substring($buildRoot.Length + 1).Replace('\', '/') })
$unlisted = @($actual | Where-Object { -not $recordPaths.Contains($_) })
if ($unlisted.Count) { throw ('Component build contains unlisted file(s): ' + ($unlisted -join ', ')) }

$lockPath = Join-Path $buildRoot 'dependency-lock.json'
if (-not $recordPaths.Contains('dependency-lock.json') -or (Get-Sha256Upper $lockPath) -ne ([string]$manifest.dependencyLockSha256).ToUpperInvariant()) { throw 'Component dependency lock is missing or does not match the manifest.' }
$lock = Get-Content -Raw -LiteralPath $lockPath | ConvertFrom-Json
if ($lock.schemaVersion -ne 1 -or $lock.adapter -ne 'FalloutNewVegas' -or $lock.sources.dlss5Feeder.revision -ne $manifest.sources.dlss5Feeder.revision -or $lock.sources.vulkanHeaders.revision -ne $manifest.sources.vulkanHeaders.revision -or $lock.sources.nvidiaDlssSdk.revision -ne $manifest.sources.nvidiaDlssSdk.revision) { throw 'Component source revisions do not match the copied dependency lock.' }

$expected = @{
    'bin/x86/dlss5-feed.addon32' = 0x014c
    'bin/x86/VkLayer_feed_vk32.dll' = 0x014c
    'bin/x64/dlss5-feed-host64.exe' = 0x8664
    'bin/x64/VkLayer_feed_vk.dll' = 0x8664
}
foreach ($relative in $expected.Keys) {
    if (-not $recordPaths.Contains($relative)) { throw "Required component output is not inventoried: $relative" }
    if ((Get-PeMachine (Join-Path $buildRoot $relative.Replace('/', '\'))) -ne $expected[$relative]) { throw "Component output has the wrong PE architecture: $relative" }
    $output = @($manifest.outputs | Where-Object { [string]$_.relativePath -ieq $relative })
    if ($output.Count -ne 1 -or ([string]$output[0].sha256).ToUpperInvariant() -ne (Get-Sha256Upper (Join-Path $buildRoot $relative.Replace('/', '\')))) { throw "Component output receipt is invalid: $relative" }
}
foreach ($relative in @('assets/DLSS5_Feed.fx', 'config/x86/VkLayer_feed_vk32.json', 'logs/pass-1.txt', 'logs/pass-2.txt')) {
    if (-not $recordPaths.Contains($relative)) { throw "Component build is missing supporting evidence: $relative" }
}

[pscustomobject]@{
    BuildId = [string]$manifest.buildId
    BuildRoot = $buildRoot
    FileCount = $records.Count
    OutputCount = @($manifest.outputs).Count
    ByteIdentical = $true
    Valid = $true
}
