[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('00-descriptor-only','01-custom-bind-only','02-setup-no-draw','03-zero-output-draw','04-real-trace-draw')]
    [string]$Variant,
    [Parameter(Mandatory)]
    [string]$TargetModsDirectory,
    [string]$MatrixRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-trace-refinement-matrix'),
    [string]$ParentMatrixRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-isolation-matrix'),
    [string]$BackupRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-trace-refinement-runtime-backups'),
    [switch]$ParentTraceFailureConfirmed,
    [switch]$AllowExternalTarget
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $ParentTraceFailureConfirmed) {
    throw 'Refinement deployment is forbidden until 03-trace-only is visually confirmed as the first failing parent variant.'
}

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$matrix = [IO.Path]::GetFullPath($MatrixRoot).TrimEnd('\')
$parentMatrix = [IO.Path]::GetFullPath($ParentMatrixRoot).TrimEnd('\')
$target = [IO.Path]::GetFullPath($TargetModsDirectory).TrimEnd('\')
$backup = [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')
foreach ($path in @($matrix,$parentMatrix,$backup)) {
    if (-not $path.StartsWith($workspace + '\',[StringComparison]::OrdinalIgnoreCase)) {
        throw "Matrix/backup path escaped the workspace: $path"
    }
}
if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw "Target Mods directory is missing: $target" }
$externalTarget = -not $target.StartsWith($workspace + '\',[StringComparison]::OrdinalIgnoreCase)
if ($externalTarget) {
    if (-not $AllowExternalTarget) { throw "External target requires -AllowExternalTarget: $target" }
    if (-not $target.EndsWith('\End\Binaries\Win64\Mods',[StringComparison]::OrdinalIgnoreCase)) {
        throw "External target must be an exact FF7 Remake Win64 Mods directory: $target"
    }
}

$manifestPath = Join-Path $matrix 'manifest.json'
$parentManifestPath = Join-Path $parentMatrix 'manifest.json'
foreach ($path in @($manifestPath,$parentManifestPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required manifest is missing: $path" }
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$parentManifest = Get-Content -Raw -LiteralPath $parentManifestPath | ConvertFrom-Json
if ($manifest.SchemaVersion -ne 1 -or $manifest.Result -ne 'pass' -or
    $manifest.Hook -ne 'e2aa1c8cb39e0a55-ps' -or
    $manifest.ParentMatrix -ne 'agent2-r3d-ssgi-f2-isolation-matrix/03-trace-only' -or
    $manifest.Controls.F2 -ne 'off/on' -or
    $manifest.Controls.F10 -ne 'unchanged 3DMigoto reload key') {
    throw 'Trace-refinement manifest contract is invalid.'
}
if ($parentManifest.SchemaVersion -ne 1 -or $parentManifest.Result -ne 'pass' -or
    $parentManifest.Hook -ne 'e2aa1c8cb39e0a55-ps') {
    throw 'Parent isolation manifest contract is invalid.'
}
$entry = @($manifest.Variants | Where-Object Name -eq $Variant)
$parentEntry = @($parentManifest.Variants | Where-Object Name -eq '03-trace-only')
if ($entry.Count -ne 1 -or $parentEntry.Count -ne 1) { throw 'Requested or parent variant is missing/ambiguous.' }
$entry = $entry[0]
$parentEntry = $parentEntry[0]
$sourceMods = Join-Path (Join-Path $matrix $Variant) 'Mods'

foreach ($file in @($entry.Files)) {
    $path = Join-Path $sourceMods ([string]$file.Name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$file.Sha256 -or
        (Get-Item -LiteralPath $path).Length -ne [long]$file.Bytes) {
        throw "Refinement source payload failed manifest verification: $($file.Name)"
    }
}

$sourceIni = Join-Path $sourceMods 'Agent2R3DSSGITest.ini'
$sourceText = Get-Content -Raw -LiteralPath $sourceIni
if ([regex]::Matches($sourceText,'(?im)^\s*key\s*=.*(?<![A-Z0-9_])F2(?![A-Z0-9_]).*$').Count -ne 1 -or
    $sourceText -match '(?im)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F10(?![A-Z0-9_]).*$' -or
    $sourceText -match '(?im)^\s*key\s*=.*(?:PAGE_UP|PAGE_DOWN|VK_PRIOR|VK_NEXT).*$' -or
    [regex]::Matches($sourceText,'(?im)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$').Count -ne 1) {
    throw 'Refinement key/owner contract is invalid.'
}

$knownIniHashes = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($variantEntry in @($manifest.Variants)) {
    foreach ($file in @($variantEntry.Files | Where-Object Name -eq 'Agent2R3DSSGITest.ini')) {
        [void]$knownIniHashes.Add([string]$file.Sha256)
    }
}
foreach ($file in @($parentEntry.Files | Where-Object Name -eq 'Agent2R3DSSGITest.ini')) {
    [void]$knownIniHashes.Add([string]$file.Sha256)
}
$liveIni = Join-Path $target 'Agent2R3DSSGITest.ini'
if (-not (Test-Path -LiteralPath $liveIni -PathType Leaf)) { throw "Live Agent 2 INI is missing: $liveIni" }
$liveIniHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $liveIni).Hash
if (-not $knownIniHashes.Contains($liveIniHash)) { throw "Live Agent 2 INI drifted or is unknown: $liveIniHash" }

# Every existing shader payload must already equal the refinement payload. The
# one new diagnostic zero shader may be absent, but an unexpected existing copy
# is treated as drift rather than overwritten.
$zeroName = 'Agent2R3DSSGITraceZero_ps.hlsl'
foreach ($file in @($entry.Files | Where-Object Name -notin @('Agent2R3DSSGITest.ini',$zeroName))) {
    $path = Join-Path $target ([string]$file.Name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$file.Sha256) {
        throw "Live shader payload drifted; refusing refinement switch: $($file.Name)"
    }
}
$sourceZeroRecord = @($entry.Files | Where-Object Name -eq $zeroName)
if ($sourceZeroRecord.Count -ne 1) { throw 'Refinement manifest lacks the zero shader.' }
$liveZero = Join-Path $target $zeroName
if (Test-Path -LiteralPath $liveZero -PathType Leaf) {
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $liveZero).Hash -ne [string]$sourceZeroRecord[0].Sha256) {
        throw "Existing live zero shader is unknown or drifted: $liveZero"
    }
}

$protected = [ordered]@{
    'Mods\ContactShadows.ini'='850925405F890D68E03F5E66073FA8529F1FD3618193A2E0C4CAFAC9A91333E2'
    'ShaderFixes\08bb8764f1840179-cs.txt'='3584A654C1E231ACB5C3E01CA50C8BC89F440B85320A97098B380706F76D1A83'
    'ShaderFixes\0e97888f9a8767da-cs.txt'='FB8C0FA229688D79497D726832ACB00F3763324AB09389BAD1A24352BAB1AA4A'
    'ShaderFixes\5a9fbefe0ab6f815-cs.txt'='421A8C026982B120AB9DDE629C529EA69C5E0B7E9A81FF30D1B4877B8DB773B0'
    'ShaderFixes\62b33a2d1e505241-cs.txt'='AB3FC967FA59ADE7E6B226B439E77DC81644ADFDA8404906C1F6EB8475A17876'
    'ShaderFixes\c30cdc8365df9840-cs.txt'='2B88112FF622CE972746334C19BED9F84A9C16CC17895992793FB4799A94F94E'
}
if ($externalTarget) {
    $win64 = Split-Path -Parent $target
    foreach ($pair in $protected.GetEnumerator()) {
        $path = Join-Path $win64 $pair.Key
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne $pair.Value) {
            throw "Protected accepted contact-shadow file drifted: $($pair.Key)"
        }
    }
}

$targetIniHash = [string](@($entry.Files | Where-Object Name -eq 'Agent2R3DSSGITest.ini')[0].Sha256)
$zeroAlreadyPresent = Test-Path -LiteralPath $liveZero -PathType Leaf
if ($liveIniHash -eq $targetIniHash -and $zeroAlreadyPresent) {
    [pscustomobject]@{Status='already-staged';Variant=$Variant;Hash=$liveIniHash;ReloadRequired=$false;LiveFilesChanged=0}
    return
}
if (-not $PSCmdlet.ShouldProcess($target,"Stage guarded SSGI trace-refinement variant $Variant")) { return }

[IO.Directory]::CreateDirectory($backup) | Out-Null
$snapshot = Join-Path $backup (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
[IO.Directory]::CreateDirectory($snapshot) | Out-Null
$backupIni = Join-Path $snapshot 'Agent2R3DSSGITest.before.ini'
[IO.File]::Copy($liveIni,$backupIni,$false)
$backupZero = Join-Path $snapshot 'Agent2R3DSSGITraceZero.before.hlsl'
if ($zeroAlreadyPresent) { [IO.File]::Copy($liveZero,$backupZero,$false) }

$changed = [Collections.Generic.List[string]]::new()
try {
    if ($liveIniHash -ne $targetIniHash) {
        [IO.File]::Copy($sourceIni,$liveIni,$true)
        $changed.Add('Agent2R3DSSGITest.ini')
    }
    if (-not $zeroAlreadyPresent) {
        [IO.File]::Copy((Join-Path $sourceMods $zeroName),$liveZero,$false)
        $changed.Add($zeroName)
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $liveIni).Hash -ne $targetIniHash -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $liveZero).Hash -ne [string]$sourceZeroRecord[0].Sha256) {
        throw 'Post-stage refinement verification failed.'
    }
} catch {
    [IO.File]::Copy($backupIni,$liveIni,$true)
    if ($zeroAlreadyPresent) { [IO.File]::Copy($backupZero,$liveZero,$true) }
    elseif (Test-Path -LiteralPath $liveZero -PathType Leaf) { [IO.File]::Delete($liveZero) }
    throw
}

$receipt = [ordered]@{
    SchemaVersion=1
    Variant=$Variant
    StagedAtUtc=[DateTime]::UtcNow.ToString('o')
    Target=$target
    ParentTraceFailureConfirmed=$true
    BeforeIniSha256=$liveIniHash
    AfterIniSha256=$targetIniHash
    ZeroShaderExistedBefore=$zeroAlreadyPresent
    ChangedFiles=@($changed)
    BackupIni=$backupIni
    BackupZero=if($zeroAlreadyPresent){$backupZero}else{$null}
    F10='unchanged; reload required'
    ContactShadowHashesVerified=$externalTarget
}
[IO.File]::WriteAllText((Join-Path $snapshot 'receipt.json'),(($receipt | ConvertTo-Json -Depth 6) + "`r`n"),[Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Status='staged'
    Variant=$Variant
    Hash=$targetIniHash
    Backup=$snapshot
    ReloadRequired=$true
    LiveFilesChanged=$changed.Count
}
