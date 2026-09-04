[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [Parameter(Mandatory)]
    [string]$TargetModsDirectory,
    [string]$PackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-zero-pack'),
    [string]$MatrixRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-isolation-matrix'),
    [string]$BackupRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-runtime-backups'),
    [switch]$AllowExternalTarget,
    [switch]$AcknowledgeDiagnosticOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$pack = [IO.Path]::GetFullPath($PackRoot).TrimEnd('\')
$matrix = [IO.Path]::GetFullPath($MatrixRoot).TrimEnd('\')
$target = [IO.Path]::GetFullPath($TargetModsDirectory).TrimEnd('\')
$backup = [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')

if (-not $AcknowledgeDiagnosticOnly) {
    throw 'This zero-output pack is diagnostic only. Pass -AcknowledgeDiagnosticOnly to stage it deliberately.'
}
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

$manifestPath = Join-Path $pack 'manifest.json'
$matrixManifestPath = Join-Path $matrix 'manifest.json'
foreach ($path in @($manifestPath, $matrixManifestPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required manifest is missing: $path" }
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$matrixManifest = Get-Content -Raw -LiteralPath $matrixManifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.result -ne 'pass' -or $manifest.runtimeEligible -ne $false -or
    $manifest.hook -ne 'e2aa1c8cb39e0a55-ps' -or $manifest.controls.F2 -ne 'off/on' -or
    $manifest.controls.F10 -ne 'native reload, unchanged' -or $manifest.ownedPass.draw -ne '3, 0' -or
    [string]$manifest.variant -notin @('owned-fullscreen-zero-output','owned-fullscreen-private-target-zero-output')) {
    throw 'Owned fullscreen pack manifest contract is invalid.'
}
if ($matrixManifest.SchemaVersion -ne 1 -or $matrixManifest.Result -ne 'pass') {
    throw 'Isolation matrix manifest contract is invalid.'
}

$sourceMods = Join-Path $pack 'Mods'
$files = @($manifest.files)
if ($files.Count -ne 8) { throw "Owned fullscreen pack must contain exactly eight files; found $($files.Count)." }
$requiredNames = @(
    'Agent2R3DSSGITest.ini',
    'Agent2R3DSSGIFullscreen_vs.hlsl',
    'Agent2R3DSSGITraceE2AA_ps.hlsl',
    'Agent2R3DSSGIDenoise2_ps.hlsl',
    'Agent2R3DSSGIDenoise4_ps.hlsl',
    'Agent2R3DSSGIDenoise8_ps.hlsl',
    'Agent2R3DSSGIDenoise16_ps.hlsl',
    'Agent2R3DSSGICompositeE2AA_ps.hlsl'
)
$manifestFileSet = (@($files.name | Sort-Object) -join '|')
$requiredFileSet = (@($requiredNames | Sort-Object) -join '|')
if ($manifestFileSet -ne $requiredFileSet) {
    throw 'Owned fullscreen pack file set is not the expected closed set.'
}

$packHashes = [ordered]@{}
foreach ($file in $files) {
    $source = Join-Path $sourceMods ([string]$file.name)
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Pack file is missing: $source" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
    if ($actual -ne [string]$file.sha256) { throw "Pack file drifted: $($file.name)" }
    $packHashes[[string]$file.name] = $actual
}

$iniText = Get-Content -Raw -LiteralPath (Join-Path $sourceMods 'Agent2R3DSSGITest.ini')
foreach ($needle in @(
    'vs = Agent2R3DSSGIFullscreen_vs.hlsl', 'hs = null', 'ds = null', 'gs = null',
    'depth_enable = false', 'depth_write_mask = zero', 'stencil_enable = false',
    'cull = none', 'topology = triangle_list', 'draw = 3, 0'
)) {
    if ($iniText -notmatch ('(?im)^\s*' + [regex]::Escape($needle) + '\s*$')) { throw "Owned pass contract is missing: $needle" }
}
if ([regex]::Matches($iniText,'(?im)^\s*key\s*=.*(?<![A-Z0-9_])F2(?![A-Z0-9_]).*$').Count -ne 1 -or
    $iniText -match '(?im)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F10(?![A-Z0-9_]).*$') {
    throw 'Owned pack key contract is invalid or attempts to bind F10.'
}

$knownIniHashes = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($variant in @($matrixManifest.Variants)) {
    foreach ($file in @($variant.Files | Where-Object Name -eq 'Agent2R3DSSGITest.ini')) {
        [void]$knownIniHashes.Add([string]$file.Sha256)
    }
}
[void]$knownIniHashes.Add([string]$packHashes['Agent2R3DSSGITest.ini'])
foreach ($predecessorRoot in @(
    (Join-Path $workspace 'artifacts\agent2-r3d-ssgi-owned-fullscreen-zero-pack'),
    (Join-Path $workspace 'artifacts\agent2-r3d-ssgi-owned-fullscreen-private-target-zero-pack')
)) {
    $predecessorManifestPath = Join-Path $predecessorRoot 'manifest.json'
    if (-not (Test-Path -LiteralPath $predecessorManifestPath -PathType Leaf)) { continue }
    $predecessorManifest = Get-Content -Raw -LiteralPath $predecessorManifestPath | ConvertFrom-Json
    if ($predecessorManifest.schemaVersion -ne 1 -or $predecessorManifest.result -ne 'pass' -or
        $predecessorManifest.runtimeEligible -ne $false -or $predecessorManifest.hook -ne 'e2aa1c8cb39e0a55-ps' -or
        @($predecessorManifest.files).Count -ne 8) {
        throw "Invalid predecessor diagnostic manifest: $predecessorManifestPath"
    }
    $predecessorIni = @($predecessorManifest.files | Where-Object name -eq 'Agent2R3DSSGITest.ini')
    if ($predecessorIni.Count -ne 1) { throw "Predecessor diagnostic has no unique INI: $predecessorManifestPath" }
    [void]$knownIniHashes.Add([string]$predecessorIni[0].sha256)
}
$liveIni = Join-Path $target 'Agent2R3DSSGITest.ini'
if (-not (Test-Path -LiteralPath $liveIni -PathType Leaf)) { throw "Live Agent 2 INI is missing: $liveIni" }
$liveIniHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $liveIni).Hash
if (-not $knownIniHashes.Contains($liveIniHash)) { throw "Live Agent 2 INI drifted or is unknown: $liveIniHash" }

# Every pre-existing payload must already equal this closed diagnostic family.
foreach ($name in $requiredNames | Where-Object { $_ -notin @('Agent2R3DSSGITest.ini','Agent2R3DSSGIFullscreen_vs.hlsl') }) {
    $live = Join-Path $target $name
    if (-not (Test-Path -LiteralPath $live -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $live).Hash -ne [string]$packHashes[$name]) {
        throw "Live shader payload drifted: $name"
    }
}
$liveVs = Join-Path $target 'Agent2R3DSSGIFullscreen_vs.hlsl'
if ((Test-Path -LiteralPath $liveVs -PathType Leaf) -and
    (Get-FileHash -Algorithm SHA256 -LiteralPath $liveVs).Hash -ne [string]$packHashes['Agent2R3DSSGIFullscreen_vs.hlsl']) {
    throw 'Live fullscreen vertex shader exists with an unknown hash.'
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

$alreadyStaged = $true
foreach ($name in $requiredNames) {
    $live = Join-Path $target $name
    if (-not (Test-Path -LiteralPath $live -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $live).Hash -ne [string]$packHashes[$name]) {
        $alreadyStaged = $false
    }
}
if ($alreadyStaged) {
    [pscustomobject]@{Status='already-staged';Pack=[string]$manifest.variant;ReloadRequired=$false}
    return
}
if (-not $PSCmdlet.ShouldProcess($target, 'Stage diagnostic injector-owned fullscreen zero-output SSGI pack')) { return }

[IO.Directory]::CreateDirectory($backup) | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$snapshot = Join-Path $backup $stamp
$snapshotMods = Join-Path $snapshot 'Mods'
[IO.Directory]::CreateDirectory($snapshotMods) | Out-Null
$before = @()
foreach ($name in $requiredNames) {
    $live = Join-Path $target $name
    $existed = Test-Path -LiteralPath $live -PathType Leaf
    $hash = $null
    if ($existed) {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $live).Hash
        [IO.File]::Copy($live, (Join-Path $snapshotMods $name), $false)
    }
    $before += [ordered]@{name=$name;existed=$existed;sha256=$hash}
}

try {
    foreach ($name in $requiredNames) {
        [IO.File]::Copy((Join-Path $sourceMods $name), (Join-Path $target $name), $true)
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $target $name)).Hash
        if ($actual -ne [string]$packHashes[$name]) { throw "Post-stage hash mismatch: $name" }
    }
} catch {
    foreach ($entry in $before) {
        $live = Join-Path $target ([string]$entry.name)
        if ($entry.existed) { [IO.File]::Copy((Join-Path $snapshotMods ([string]$entry.name)), $live, $true) }
        elseif (Test-Path -LiteralPath $live -PathType Leaf) { Remove-Item -LiteralPath $live -Force }
    }
    throw
}

$receipt = [ordered]@{
    schemaVersion=1
    action='stage-owned-fullscreen-zero'
    stagedAtUtc=[DateTime]::UtcNow.ToString('o')
    targetModsDirectory=$target
    packManifest=$manifestPath
    backupDirectory=$snapshotMods
    before=$before
    after=@($requiredNames | ForEach-Object { [ordered]@{name=$_;sha256=[string]$packHashes[$_]} })
    controls=[ordered]@{F2='off/on';F10='unchanged; reload required';PageUp='unchanged';PageDown='unchanged'}
    diagnosticOnly=$true
    packVariant=[string]$manifest.variant
}
$receiptPath = Join-Path $snapshot 'receipt.json'
[IO.File]::WriteAllText($receiptPath, (($receipt | ConvertTo-Json -Depth 8) + "`r`n"), [Text.UTF8Encoding]::new($false))
[pscustomobject]@{Status='staged';Pack=[string]$manifest.variant;Receipt=$receiptPath;ReloadRequired=$true}
