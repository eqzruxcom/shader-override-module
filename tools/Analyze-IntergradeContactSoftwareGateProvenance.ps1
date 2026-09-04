[CmdletBinding()]
param(
    [string]$ReplayManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\contact-capture-replay-20260831-v4\manifest.json'),
    [string]$PlaneAuditManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\contact-plane-audit-20260831-v13\manifest.json'),
    [string]$PinnedContactSourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'backups\ContactMotion\20260831-before-surface-crossing\ContactShadows.hlsl'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-contact-software-gate-provenance-20260904.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "OutputPath must remain under artifacts: $output" }

$replayPath = [IO.Path]::GetFullPath($ReplayManifestPath)
$auditPath = [IO.Path]::GetFullPath($PlaneAuditManifestPath)
$pinnedPath = [IO.Path]::GetFullPath($PinnedContactSourcePath)
foreach ($path in @($replayPath,$auditPath,$pinnedPath)) {
    if (-not $path.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required workspace input is missing: $path" }
}

$replay = Get-Content -Raw -LiteralPath $replayPath | ConvertFrom-Json
$audit = Get-Content -Raw -LiteralPath $auditPath | ConvertFrom-Json
$manifestRecords = @(
    [pscustomobject][ordered]@{ name='captureReplay'; path=$replayPath; document=$replay }
    [pscustomobject][ordered]@{ name='planeAudit'; path=$auditPath; document=$audit }
)

$checks = foreach ($manifest in $manifestRecords) {
    foreach ($source in $manifest.document.sources) {
        $currentPath = [IO.Path]::GetFullPath((Join-Path $root $source.path))
        $exists = $currentPath.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $currentPath -PathType Leaf)
        $currentSha = if ($exists) { (Get-FileHash -Algorithm SHA256 -LiteralPath $currentPath).Hash } else { $null }
        [pscustomobject][ordered]@{
            manifest = $manifest.name
            path = [string]$source.path
            expectedSha256 = [string]$source.sha256
            currentSha256 = $currentSha
            currentExists = $exists
            currentMatchesEvidence = ($exists -and $currentSha -eq [string]$source.sha256)
        }
    }
}

$expectedContactHashes = @($checks | Where-Object path -eq 'src/Effects/Lighting/ContactShadows.hlsl' | Select-Object -ExpandProperty expectedSha256 -Unique)
if ($expectedContactHashes.Count -ne 1) { throw 'Historical manifests do not agree on the pinned contact source hash' }
$pinnedSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $pinnedPath).Hash
if ($pinnedSha -ne $expectedContactHashes[0]) { throw 'Pinned historical contact source no longer matches the saved evidence' }

$mismatches = @($checks | Where-Object { -not $_.currentMatchesEvidence })
$report = [ordered]@{
    schemaVersion = 1
    detector = 'ff7-remake-contact-software-gate-provenance-v1'
    scope = 'Provenance status of the historical analytic/contact-capture software gate after later source development.'
    manifests = foreach ($manifest in $manifestRecords) {
        [ordered]@{
            name = $manifest.name
            path = [IO.Path]::GetRelativePath($root,$manifest.path).Replace('\','/')
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifest.path).Hash
        }
    }
    sourceChecks = @($checks)
    checkedReferences = $checks.Count
    currentMismatchCount = $mismatches.Count
    currentGateStatus = 'correctly-rejected-stale-source-provenance'
    firstObservedFailure = 'Software gate: tested source changed: src/Effects/Lighting/ContactShadows.hlsl'
    pinnedHistoricalContactSource = [ordered]@{
        path = [IO.Path]::GetRelativePath($root,$pinnedPath).Replace('\','/')
        sha256 = $pinnedSha
        matchesBothHistoricalManifests = $true
    }
    interpretation = @(
        'The saved WARP replay and analytic plane results remain evidence for their pinned 2026-08-31 source revision.',
        'They do not certify the current geometric-tracer source or its later adapter/test harness revisions.',
        'This provenance failure is independent of the accepted ShaderRegex family, which is regenerated from hash-pinned first-working native assembly checkpoints and validated separately.'
    )
    policy = 'Do not refresh historical hashes. Re-run a new software evidence set if the current geometric source is ever promoted; keep the accepted assembly-family proof separate.'
    liveFilesModified = $false
}

[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,(($report | ConvertTo-Json -Depth 10)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Result=$report.currentGateStatus; CheckedReferences=$checks.Count; CurrentMismatches=$mismatches.Count; HistoricalSourcePinned=$true; Output=$output; LiveFilesModified=$false }

