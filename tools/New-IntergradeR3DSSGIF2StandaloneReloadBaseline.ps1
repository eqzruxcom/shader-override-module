[CmdletBinding()]
param(
    [string]$TargetModsDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\Mods',
    [string]$StageStatePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-standalone-stage-backups\active-state.json'),
    [string]$PackManifest = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-standalone-pack\manifest.json'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\agent2-r3d-ssgi-live-reload-baseline.json'),
    [switch]$AllowExternalStageState,
    [int]$ProcessId = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$target = [IO.Path]::GetFullPath($TargetModsDirectory).TrimEnd('\')
$statePath = [IO.Path]::GetFullPath($StageStatePath)
$manifestPath = [IO.Path]::GetFullPath($PackManifest)
$outputFull = [IO.Path]::GetFullPath($OutputPath)
foreach ($workspaceFile in @($manifestPath,$outputFull)) {
    if (-not $workspaceFile.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Baseline workspace path escaped the project: $workspaceFile"
    }
}
if (-not $statePath.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) -and -not $AllowExternalStageState) {
    throw "External stage receipt requires -AllowExternalStageState: $statePath"
}
foreach ($required in @($statePath,$manifestPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required reload-baseline input is missing: $required" }
}
if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw "Target Mods directory is missing: $target" }

function Get-Hash([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
if ($manifest.classification -ne 'offline-f2-standalone-live-topology-candidate' -or
    $manifest.policy.runtimeEligible -ne $false -or $manifest.policy.installed -ne $false -or
    $state.packageId -ne 'agent2-r3d-ssgi-f2-standalone' -or $state.status -ne 'staged' -or
    -not [string]::Equals([string]$state.targetRoot,$target,[StringComparison]::OrdinalIgnoreCase) -or
    (Get-Hash $manifestPath) -ne [string]$state.packManifestSha256) {
    throw 'Reload baseline requires the exact staged standalone package and source manifest.'
}

$changed = [Collections.Generic.List[string]]::new()
foreach ($file in @($state.files)) {
    if (-not (Test-Path -LiteralPath $file.destination -PathType Leaf) -or
        (Get-Hash $file.destination) -ne [string]$file.sha256) {
        $changed.Add([string]$file.relativePath)
    }
}
if ($changed.Count) { throw "Staged Agent 2 files drifted before baseline capture: $($changed -join ', ')" }
foreach ($item in @($manifest.baseline.disabledRebirthOwner,$manifest.baseline.generatedIni)) {
    $path = Join-Path $target ([string]$item.name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Hash $path) -ne [string]$item.sha256) {
        throw "Live topology fingerprint drifted before baseline capture: $($item.name)"
    }
}

$win64 = [IO.Path]::GetDirectoryName($target)
$logPath = Join-Path $win64 'd3d11_log.txt'
if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) { throw "Live 3Dmigoto log is missing: $logPath" }
$stream = [IO.File]::Open($logPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
try { $byteOffset = [long]$stream.Length } finally { $stream.Dispose() }

$process = if ($ProcessId -gt 0) {
    Get-Process -Id $ProcessId -ErrorAction Stop
} else {
    $matches = @(Get-Process -Name 'ff7remake_' -ErrorAction Stop)
    if ($matches.Count -ne 1) { throw "Expected exactly one FF7 Remake process, found $($matches.Count)." }
    $matches[0]
}
$expectedExe = Join-Path $win64 'ff7remake_.exe'
$targetInsideWorkspace = $target.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase)
if (-not $targetInsideWorkspace -and -not [string]::Equals($process.Path,$expectedExe,[StringComparison]::OrdinalIgnoreCase)) {
    throw "Reload baseline process is not the target FF7 executable. Expected $expectedExe, found $($process.Path)"
}

$expectedCustomSections = @(
    'Agent2R3DSSGITrace',
    'Agent2R3DSSGIDenoise16',
    'Agent2R3DSSGIDenoise8',
    'Agent2R3DSSGIDenoise4',
    'Agent2R3DSSGIDenoise2',
    'Agent2R3DSSGIComposite'
)
$expectedShaders = @(
    'Agent2R3DSSGITraceE2AA_ps.hlsl',
    'Agent2R3DSSGIDenoise16_ps.hlsl',
    'Agent2R3DSSGIDenoise8_ps.hlsl',
    'Agent2R3DSSGIDenoise4_ps.hlsl',
    'Agent2R3DSSGIDenoise2_ps.hlsl',
    'Agent2R3DSSGICompositeE2AA_ps.hlsl'
)
$baseline = [ordered]@{
    schemaVersion = 1
    packageId = 'agent2-r3d-ssgi-f2-standalone'
    classification = 'captured-before-F10-reload'
    capturedAtUtc = [DateTime]::UtcNow.ToString('o')
    targetModsDirectory = $target
    win64Directory = $win64
    processId = [int]$process.Id
    processPath = [string]$process.Path
    processResponding = [bool]$process.Responding
    logPath = $logPath
    byteOffset = $byteOffset
    stageStatePath = $statePath
    stageStateSha256 = Get-Hash $statePath
    packManifestPath = $manifestPath
    packManifestSha256 = Get-Hash $manifestPath
    installedFiles = @($state.files | ForEach-Object {[ordered]@{relativePath=[string]$_.relativePath; sha256=[string]$_.sha256}})
    protectedFingerprints = @(
        [ordered]@{relativePath=[string]$manifest.baseline.disabledRebirthOwner.name; sha256=[string]$manifest.baseline.disabledRebirthOwner.sha256},
        [ordered]@{relativePath=[string]$manifest.baseline.generatedIni.name; sha256=[string]$manifest.baseline.generatedIni.sha256}
    )
    expected = [ordered]@{
        ini = 'Agent2R3DSSGITest.ini'
        keySection = 'Agent2R3DSSGITest'
        overrideSection = 'Agent2R3DSSGIF2Test'
        shaderHash = 'e2aa1c8cb39e0a55'
        customSections = $expectedCustomSections
        shaderFiles = $expectedShaders
    }
    remainingGates = @('F10 reload','live parser and six custom-HLSL compile-clean result','F2 still A/B','F2 motion/disocclusion A/B','GPU timing')
    runtimeEligible = $false
}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull)) | Out-Null
[IO.File]::WriteAllText($outputFull,(($baseline|ConvertTo-Json -Depth 12)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Result = 'captured-before-F10-reload'
    ProcessId = $baseline.processId
    ProcessResponding = $baseline.processResponding
    ByteOffset = $baseline.byteOffset
    InstalledFiles = @($baseline.installedFiles).Count
    RuntimeEligible = $false
    Output = $outputFull
}
