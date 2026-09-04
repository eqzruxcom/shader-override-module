[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][string]$GameRoot,
    [Parameter(Mandatory)][string]$BundleDirectory,
    [string]$BackupRoot = 'F:\Shader3Dmigoto\Backups',
    [switch]$AllowExternalGameRoot,
    [switch]$AllowExternalBackupRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$game = [IO.Path]::GetFullPath($GameRoot).TrimEnd('\')
$bundle = [IO.Path]::GetFullPath($BundleDirectory).TrimEnd('\')
$backupBase = [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')
$allowedBackupBase = [IO.Path]::GetFullPath('F:\Shader3Dmigoto\Backups').TrimEnd('\')

if (-not (Test-Path -LiteralPath $game -PathType Container)) { throw "Game root is missing: $game" }
if (-not $game.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    if (-not $AllowExternalGameRoot) { throw "External game root requires -AllowExternalGameRoot: $game" }
    if (-not $game.EndsWith('\End\Binaries\Win64', [StringComparison]::OrdinalIgnoreCase)) {
        throw "External game root must be the exact FF7 Remake Win64 directory: $game"
    }
}
if (-not $bundle.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Bundle must remain inside the workspace: $bundle"
}
if (-not $backupBase.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    if (-not $AllowExternalBackupRoot) { throw "External backup root requires -AllowExternalBackupRoot: $backupBase" }
    if (-not ($backupBase.Equals($allowedBackupBase, [StringComparison]::OrdinalIgnoreCase) -or
        $backupBase.StartsWith($allowedBackupBase + '\', [StringComparison]::OrdinalIgnoreCase))) {
        throw "External backup root must remain under $allowedBackupBase"
    }
}

$validated = & (Join-Path $PSScriptRoot 'Assert-DxvkD3D11RuntimeBundle.ps1') -BundleDirectory $bundle
if ($validated.Valid -ne $true -or $validated.Installed -ne $false -or $validated.RuntimeEligible -ne $false -or
    $validated.ReplacementCount -ne 5) {
    throw 'DXVK bundle did not satisfy the reviewed offline contract.'
}

$bundleManifestPath = Join-Path $bundle 'runtime-bundle.json'
$rollbackPlanPath = Join-Path $bundle 'rollback-plan.json'
$bundleManifest = Get-Content -Raw -LiteralPath $bundleManifestPath | ConvertFrom-Json
$rollbackPlan = Get-Content -Raw -LiteralPath $rollbackPlanPath | ConvertFrom-Json
if ($rollbackPlan.packageId -ne $bundleManifest.packageId -or $rollbackPlan.backupBeforeWrite -ne $true -or
    $rollbackPlan.restoreBackedUpFiles -ne $true -or $rollbackPlan.removePackageCreatedFiles -ne $true -or
    $rollbackPlan.verifyRestoredHashes -ne $true) {
    throw 'Bundle rollback plan is not the required reversible contract.'
}

$exe = Join-Path $game 'ff7remake_.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Game executable is missing: $exe" }
$exeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash
if ($exeHash -ne [string]$bundleManifest.adapter.executable.sha256) {
    throw "Game executable does not match the reviewed adapter: $exeHash"
}

function Resolve-SafeRelativePath([string]$Root, [string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\/])\.\.([\/]|$)') {
        throw "Unsafe relative path: $Relative"
    }
    $full = [IO.Path]::GetFullPath((Join-Path $Root $Relative.Replace('/','\')))
    if (-not $full.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes root: $Relative"
    }
    $full
}

$targetPaths = @($rollbackPlan.exactTargetRelativePaths | ForEach-Object { [string]$_ })
if ($targetPaths.Count -ne 8 -or @($targetPaths | Select-Object -Unique).Count -ne 8) {
    throw "Expected exactly eight unique DXVK install targets, found $($targetPaths.Count)."
}
foreach ($relative in $targetPaths) { [void](Resolve-SafeRelativePath -Root $game -Relative $relative) }

$contextPaths = @(
    'd3dx.ini',
    'Mods/ContactShadows.ini',
    'ShaderFixes/08bb8764f1840179-cs.txt',
    'ShaderFixes/0e97888f9a8767da-cs.txt',
    'ShaderFixes/5a9fbefe0ab6f815-cs.txt',
    'ShaderFixes/62b33a2d1e505241-cs.txt',
    'ShaderFixes/c30cdc8365df9840-cs.txt'
)
foreach ($relative in $contextPaths) {
    $path = Resolve-SafeRelativePath -Root $game -Relative $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required native comparison context is missing: $relative" }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$snapshot = Join-Path $backupBase "FF7Remake-DXVK-preinstall-$stamp"
if (Test-Path -LiteralPath $snapshot) { throw "Backup snapshot already exists: $snapshot" }
if (-not $PSCmdlet.ShouldProcess($snapshot, 'Create exact hash-verified pre-DXVK backup snapshot')) { return }

[IO.Directory]::CreateDirectory($snapshot) | Out-Null
$targetBackupRoot = Join-Path $snapshot 'install-targets'
$contextBackupRoot = Join-Path $snapshot 'native-context'
$provenanceRoot = Join-Path $snapshot 'provenance'
[IO.Directory]::CreateDirectory($targetBackupRoot) | Out-Null
[IO.Directory]::CreateDirectory($contextBackupRoot) | Out-Null
[IO.Directory]::CreateDirectory($provenanceRoot) | Out-Null

$targets = [Collections.Generic.List[object]]::new()
foreach ($relative in $targetPaths) {
    $sourcePath = Resolve-SafeRelativePath -Root $game -Relative $relative
    $exists = Test-Path -LiteralPath $sourcePath -PathType Leaf
    $record = [ordered]@{relativePath=$relative;existedBefore=$exists;backupPath=$null;sha256=$null;sizeBytes=$null}
    if ($exists) {
        $destination = Resolve-SafeRelativePath -Root $targetBackupRoot -Relative $relative
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
        [IO.File]::Copy($sourcePath, $destination, $false)
        $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash
        $backupHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash
        if ($sourceHash -ne $backupHash) { throw "Backup hash mismatch: $relative" }
        $record.backupPath = [IO.Path]::GetRelativePath($snapshot, $destination).Replace('\','/')
        $record.sha256 = $sourceHash
        $record.sizeBytes = (Get-Item -LiteralPath $sourcePath).Length
    }
    $targets.Add($record)
}

$context = [Collections.Generic.List[object]]::new()
foreach ($relative in $contextPaths) {
    $sourcePath = Resolve-SafeRelativePath -Root $game -Relative $relative
    $destination = Resolve-SafeRelativePath -Root $contextBackupRoot -Relative $relative
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    [IO.File]::Copy($sourcePath, $destination, $false)
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash -ne $sourceHash) {
        throw "Native-context backup hash mismatch: $relative"
    }
    $context.Add([ordered]@{
        relativePath=$relative
        backupPath=[IO.Path]::GetRelativePath($snapshot, $destination).Replace('\','/')
        sha256=$sourceHash
        sizeBytes=(Get-Item -LiteralPath $sourcePath).Length
    })
}

foreach ($sourcePath in @($bundleManifestPath,$rollbackPlanPath)) {
    $destination = Join-Path $provenanceRoot (Split-Path -Leaf $sourcePath)
    [IO.File]::Copy($sourcePath, $destination, $false)
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash -ne
        (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash) {
        throw "Bundle provenance backup hash mismatch: $sourcePath"
    }
}

$snapshotManifest = [ordered]@{
    schemaVersion=1
    kind='ff7-remake-dxvk-preinstall-backup'
    complete=$true
    createdUtc=[DateTime]::UtcNow.ToString('o')
    gameRoot=$game
    gameExecutable=[ordered]@{relativePath='ff7remake_.exe';sha256=$exeHash}
    packageId=[string]$bundleManifest.packageId
    bundleRoot=$bundle
    bundleManifestSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $bundleManifestPath).Hash
    rollbackPlanSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $rollbackPlanPath).Hash
    installTargets=@($targets)
    nativeComparisonContext=@($context)
    policy=[ordered]@{dxvkInstalled=$false;gameFilesModified=$false;restoreBeforeDelete=$true;verifyHashes=$true}
}
$snapshotManifestPath = Join-Path $snapshot 'preinstall-backup.json'
[IO.File]::WriteAllText($snapshotManifestPath, (($snapshotManifest | ConvertTo-Json -Depth 8) + "`r`n"), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Status='complete'
    Snapshot=$snapshot
    Manifest=$snapshotManifestPath
    InstallTargets=$targets.Count
    ExistingTargets=@($targets | Where-Object existedBefore).Count
    AbsentTargets=@($targets | Where-Object { -not $_.existedBefore }).Count
    ContextFiles=$context.Count
    DxvkInstalled=$false
    GameFilesModified=$false
}
