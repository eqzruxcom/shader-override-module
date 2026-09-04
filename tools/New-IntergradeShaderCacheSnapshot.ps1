[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ShaderCacheDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')][string]$SnapshotId,
    [Parameter(Mandatory)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cache = (Resolve-Path -LiteralPath $ShaderCacheDirectory).Path
if (-not (Test-Path -LiteralPath $cache -PathType Container)) {
    throw "ShaderCache directory is missing: $ShaderCacheDirectory"
}

$shaderFiles = @(Get-ChildItem -LiteralPath $cache -File -Filter '*.bin' |
    Where-Object Name -match '^(?<hash>[0-9A-Fa-f]{16})-(?<stage>ps|vs|cs|gs|hs|ds)\.bin$' |
    Sort-Object Name)
if (-not $shaderFiles.Count) {
    throw 'No original 3Dmigoto shader binaries were found.'
}

$records = foreach ($file in $shaderFiles) {
    if ($file.Name -notmatch '^(?<hash>[0-9A-Fa-f]{16})-(?<stage>ps|vs|cs|gs|hs|ds)\.bin$') {
        throw "Unexpected shader filename after filtering: $($file.Name)"
    }
    [pscustomobject][ordered]@{
        identity = "$($Matches.hash.ToLowerInvariant())-$($Matches.stage.ToLowerInvariant())"
        stage = $Matches.stage.ToLowerInvariant()
        bytes = [long]$file.Length
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
}

$identities = @($records | ForEach-Object identity)
if (@($identities | Sort-Object -Unique).Count -ne $identities.Count) {
    throw 'ShaderCache snapshot contains duplicate identities.'
}

$stageCounts = [ordered]@{}
foreach ($stage in @('vs','ps','cs','gs','hs','ds')) {
    $count = @($records | Where-Object stage -eq $stage).Count
    if ($count) { $stageCounts[$stage] = $count }
}

$manifest = [ordered]@{
    schemaVersion = 1
    snapshotId = $SnapshotId
    sourceKind = '3dmigoto-shader-cache'
    shaderCount = $records.Count
    stageCounts = $stageCounts
    shaders = @($records)
}

$outputFull = [IO.Path]::GetFullPath($OutputPath)
$parent = Split-Path -Parent $outputFull
if ([string]::IsNullOrWhiteSpace($parent)) { throw 'Snapshot output needs a parent directory.' }
[IO.Directory]::CreateDirectory($parent) | Out-Null
[IO.File]::WriteAllText(
    $outputFull,
    (($manifest | ConvertTo-Json -Depth 6) + [Environment]::NewLine),
    [Text.UTF8Encoding]::new($false)
)

[pscustomobject]@{
    SnapshotId = $SnapshotId
    Shaders = $records.Count
    Stages = (($stageCounts.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')
    Output = $outputFull
    Sha256 = (Get-FileHash -LiteralPath $outputFull -Algorithm SHA256).Hash
}
