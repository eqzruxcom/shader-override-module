[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('00-true-noop','01-references-only','02-scene-copy-only','03-trace-only','04-trace-denoise','05-zero-composite','06-zero-composite-no-depth','07-zero-composite-no-draw')]
    [string]$Variant,
    [Parameter(Mandatory)]
    [string]$TargetModsDirectory,
    [string]$MatrixRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-isolation-matrix'),
    [string]$BackupRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-isolation-runtime-backups'),
    [switch]$AllowExternalTarget
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$matrix = [IO.Path]::GetFullPath($MatrixRoot).TrimEnd('\')
$target = [IO.Path]::GetFullPath($TargetModsDirectory).TrimEnd('\')
$backup = [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')

if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw "Target Mods directory is missing: $target" }
if (-not $target.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    if (-not $AllowExternalTarget) { throw "External target requires -AllowExternalTarget: $target" }
    if (-not $target.EndsWith('\End\Binaries\Win64\Mods', [StringComparison]::OrdinalIgnoreCase)) {
        throw "External target must be an exact FF7 Remake Win64 Mods directory: $target"
    }
}
if (-not $backup.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Backups must remain inside the workspace: $backup"
}

$manifestPath = Join-Path $matrix 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Isolation manifest is missing: $manifestPath" }
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.SchemaVersion -ne 1 -or $manifest.Result -ne 'pass' -or $manifest.Hook -ne 'e2aa1c8cb39e0a55-ps' -or
    $manifest.Controls.F2 -ne 'off/on' -or $manifest.Controls.F10 -ne 'unchanged 3DMigoto reload key') {
    throw 'Isolation manifest contract is invalid.'
}
$entry = @($manifest.Variants | Where-Object Name -eq $Variant)
if ($entry.Count -ne 1) { throw "Isolation variant is not unique: $Variant" }
$entry = $entry[0]
$sourceMods = Join-Path $matrix $Variant | Join-Path -ChildPath 'Mods'
$sourceIni = Join-Path $sourceMods 'Agent2R3DSSGITest.ini'
$expectedIni = @($entry.Files | Where-Object Name -eq 'Agent2R3DSSGITest.ini')
if ($expectedIni.Count -ne 1 -or -not (Test-Path -LiteralPath $sourceIni -PathType Leaf) -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceIni).Hash -ne $expectedIni[0].Sha256) {
    throw "Variant INI failed manifest verification: $Variant"
}

$sourceText = Get-Content -Raw -LiteralPath $sourceIni
if ([regex]::Matches($sourceText,'(?im)^\s*key\s*=.*(?<![A-Z0-9_])F2(?![A-Z0-9_]).*$').Count -ne 1 -or
    [regex]::Matches($sourceText,'(?im)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$').Count -ne 1 -or
    $sourceText -match '(?im)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F10(?![A-Z0-9_]).*$') {
    throw 'Variant key/owner contract is invalid or attempts to bind F10.'
}

$liveIni = Join-Path $target 'Agent2R3DSSGITest.ini'
if (-not (Test-Path -LiteralPath $liveIni -PathType Leaf)) { throw "Live Agent 2 INI is missing: $liveIni" }
$currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $liveIni).Hash
$knownIniHashes = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($v in @($manifest.Variants)) {
    foreach ($f in @($v.Files | Where-Object Name -eq 'Agent2R3DSSGITest.ini')) { [void]$knownIniHashes.Add([string]$f.Sha256) }
}
# Exact hashes of the manually staged, visually tracked precursors to this matrix.
foreach ($hash in @(
    '3EA288924EF6C1EA91A974707CFF9C1DA5458D046380B0359F3AEFD5B35B845D',
    '46EB7EBB590E79FF719C6FA44CFB86DFCEFA62E4B3C2F25C6A66DBD5378C6AB0',
    'A1839B5FB96DE13F6F0044AB741D122050F2E38E8C601129BF38930EC9A2AEC9',
    # Known parser-invalid isolation variants generated before the scene-resource typo was corrected.
    'E3A3F8494A9B17FB92FBAE66CB63A8CFE668C97070D10372726AB36036D5F3E2',
    'A2263975A380619B7D810CA20C9E561B1E3C4255C32E599FBF99C46FB094F848'
)) { [void]$knownIniHashes.Add($hash) }
if (-not $knownIniHashes.Contains($currentHash)) { throw "Live Agent 2 INI drifted or is unknown: $currentHash" }

foreach ($file in @($entry.Files | Where-Object Name -ne 'Agent2R3DSSGITest.ini')) {
    $sourceFile = Join-Path $sourceMods ([string]$file.Name)
    $liveFile = Join-Path $target ([string]$file.Name)
    if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceFile).Hash -ne [string]$file.Sha256) {
        throw "Matrix payload drifted: $($file.Name)"
    }
    if (-not (Test-Path -LiteralPath $liveFile -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $liveFile).Hash -ne [string]$file.Sha256) {
        throw "Live shader payload drifted; refusing an INI-only switch: $($file.Name)"
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
if ($target.EndsWith('\End\Binaries\Win64\Mods', [StringComparison]::OrdinalIgnoreCase)) {
    $win64 = Split-Path -Parent $target
    foreach ($pair in $protected.GetEnumerator()) {
        $path = Join-Path $win64 $pair.Key
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne $pair.Value) {
            throw "Protected accepted contact-shadow file drifted: $($pair.Key)"
        }
    }
}

$targetHash = [string]$expectedIni[0].Sha256
if ($currentHash -eq $targetHash) {
    [pscustomobject]@{Status='already-staged';Variant=$Variant;Hash=$currentHash;ReloadRequired=$false}
    return
}
if (-not $PSCmdlet.ShouldProcess($liveIni, "Stage SSGI isolation variant $Variant")) { return }

[IO.Directory]::CreateDirectory($backup) | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$snapshot = Join-Path $backup $stamp
[IO.Directory]::CreateDirectory($snapshot) | Out-Null
$backupIni = Join-Path $snapshot 'Agent2R3DSSGITest.before.ini'
[IO.File]::Copy($liveIni, $backupIni, $false)
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $backupIni).Hash -ne $currentHash) { throw 'Pre-stage backup verification failed.' }

[IO.File]::Copy($sourceIni, $liveIni, $true)
$actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $liveIni).Hash
if ($actualHash -ne $targetHash) {
    [IO.File]::Copy($backupIni, $liveIni, $true)
    throw "Post-stage hash mismatch; prior INI restored. Found: $actualHash"
}

$receipt = [ordered]@{
    SchemaVersion=1
    Variant=$Variant
    StagedAtUtc=[DateTime]::UtcNow.ToString('o')
    Target=$liveIni
    BeforeSha256=$currentHash
    AfterSha256=$actualHash
    Backup=$backupIni
    F10='unchanged; reload required'
    ContactShadowHashesVerified=$target.EndsWith('\End\Binaries\Win64\Mods', [StringComparison]::OrdinalIgnoreCase)
}
[IO.File]::WriteAllText((Join-Path $snapshot 'receipt.json'), (($receipt | ConvertTo-Json -Depth 5) + "`r`n"), [Text.UTF8Encoding]::new($false))
[pscustomobject]@{Status='staged';Variant=$Variant;Hash=$actualHash;Backup=$backupIni;ReloadRequired=$true}
