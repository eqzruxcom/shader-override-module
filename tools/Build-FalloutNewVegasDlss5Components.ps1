[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')][string] $BuildId,
    [string] $FeederSource = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\upstream\DLSS5-Feeder'),
    [string] $VulkanHeadersSource = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\upstream\Vulkan-Headers'),
    [string] $NvidiaDlssSource = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\upstream\NVIDIA-DLSS'),
    [string] $DependencyLockPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Adapters\FalloutNewVegas\dependency-lock.json'),
    [string] $OutputParent = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\fallout-new-vegas-dlss5-component-builds')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$outputParentFull = [IO.Path]::GetFullPath($OutputParent).TrimEnd('\')
$finalRoot = Join-Path $outputParentFull $BuildId
$temporaryRoot = Join-Path $outputParentFull ('.staging-' + $BuildId + '-' + [Guid]::NewGuid().ToString('N'))
$assertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5ComponentBuild.ps1'
$utf8 = [Text.UTF8Encoding]::new($false)
$moved = $false

function Get-Sha256Upper {
    param([string] $Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Resolve-Directory {
    param([string] $Path, [string] $Description)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) { throw "$Description is not a directory: $resolved" }
    return $resolved
}

function Assert-GitSource {
    param([string] $Path, [object] $Expected, [string] $Description)
    if (-not (Test-Path -LiteralPath (Join-Path $Path '.git'))) { throw "$Description is not a Git checkout: $Path" }
    $head = (& git -C $Path rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $head -ne [string]$Expected.revision) { throw "$Description revision mismatch: expected $($Expected.revision), got $head" }
    & git -C $Path diff --quiet --ignore-submodules --
    if ($LASTEXITCODE -ne 0) { throw "$Description has tracked working-tree changes: $Path" }
    & git -C $Path diff --cached --quiet --ignore-submodules --
    if ($LASTEXITCODE -ne 0) { throw "$Description has staged changes: $Path" }
    $origin = (& git -C $Path remote get-url origin).Trim().TrimEnd('/')
    $expectedOrigin = ([string]$Expected.repository).TrimEnd('/')
    if ($origin.EndsWith('.git', [StringComparison]::OrdinalIgnoreCase)) { $origin = $origin.Substring(0, $origin.Length - 4) }
    if ($expectedOrigin.EndsWith('.git', [StringComparison]::OrdinalIgnoreCase)) { $expectedOrigin = $expectedOrigin.Substring(0, $expectedOrigin.Length - 4) }
    if (-not $origin.Equals($expectedOrigin, [StringComparison]::OrdinalIgnoreCase)) { throw "$Description origin mismatch: expected $expectedOrigin, got $origin" }
}

function Replace-Exact {
    param([string] $Path, [string] $Old, [string] $New, [int] $ExpectedCount)
    $text = [IO.File]::ReadAllText($Path)
    $count = ([regex]::Matches($text, [regex]::Escape($Old))).Count
    if ($count -ne $ExpectedCount) { throw "Deterministic-link patch mismatch in $Path; expected $ExpectedCount occurrence(s), got $count" }
    [IO.File]::WriteAllText($Path, $text.Replace($Old, $New), $utf8)
}

function Get-PeMachine {
    param([string] $Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $pe = if ($bytes.Length -ge 0x88 -and $bytes[0] -eq 0x4d -and $bytes[1] -eq 0x5a) { [BitConverter]::ToInt32($bytes, 0x3c) } else { -1 }
    if ($pe -lt 0 -or $pe + 6 -gt $bytes.Length -or $bytes[$pe] -ne 0x50 -or $bytes[$pe + 1] -ne 0x45) { throw "Invalid PE image: $Path" }
    return [BitConverter]::ToUInt16($bytes, $pe + 4)
}

function Invoke-BuildPass {
    param([int] $Pass, [string] $Root, [string] $Feeder, [string] $Vulkan, [string] $Ngx, [object] $Lock)
    $clone = Join-Path $Root ("source-$Pass")
    & git clone --quiet --no-hardlinks --no-checkout -- $Feeder $clone
    if ($LASTEXITCODE -ne 0) { throw "Local Feeder clone failed for pass $Pass" }
    & git -C $clone checkout --quiet --detach ([string]$Lock.sources.dlss5Feeder.revision)
    if ($LASTEXITCODE -ne 0) { throw "Feeder checkout failed for pass $Pass" }

    $vulkanDestination = Join-Path $clone 'external\vulkan'
    foreach ($directory in @('vulkan', 'vk_video')) {
        Copy-Item -LiteralPath (Join-Path $Vulkan ('include\' + $directory)) -Destination $vulkanDestination -Recurse
    }
    $ngxDestination = Join-Path $clone 'external\ngx'
    foreach ($header in Get-ChildItem -LiteralPath (Join-Path $Ngx 'include') -Filter '*.h' -File) { Copy-Item -LiteralPath $header.FullName -Destination $ngxDestination }
    $ngxLibDestination = Join-Path $ngxDestination 'libs'
    [IO.Directory]::CreateDirectory($ngxLibDestination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $Ngx 'lib\Windows_x86_64\x64\nvsdk_ngx_d.lib') -Destination $ngxLibDestination

    Replace-Exact (Join-Path $clone 'build-addon32.bat') '/link /OUT:' '/link /Brepro /OUT:' 1
    Replace-Exact (Join-Path $clone 'host\build-host.bat') '/link ..\external\ngx' '/link /Brepro ..\external\ngx' 1
    Replace-Exact (Join-Path $clone 'layer\build-layer.bat') '/link /OUT:' '/link /Brepro /OUT:' 2
    Replace-Exact (Join-Path $clone 'src\dlss5-feed32.cpp') `
        'Log("dlss5-feed32 %s (built %s %s) attached%s.", FEED_VERSION, __DATE__, __TIME__,' `
        'Log("dlss5-feed32 %s (source 7927553) attached%s.", FEED_VERSION,' 1
    Replace-Exact (Join-Path $clone 'host\dlss5-feed-host64.cpp') `
        'Log("dlss5-feed-host64 (built %s %s)", __DATE__, __TIME__);' `
        'Log("dlss5-feed-host64 (source 7927553)");' 1

    $lines = [Collections.Generic.List[string]]::new()
    foreach ($batch in @('build-addon32.bat', 'host\build-host.bat', 'layer\build-layer.bat')) {
        $batchPath = Join-Path $clone $batch
        $lines.Add("== $batch ==")
        $result = @(& $env:ComSpec /d /c "`"$batchPath`"" 2>&1)
        foreach ($line in $result) { $lines.Add([string]$line) }
        if ($LASTEXITCODE -ne 0) { throw "Build pass $Pass failed in $batch (exit $LASTEXITCODE)" }
    }
    $logPath = Join-Path $Root ("pass-$Pass.txt")
    [IO.File]::WriteAllLines($logPath, $lines, $utf8)

    $outputs = [ordered]@{
        'bin/x86/dlss5-feed.addon32' = (Join-Path $clone 'build\dlss5-feed.addon32')
        'bin/x86/VkLayer_feed_vk32.dll' = (Join-Path $clone 'layer\x86\VkLayer_feed_vk32.dll')
        'bin/x64/dlss5-feed-host64.exe' = (Join-Path $clone 'host\dlss5-feed-host64.exe')
        'bin/x64/VkLayer_feed_vk.dll' = (Join-Path $clone 'layer\VkLayer_feed_vk.dll')
    }
    foreach ($path in $outputs.Values) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Build pass $Pass omitted output: $path" } }
    return [pscustomobject]@{ Clone = $clone; Log = $logPath; Outputs = $outputs }
}

if (-not ($outputParentFull -eq $artifactsRoot -or $outputParentFull.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase))) { throw "Refusing component output outside workspace artifacts: $outputParentFull" }
if (Test-Path -LiteralPath $finalRoot) { throw "Refusing to overwrite an existing component build: $finalRoot" }
$lockPath = (Resolve-Path -LiteralPath $DependencyLockPath).Path
$lock = Get-Content -Raw -LiteralPath $lockPath | ConvertFrom-Json
if ($lock.schemaVersion -ne 1 -or $lock.adapter -ne 'FalloutNewVegas' -or $lock.build.passes -ne 2 -or $lock.build.deterministicLinkOption -ne '/Brepro') { throw 'Dependency lock does not define the expected deterministic New Vegas component build.' }
$feeder = Resolve-Directory $FeederSource 'DLSS5-Feeder source'
$vulkan = Resolve-Directory $VulkanHeadersSource 'Vulkan-Headers source'
$ngx = Resolve-Directory $NvidiaDlssSource 'NVIDIA DLSS SDK source'
Assert-GitSource $feeder $lock.sources.dlss5Feeder 'DLSS5-Feeder'
Assert-GitSource $vulkan $lock.sources.vulkanHeaders 'Vulkan-Headers'
Assert-GitSource $ngx $lock.sources.nvidiaDlssSdk 'NVIDIA DLSS SDK'

$vsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vsWhere -PathType Leaf)) { throw 'Visual Studio Installer vswhere.exe is missing.' }
$vsInstall = (& $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
if ([string]::IsNullOrWhiteSpace($vsInstall)) { throw 'Visual Studio C++ x86/x64 tools are not installed.' }
$toolsetRoot = Get-ChildItem -LiteralPath (Join-Path $vsInstall 'VC\Tools\MSVC') -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if ($null -eq $toolsetRoot) { throw 'No MSVC toolset directory was found.' }
$clPath = Join-Path $toolsetRoot.FullName 'bin\Hostx64\x64\cl.exe'
$linkPath = Join-Path $toolsetRoot.FullName 'bin\Hostx64\x64\link.exe'
if (-not (Test-Path -LiteralPath $clPath -PathType Leaf) -or -not (Test-Path -LiteralPath $linkPath -PathType Leaf)) { throw 'Expected Hostx64 MSVC compiler/linker binaries are missing.' }
$toolchain = [ordered]@{
    visualStudioInstallation = $vsInstall
    msvcToolset = $toolsetRoot.Name
    clFileVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($clPath).FileVersion
    linkFileVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($linkPath).FileVersion
}

try {
    [IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
    $pass1 = Invoke-BuildPass 1 $temporaryRoot $feeder $vulkan $ngx $lock
    $pass2 = Invoke-BuildPass 2 $temporaryRoot $feeder $vulkan $ngx $lock
    $outputRecords = [Collections.Generic.List[object]]::new()
    foreach ($relative in $pass1.Outputs.Keys) {
        $first = [string]$pass1.Outputs[$relative]
        $second = [string]$pass2.Outputs[$relative]
        $firstHash = Get-Sha256Upper $first
        $secondHash = Get-Sha256Upper $second
        if ($firstHash -ne $secondHash) { throw "Two-pass reproducibility failure for $relative`: $firstHash != $secondHash" }
        $machine = Get-PeMachine $first
        $expectedMachine = if ($relative.StartsWith('bin/x86/')) { 0x014c } else { 0x8664 }
        if ($machine -ne $expectedMachine) { throw ('Wrong PE machine for {0}: 0x{1:X4}' -f $relative, $machine) }
        $destination = Join-Path $temporaryRoot $relative.Replace('/', '\')
        [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
        Copy-Item -LiteralPath $first -Destination $destination
        $outputRecords.Add([ordered]@{ relativePath = $relative; sha256 = $firstHash; sizeBytes = [long](Get-Item -LiteralPath $first).Length; machine = if ($expectedMachine -eq 0x014c) { 'x86' } else { 'x64' } })
    }
    [IO.Directory]::CreateDirectory((Join-Path $temporaryRoot 'logs')) | Out-Null
    Copy-Item -LiteralPath $pass1.Log -Destination (Join-Path $temporaryRoot 'logs\pass-1.txt')
    Copy-Item -LiteralPath $pass2.Log -Destination (Join-Path $temporaryRoot 'logs\pass-2.txt')
    [IO.Directory]::CreateDirectory((Join-Path $temporaryRoot 'assets')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $temporaryRoot 'config\x86')) | Out-Null
    Copy-Item -LiteralPath (Join-Path $pass1.Clone 'shaders\DLSS5_Feed.fx') -Destination (Join-Path $temporaryRoot 'assets\DLSS5_Feed.fx')
    Copy-Item -LiteralPath (Join-Path $pass1.Clone 'layer\x86\VkLayer_feed_vk32.json') -Destination (Join-Path $temporaryRoot 'config\x86\VkLayer_feed_vk32.json')
    Copy-Item -LiteralPath $lockPath -Destination (Join-Path $temporaryRoot 'dependency-lock.json')

    foreach ($clone in @($pass1.Clone, $pass2.Clone)) { Remove-Item -LiteralPath $clone -Recurse -Force }
    Remove-Item -LiteralPath $pass1.Log, $pass2.Log -Force

    $files = @(Get-ChildItem -LiteralPath $temporaryRoot -Recurse -File | Sort-Object FullName | ForEach-Object { [ordered]@{ relativePath = $_.FullName.Substring($temporaryRoot.Length + 1).Replace('\', '/'); sha256 = Get-Sha256Upper $_.FullName; sizeBytes = [long]$_.Length } })
    $manifest = [ordered]@{
        schemaVersion = 1
        kind = 'fallout-new-vegas-dlss5-component-build'
        adapter = 'FalloutNewVegas'
        buildId = $BuildId
        createdUtc = [DateTime]::UtcNow.ToString('o')
        dependencyLockSha256 = Get-Sha256Upper (Join-Path $temporaryRoot 'dependency-lock.json')
        sources = [ordered]@{
            dlss5Feeder = [ordered]@{ repository = [string]$lock.sources.dlss5Feeder.repository; revision = [string]$lock.sources.dlss5Feeder.revision }
            vulkanHeaders = [ordered]@{ repository = [string]$lock.sources.vulkanHeaders.repository; revision = [string]$lock.sources.vulkanHeaders.revision }
            nvidiaDlssSdk = [ordered]@{ repository = [string]$lock.sources.nvidiaDlssSdk.repository; revision = [string]$lock.sources.nvidiaDlssSdk.revision }
        }
        toolchain = $toolchain
        reproducibility = [ordered]@{ passCount = 2; byteIdentical = $true; deterministicLinkOption = '/Brepro' }
        outputs = @($outputRecords)
        files = @($files)
    }
    [IO.File]::WriteAllText((Join-Path $temporaryRoot 'component-build.json'), (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine), $utf8)
    [IO.Directory]::CreateDirectory($outputParentFull) | Out-Null
    [IO.Directory]::Move($temporaryRoot, $finalRoot)
    $moved = $true
    $validated = & $assertPath -BuildDirectory $finalRoot
    Write-Host "PASS: two byte-identical deterministic Feeder builds staged as '$BuildId'."
    return $validated
}
catch {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
    if ($moved -and (Test-Path -LiteralPath $finalRoot -PathType Container)) { Remove-Item -LiteralPath $finalRoot -Recurse -Force }
    throw
}
