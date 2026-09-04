[CmdletBinding()]
param(
    [string]$BundleDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\dxvk-d3d11-runtime-bundles\FF7RemakeIntergrade-DXVKContactFamily5-offline-20260901-v1'),
    [string]$SnapshotDirectory = 'F:\Shader3Dmigoto\Backups\FF7Remake-DXVK-preinstall-20260902-084200-915',
    [string]$RealGameExecutable = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\ff7remake_.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = Join-Path $workspace 'artifacts'
$testRoot = Join-Path $artifacts ('.intergrade-dxvk-live-transition-' + [Guid]::NewGuid().ToString('N'))
$fixtureGame = Join-Path $testRoot 'Game\End\Binaries\Win64'
$fixtureSnapshot = Join-Path $testRoot 'Snapshot'
$utf8 = [Text.UTF8Encoding]::new($false)
$passed = $false

function Resolve-UnderRoot([string]$Root, [string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or
        $Relative -match '(^|[\\/])\.\.([\\/]|$)') { throw "Unsafe relative path: $Relative" }
    $full = [IO.Path]::GetFullPath((Join-Path $Root $Relative.Replace('/','\')))
    if (-not $full.StartsWith($Root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes fixture root: $Relative"
    }
    $full
}

try {
    $bundle = [IO.Path]::GetFullPath($BundleDirectory).TrimEnd('\')
    $sourceSnapshot = [IO.Path]::GetFullPath($SnapshotDirectory).TrimEnd('\')
    if (-not $bundle.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Bundle must remain inside the workspace.'
    }
    if (-not (Test-Path -LiteralPath $sourceSnapshot -PathType Container)) { throw 'Source snapshot is missing.' }
    if (-not (Test-Path -LiteralPath $RealGameExecutable -PathType Leaf)) { throw 'Reviewed game executable is missing.' }

    [IO.Directory]::CreateDirectory($fixtureGame) | Out-Null
    Copy-Item -LiteralPath $sourceSnapshot -Destination $fixtureSnapshot -Recurse

    $snapshotManifestPath = Join-Path $fixtureSnapshot 'preinstall-backup.json'
    $snapshotManifest = Get-Content -Raw -LiteralPath $snapshotManifestPath | ConvertFrom-Json
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $RealGameExecutable).Hash -ne
        [string]$snapshotManifest.gameExecutable.sha256) { throw 'Real executable does not match snapshot fingerprint.' }

    $fixtureExe = Join-Path $fixtureGame 'ff7remake_.exe'
    New-Item -ItemType HardLink -Path $fixtureExe -Target $RealGameExecutable | Out-Null
    $snapshotManifest.gameRoot = $fixtureGame
    [IO.File]::WriteAllText($snapshotManifestPath,
        (($snapshotManifest | ConvertTo-Json -Depth 8) + "`r`n"), $utf8)

    foreach ($entry in @($snapshotManifest.installTargets | Where-Object existedBefore)) {
        $source = Resolve-UnderRoot -Root $fixtureSnapshot -Relative ([string]$entry.backupPath)
        $destination = Resolve-UnderRoot -Root $fixtureGame -Relative ([string]$entry.relativePath)
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
        [IO.File]::Copy($source, $destination, $false)
    }
    foreach ($entry in @($snapshotManifest.nativeComparisonContext)) {
        $source = Resolve-UnderRoot -Root $fixtureSnapshot -Relative ([string]$entry.backupPath)
        $destination = Resolve-UnderRoot -Root $fixtureGame -Relative ([string]$entry.relativePath)
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
        [IO.File]::Copy($source, $destination, $false)
    }

    $nativeContextBefore = @($snapshotManifest.nativeComparisonContext | ForEach-Object {
        $path = Resolve-UnderRoot -Root $fixtureGame -Relative ([string]$_.relativePath)
        [pscustomobject]@{ RelativePath=[string]$_.relativePath; Sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash }
    })

    # The real process may be open while this isolated fixture runs. Override
    # process discovery only in this test scope; production installer behavior
    # is separately proven to refuse the running game.
    function Get-Process {
        [CmdletBinding()]
        param([string]$Name)
        @()
    }

    $installResult = & (Join-Path $PSScriptRoot 'Install-IntergradeDxvkLiveTest.ps1') `
        -GameRoot $fixtureGame -BundleDirectory $bundle -SnapshotDirectory $fixtureSnapshot `
        -AcknowledgeReplaces3DMigotoD3D11 -Confirm:$false
    if ($installResult.Status -ne 'installed' -or $installResult.InstalledTargets -ne 8 -or
        $installResult.Replaces3DMigotoD3D11 -ne $true) { throw 'Fixture installation did not report the expected result.' }

    $bundleManifest = Get-Content -Raw -LiteralPath (Join-Path $bundle 'runtime-bundle.json') | ConvertFrom-Json
    $targetHashes = @{}
    foreach ($entry in @($bundleManifest.files)) { $targetHashes[[string]$entry.relativePath] = [string]$entry.sha256 }
    foreach ($relative in @((Get-Content -Raw -LiteralPath (Join-Path $bundle 'rollback-plan.json') | ConvertFrom-Json).exactTargetRelativePaths)) {
        $path = Resolve-UnderRoot -Root $fixtureGame -Relative ([string]$relative)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$targetHashes[[string]$relative]) {
            throw "Fixture install hash verification failed: $relative"
        }
    }

    $restoreResult = & (Join-Path $PSScriptRoot 'Restore-IntergradeDxvkLiveTest.ps1') `
        -GameRoot $fixtureGame -SnapshotDirectory $fixtureSnapshot -Confirm:$false
    if ($restoreResult.Status -ne 'restored' -or $restoreResult.ChangedFiles -ne 8 -or
        $restoreResult.VerifiedTargets -ne 8) { throw 'Fixture rollback did not report the expected result.' }

    foreach ($entry in @($snapshotManifest.installTargets)) {
        $path = Resolve-UnderRoot -Root $fixtureGame -Relative ([string]$entry.relativePath)
        if ($entry.existedBefore -eq $true) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
                (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$entry.sha256) {
                throw "Fixture rollback failed to restore native target: $($entry.relativePath)"
            }
        } elseif (Test-Path -LiteralPath $path) {
            throw "Fixture rollback failed to remove package-created target: $($entry.relativePath)"
        }
    }
    foreach ($entry in $nativeContextBefore) {
        $path = Resolve-UnderRoot -Root $fixtureGame -Relative ([string]$entry.RelativePath)
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$entry.Sha256) {
            throw "Native comparison context changed during fixture transition: $($entry.RelativePath)"
        }
    }

    $tampered = Join-Path $fixtureGame 'dxgi.dll'
    [IO.File]::WriteAllBytes($tampered, [byte[]](0x44,0x52,0x49,0x46,0x54))
    $rejected = $false
    try {
        & (Join-Path $PSScriptRoot 'Restore-IntergradeDxvkLiveTest.ps1') `
            -GameRoot $fixtureGame -SnapshotDirectory $fixtureSnapshot -Confirm:$false | Out-Null
    } catch {
        if ($_.Exception.Message -match 'Refusing to delete non-package file during rollback: dxgi.dll') { $rejected = $true } else { throw }
    }
    if (-not $rejected) { throw 'Rollback did not reject a drifted package-created target.' }
    Remove-Item -LiteralPath $tampered -Force

    $passed = $true
    [pscustomobject]@{
        Passed=$true
        InstalledTargets=8
        RestoredTargets=8
        NativeContextFiles=$nativeContextBefore.Count
        DriftedDeleteRejected=$true
        RealGameDirectoryTouched=$false
    }
} finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        $resolved = [IO.Path]::GetFullPath($testRoot).TrimEnd('\')
        if (-not $resolved.StartsWith($artifacts.TrimEnd('\') + '\.intergrade-dxvk-live-transition-',
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing unsafe fixture cleanup: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    if (-not $passed -and $Error.Count -eq 0) { throw 'DXVK live-transition fixture did not complete.' }
}
