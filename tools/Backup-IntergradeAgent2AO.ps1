[CmdletBinding()]
param(
    [string]$BackupRoot = 'F:\Shader3Dmigoto\Agent 2'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$allowedRoot = [IO.Path]::GetFullPath('F:\Shader3Dmigoto\Agent 2').TrimEnd('\')
$backupFull = [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')
if (-not $backupFull.Equals($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Backup root must be exactly $allowedRoot"
}

function Assert-NoReparse([string]$Path) {
    $probe = [IO.Path]::GetFullPath($Path)
    while ($probe) {
        if (Test-Path -LiteralPath $probe) {
            if ((Get-Item -Force -LiteralPath $probe).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse path is not allowed: $probe"
            }
        }
        $probe = [IO.Path]::GetDirectoryName($probe)
    }
}

$entries = [Collections.Generic.List[object]]::new()
$relativeNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

function Add-BackupFile([string]$RelativePath) {
    $source = [IO.Path]::GetFullPath((Join-Path $projectRoot $RelativePath))
    $projectPrefix = $projectRoot.TrimEnd('\') + '\'
    if (-not $source.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Source escaped project root: $RelativePath"
    }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required Agent 2 backup file is missing: $RelativePath"
    }
    Assert-NoReparse $source
    $normalized = $RelativePath -replace '/', '\'
    if (-not $relativeNames.Add($normalized)) { return }
    $item = Get-Item -Force -LiteralPath $source
    $entries.Add([pscustomobject]@{
        source = $source
        relativePath = $normalized
        bytes = $item.Length
    })
}

function Add-BackupTree([string]$RelativePath) {
    $tree = [IO.Path]::GetFullPath((Join-Path $projectRoot $RelativePath))
    if (-not (Test-Path -LiteralPath $tree -PathType Container)) {
        throw "Required Agent 2 backup tree is missing: $RelativePath"
    }
    Assert-NoReparse $tree
    foreach ($item in Get-ChildItem -Force -LiteralPath $tree -Recurse -File) {
        Assert-NoReparse $item.FullName
        $child = [IO.Path]::GetRelativePath($tree, $item.FullName)
        Add-BackupFile (Join-Path $RelativePath $child)
    }
}

foreach ($relative in @(
    'THIRD_PARTY_NOTICES.md',
    'docs\agent2-ao-control-integration.md',
    'docs\agent2-ao-shader-test-matrix.md',
    'docs\agent2-indirect-lighting-strength-review.md',
    'docs\agent2-open-source-ssgi-donor.md',
    'docs\agent2-r3d-ssgi-remake-integration.md',
    'licenses\R3D-Zlib.txt',
    'reference\external\r3d-provenance.json',
    'reference\external\r3d\LICENSE',
    'reference\external\r3d\shaders\prepare\ssgi.frag',
    'reference\external\r3d\shaders\prepare\ssil.frag',
    'reference\external\r3d\shaders\prepare\denoiser_atrous.frag',
    'reference\external\r3d\shaders\deferred\ambient.frag',
    'reference\external\r3d\src\r3d_draw.c',
    'src\Adapters\FF7RemakeIntergrade\R3DSSGICompositeE2AA_ps.hlsl',
    'src\Adapters\FF7RemakeIntergrade\R3DSSGITraceE2AA_ps.hlsl',
    'src\Effects\Lighting\R3DSSGIDenoise_SM5.hlsl',
    'src\Effects\Lighting\R3DSSGI_SM5.hlsl',
    'tools\Analyze-IntergradeAOControlOwnership.ps1',
    'tools\Analyze-IntergradeAOShaderTestMatrix.ps1',
    'tools\Analyze-IntergradeR3DSSGIInjection.ps1',
    'tools\Analyze-IntergradeR3DSSGILiveTopology.ps1',
    'tools\Backup-IntergradeAgent2AO.ps1',
    'tools\Get-IntergradeR3DSSGIF2StandaloneReloadStatus.ps1',
    'tools\New-IntergradeR3DSSGIF2EvidenceLedger.ps1',
    'tools\New-IntergradeR3DSSGIF2OwnerIntegrationPack.ps1',
    'tools\New-IntergradeR3DSSGIF2StandalonePack.ps1',
    'tools\New-IntergradeR3DSSGIF2StandaloneReloadBaseline.ps1',
    'tools\New-IntergradeR3DSSGIPrototype.ps1',
    'tools\New-IntergradeR3DSSGIStrengthReview.ps1',
    'tools\New-IntergradeRebirthFallbackAOConsumer.ps1',
    'tools\New-IntergradeRebirthFallbackAOF2OwnerIntegrationPack.ps1',
    'tools\New-IntergradeRebirthFallbackAOF2TestPack.ps1',
    'tools\Stage-IntergradeRebirthFallbackAOF2OwnerIntegration.ps1',
    'tools\Stage-IntergradeRebirthFallbackAOF2Standalone.ps1',
    'tools\Stage-IntergradeR3DSSGIF2OwnerIntegration.ps1',
    'tools\Stage-IntergradeR3DSSGIF2Standalone.ps1',
    'tools\Test-IntergradeAOControlOwnership.ps1',
    'tools\Test-IntergradeAOShaderTestMatrix.ps1',
    'tools\Test-IntergradeR3DSSGIF2OwnerIntegrationPack.ps1',
    'tools\Test-IntergradeR3DSSGIF2OwnerStage.ps1',
    'tools\Test-IntergradeR3DSSGIF2StandalonePack.ps1',
    'tools\Test-IntergradeR3DSSGIF2StandaloneReloadStatus.ps1',
    'tools\Test-IntergradeR3DSSGIF2StandaloneStage.ps1',
    'tools\Test-IntergradeR3DSSGIF2EvidenceLedger.ps1',
    'tools\Test-IntergradeR3DSSGI3DmigotoSemantics.ps1',
    'tools\Test-IntergradeR3DSSGIPrototype.ps1',
    'tools\Test-IntergradeR3DSSGISamplingSemantics.ps1',
    'tools\Test-IntergradeR3DSSGIStrengthReview.ps1',
    'tools\Test-IntergradeR3DSSGIUnitScale.ps1',
    'tools\Test-IntergradeRebirthFallbackAOConsumer.ps1',
    'tools\Test-IntergradeRebirthFallbackAOF2OwnerIntegrationPack.ps1',
    'tools\Test-IntergradeRebirthFallbackAOF2OwnerStage.ps1',
    'tools\Test-IntergradeRebirthFallbackAOF2TestPack.ps1',
    'artifacts\analysis\agent2-r3d-ssgi-injection.json',
    'artifacts\analysis\agent2-r3d-ssgi-live-topology.json',
    'artifacts\analysis\agent2-r3d-ssgi-live-evidence-ledger.json',
    'artifacts\analysis\agent2-r3d-ssgi-live-reload-checker-test.json',
    'artifacts\analysis\agent2-r3d-ssgi-3dmigoto-semantics.json',
    'artifacts\analysis\agent2-r3d-ssgi-standalone-3dmigoto-semantics.json',
    'artifacts\analysis\agent2-r3d-ssgi-sampling-semantics.json',
    'artifacts\analysis\agent2-r3d-ssgi-stage-rollback.json',
    'artifacts\analysis\agent2-r3d-ssgi-standalone-stage-rollback.json',
    'artifacts\analysis\agent2-r3d-ssgi-unit-scale.json'
)) {
    Add-BackupFile $relative
}

foreach ($relative in @(
    'artifacts\ao-rebirth-fallback-consumer-candidate',
    'artifacts\ao-rebirth-fallback-consumer-f2-owner-integration-pack',
    'artifacts\ao-rebirth-fallback-consumer-f2-test-pack',
    'artifacts\agent2-r3d-ssgi-f2-owner-integration-pack',
    'artifacts\agent2-r3d-ssgi-f2-standalone-pack',
    'artifacts\agent2-r3d-ssgi-strength-review',
    'artifacts\r3d-ssgi-sm5-prototype'
)) {
    Add-BackupTree $relative
}

Assert-NoReparse $backupFull
[IO.Directory]::CreateDirectory($backupFull) | Out-Null
$snapshot = Join-Path $backupFull (Get-Date -Format 'yyyyMMdd-HHmmss')
if (Test-Path -LiteralPath $snapshot) { throw "Snapshot already exists: $snapshot" }
[IO.Directory]::CreateDirectory($snapshot) | Out-Null
Assert-NoReparse $snapshot

$snapshotPrefix = [IO.Path]::GetFullPath($snapshot).TrimEnd('\') + '\'
$records = [Collections.Generic.List[object]]::new()
foreach ($entry in $entries) {
    $destination = [IO.Path]::GetFullPath((Join-Path $snapshot $entry.relativePath))
    if (-not $destination.StartsWith($snapshotPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Backup destination escaped snapshot: $($entry.relativePath)"
    }
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    $before = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.source).Hash
    [IO.File]::Copy($entry.source, $destination, $false)
    $after = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash
    if ($before -ne $after) { throw "Backup hash mismatch: $($entry.relativePath)" }
    $records.Add([ordered]@{
        relativePath = $entry.relativePath
        bytes = $entry.bytes
        sha256 = $after
    })
}

$manifest = [ordered]@{
    schemaVersion = 1
    status = 'verified'
    createdUtc = [DateTime]::UtcNow.ToString('o')
    projectRoot = $projectRoot
    snapshot = $snapshot
    fileCount = $records.Count
    algorithm = 'SHA256'
    gameFilesTouched = $false
    files = @($records)
}
$manifestPath = Join-Path $snapshot 'backup-manifest.json'
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine, $utf8)

[pscustomobject]@{
    status = 'verified'
    snapshot = $snapshot
    files = $records.Count
    manifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash
    gameFilesTouched = $false
}
