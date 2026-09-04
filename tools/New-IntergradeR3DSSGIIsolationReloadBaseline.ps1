[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('00-true-noop','01-references-only','02-scene-copy-only','03-trace-only','04-trace-denoise','05-zero-composite','06-zero-composite-no-depth','07-zero-composite-no-draw')]
    [string]$Variant,
    [string]$TargetModsDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\Mods',
    [string]$MatrixRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-isolation-matrix'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\agent2-r3d-ssgi-isolation-reload-baseline.json'),
    [switch]$AllowExternalTarget
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$target = [IO.Path]::GetFullPath($TargetModsDirectory).TrimEnd('\')
$matrix = [IO.Path]::GetFullPath($MatrixRoot).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $matrix.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase) -or
    -not $output.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Matrix and baseline output must remain inside the workspace.'
}
if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw "Target Mods directory is missing: $target" }
if (-not $target.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    if (-not $AllowExternalTarget) { throw "External target requires -AllowExternalTarget: $target" }
    if (-not $target.EndsWith('\End\Binaries\Win64\Mods', [StringComparison]::OrdinalIgnoreCase)) {
        throw "External target must be the exact FF7 Remake Win64 Mods directory: $target"
    }
}

$manifestPath = Join-Path $matrix 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Isolation manifest is missing: $manifestPath" }
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.SchemaVersion -ne 1 -or $manifest.Result -ne 'pass' -or
    $manifest.Hook -ne 'e2aa1c8cb39e0a55-ps' -or $manifest.Controls.F10 -ne 'unchanged 3DMigoto reload key') {
    throw 'Isolation matrix contract is invalid.'
}
$entry = @($manifest.Variants | Where-Object Name -eq $Variant)
if ($entry.Count -ne 1) { throw "Isolation variant is not unique: $Variant" }
$entry = $entry[0]

$liveFiles = [Collections.Generic.List[object]]::new()
foreach ($file in @($entry.Files)) {
    $path = Join-Path $target ([string]$file.Name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Live isolation payload is missing: $($file.Name)" }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    if ($hash -ne [string]$file.Sha256 -or (Get-Item -LiteralPath $path).Length -ne [long]$file.Bytes) {
        throw "Live isolation payload does not match variant $Variant`: $($file.Name)"
    }
    $liveFiles.Add([ordered]@{name=[string]$file.Name;sha256=$hash;bytes=[long]$file.Bytes})
}
$iniPath = Join-Path $target 'Agent2R3DSSGITest.ini'
$iniText = Get-Content -Raw -LiteralPath $iniPath
if ([regex]::Matches($iniText,'(?im)^\s*key\s*=.*(?<![A-Z0-9_])F2(?![A-Z0-9_]).*$').Count -ne 1 -or
    $iniText -match '(?im)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F10(?![A-Z0-9_]).*$') {
    throw 'Isolation key contract is invalid.'
}

$win64 = Split-Path -Parent $target
$logPath = Join-Path $win64 'd3d11_log.txt'
if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) { throw "3DMigoto log is missing: $logPath" }
$stream = [IO.File]::Open($logPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
try { $logOffset = [long]$stream.Length } finally { $stream.Dispose() }

$processes = @(Get-Process -Name 'ff7remake_' -ErrorAction Stop)
if ($processes.Count -ne 1) { throw "Expected one FF7 Remake process, found $($processes.Count)." }
$process = $processes[0]
$expectedExe = Join-Path $win64 'ff7remake_.exe'
if (-not $target.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase) -and
    -not [string]::Equals([string]$process.Path,$expectedExe,[StringComparison]::OrdinalIgnoreCase)) {
    throw "Running process is not the target FF7 executable: $($process.Path)"
}

$protected = [ordered]@{
    'Mods\ContactShadows.ini'='850925405F890D68E03F5E66073FA8529F1FD3618193A2E0C4CAFAC9A91333E2'
    'ShaderFixes\08bb8764f1840179-cs.txt'='3584A654C1E231ACB5C3E01CA50C8BC89F440B85320A97098B380706F76D1A83'
    'ShaderFixes\0e97888f9a8767da-cs.txt'='FB8C0FA229688D79497D726832ACB00F3763324AB09389BAD1A24352BAB1AA4A'
    'ShaderFixes\5a9fbefe0ab6f815-cs.txt'='421A8C026982B120AB9DDE629C529EA69C5E0B7E9A81FF30D1B4877B8DB773B0'
    'ShaderFixes\62b33a2d1e505241-cs.txt'='AB3FC967FA59ADE7E6B226B439E77DC81644ADFDA8404906C1F6EB8475A17876'
    'ShaderFixes\c30cdc8365df9840-cs.txt'='2B88112FF622CE972746334C19BED9F84A9C16CC17895992793FB4799A94F94E'
}
$protectedRecords = [Collections.Generic.List[object]]::new()
foreach ($pair in $protected.GetEnumerator()) {
    $path = Join-Path $win64 $pair.Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne $pair.Value) {
        throw "Protected accepted contact-shadow file drifted: $($pair.Key)"
    }
    $protectedRecords.Add([ordered]@{relativePath=$pair.Key;sha256=$pair.Value})
}

$baseline = [ordered]@{
    schemaVersion=1
    kind='agent2-r3d-ssgi-isolation-reload-baseline'
    classification='captured-before-F10'
    capturedUtc=[DateTime]::UtcNow.ToString('o')
    variant=$Variant
    variantDescription=[string]$entry.Description
    matrixManifest=$manifestPath
    matrixManifestSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash
    targetModsDirectory=$target
    process=[ordered]@{id=[int]$process.Id;path=[string]$process.Path;responding=[bool]$process.Responding}
    log=[ordered]@{path=$logPath;byteOffset=$logOffset;lastWriteUtc=(Get-Item -LiteralPath $logPath).LastWriteTimeUtc.ToString('o')}
    liveFiles=@($liveFiles)
    protectedFiles=@($protectedRecords)
    expected=[ordered]@{
        ini='Agent2R3DSSGITest.ini'
        keySection='Agent2R3DSSGITest'
        overrideSection='Agent2R3DSSGIF2Test'
        shaderHash='e2aa1c8cb39e0a55'
        customSections=@('Agent2R3DSSGITrace','Agent2R3DSSGIDenoise16','Agent2R3DSSGIDenoise8','Agent2R3DSSGIDenoise4','Agent2R3DSSGIDenoise2','Agent2R3DSSGIComposite')
        shaderFiles=@('Agent2R3DSSGITraceE2AA_ps.hlsl','Agent2R3DSSGIDenoise16_ps.hlsl','Agent2R3DSSGIDenoise8_ps.hlsl','Agent2R3DSSGIDenoise4_ps.hlsl','Agent2R3DSSGIDenoise2_ps.hlsl','Agent2R3DSSGICompositeE2AA_ps.hlsl')
    }
    visualResult='pending user F2 comparison'
    runtimeEligible=$false
}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,(($baseline | ConvertTo-Json -Depth 10) + "`r`n"),[Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Status='captured-before-F10'
    Variant=$Variant
    ProcessId=[int]$process.Id
    LogOffset=$logOffset
    LiveFiles=$liveFiles.Count
    ProtectedFiles=$protectedRecords.Count
    Output=$output
}
