[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BeforePath,
    [Parameter(Mandatory)][string]$AfterPath,
    [Parameter(Mandatory)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-Snapshot([string]$Path, [string]$Label) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $snapshot = Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json
    if ($snapshot.schemaVersion -ne 1 -or $snapshot.sourceKind -ne '3dmigoto-shader-cache') {
        throw "$Label is not a supported ShaderCache snapshot."
    }
    $records = @($snapshot.shaders)
    if ([int]$snapshot.shaderCount -ne $records.Count -or -not $records.Count) {
        throw "$Label shader count is invalid."
    }
    $ids = @($records | ForEach-Object { [string]$_.identity })
    if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) {
        throw "$Label contains duplicate shader identities."
    }
    [pscustomobject]@{
        Path = $resolved
        Sha256 = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
        Data = $snapshot
        Records = $records
    }
}

$before = Read-Snapshot $BeforePath 'Before snapshot'
$after = Read-Snapshot $AfterPath 'After snapshot'
$beforeMap = @{}
$afterMap = @{}
foreach ($record in $before.Records) { $beforeMap[[string]$record.identity] = $record }
foreach ($record in $after.Records) { $afterMap[[string]$record.identity] = $record }

$added = @($afterMap.Keys | Where-Object { -not $beforeMap.ContainsKey($_) } | Sort-Object)
$removed = @($beforeMap.Keys | Where-Object { -not $afterMap.ContainsKey($_) } | Sort-Object)
$changed = @(
    $beforeMap.Keys |
        Where-Object { $afterMap.ContainsKey($_) -and [string]$beforeMap[$_].sha256 -ne [string]$afterMap[$_].sha256 } |
        Sort-Object |
        ForEach-Object {
            [pscustomobject][ordered]@{
                identity = $_
                beforeSha256 = [string]$beforeMap[$_].sha256
                afterSha256 = [string]$afterMap[$_].sha256
            }
        }
)

$addedByStage = [ordered]@{}
foreach ($stage in @('vs','ps','cs','gs','hs','ds')) {
    $count = @($added | Where-Object { $_ -match "-$stage$" }).Count
    if ($count) { $addedByStage[$stage] = $count }
}

$report = [ordered]@{
    schemaVersion = 1
    comparisonKind = '3dmigoto-shader-cache-regional-delta'
    before = [ordered]@{
        snapshotId = [string]$before.Data.snapshotId
        sha256 = $before.Sha256
        shaderCount = [int]$before.Data.shaderCount
    }
    after = [ordered]@{
        snapshotId = [string]$after.Data.snapshotId
        sha256 = $after.Sha256
        shaderCount = [int]$after.Data.shaderCount
    }
    counts = [ordered]@{
        added = $added.Count
        removed = $removed.Count
        changed = $changed.Count
    }
    addedByStage = $addedByStage
    added = $added
    removed = $removed
    changed = $changed
}

$outputFull = [IO.Path]::GetFullPath($OutputPath)
$parent = Split-Path -Parent $outputFull
if ([string]::IsNullOrWhiteSpace($parent)) { throw 'Comparison output needs a parent directory.' }
[IO.Directory]::CreateDirectory($parent) | Out-Null
[IO.File]::WriteAllText(
    $outputFull,
    (($report | ConvertTo-Json -Depth 7) + [Environment]::NewLine),
    [Text.UTF8Encoding]::new($false)
)

[pscustomobject]@{
    Added = $added.Count
    Removed = $removed.Count
    Changed = $changed.Count
    AddedByStage = (($addedByStage.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')
    Output = $outputFull
    Sha256 = (Get-FileHash -LiteralPath $outputFull -Algorithm SHA256).Hash
}
