[CmdletBinding()]
param(
    [string]$PackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-temporal-history-pack'),
    [string]$WrapperPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Backends\3DmigotoFork\builds\x64\Release\d3d11.dll'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-temporal-live-candidate'),
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedPredecessorWrapperSha256 = 'D3F0FC5562AF68DA2E6C99F24D742A562B2FF9604398EE6B80188C7CF46B8FDB'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$pack = [IO.Path]::GetFullPath($PackRoot).TrimEnd('\')
$wrapper = [IO.Path]::GetFullPath($WrapperPath)
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$utf8 = [Text.UTF8Encoding]::new($false)

function Assert-InRoot([string]$Path,[string]$Label) {
    if (-not $Path.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "$Label escaped the workspace: $Path" }
}
function Get-Hash([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash }
function Get-FileRecord([string]$Base,[string]$Path) {
    [ordered]@{
        relativePath = [IO.Path]::GetRelativePath($Base,$Path).Replace('\','/')
        bytes = (Get-Item -LiteralPath $Path).Length
        sha256 = Get-Hash $Path
    }
}

Assert-InRoot $pack 'PackRoot'
Assert-InRoot $wrapper 'WrapperPath'
Assert-InRoot $output 'OutputRoot'
if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf)) { throw "Rebuilt wrapper is missing: $wrapper" }

& (Join-Path $PSScriptRoot 'Test-IntergradeR3DSSGITemporalHistoryPack.ps1') | Out-Null
$sourceManifestPath = Join-Path $pack 'manifest.json'
$sourceManifest = Get-Content -Raw -LiteralPath $sourceManifestPath | ConvertFrom-Json
if ($sourceManifest.schemaVersion -ne 1 -or $sourceManifest.result -ne 'pass' -or
    $sourceManifest.variant -ne 'private-temporal-indirect-history' -or
    [bool]$sourceManifest.runtimeEligible -or [bool]$sourceManifest.installed -or
    -not [bool]$sourceManifest.validation.deterministicInitialization -or
    -not [bool]$sourceManifest.validation.resolutionRecreationClear -or
    -not [bool]$sourceManifest.validation.finishedSceneFeedbackAbsent -or
    $sourceManifest.controls.F10 -ne 'native reload, unchanged') {
    throw 'Temporal source pack failed its closed offline contract.'
}

$expectedNames = @(
    'Agent2R3DSSGICompositeE2AA_ps.hlsl','Agent2R3DSSGIDenoise16_ps.hlsl','Agent2R3DSSGIDenoise2_ps.hlsl',
    'Agent2R3DSSGIDenoise4_ps.hlsl','Agent2R3DSSGIDenoise8_ps.hlsl','Agent2R3DSSGIFullscreen_vs.hlsl',
    'Agent2R3DSSGITest.ini','Agent2R3DSSGITemporalHistory_ps.hlsl','Agent2R3DSSGITraceE2AA_ps.hlsl'
)
$sourceEntries = @($sourceManifest.files)
if ((@($sourceEntries.name | Sort-Object) -join '|') -cne (@($expectedNames | Sort-Object) -join '|')) { throw 'Temporal source inventory changed.' }
foreach ($entry in $sourceEntries) {
    $path = Join-Path (Join-Path $pack 'Mods') ([string]$entry.name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Hash $path) -ne [string]$entry.sha256) {
        throw "Temporal source payload is missing or drifted: $($entry.name)"
    }
}

$bytes = [IO.File]::ReadAllBytes($wrapper)
if ($bytes.Length -lt 512 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) { throw 'Wrapper is not an MZ executable.' }
$pe = [BitConverter]::ToInt32($bytes,0x3c)
if ($pe -lt 0 -or $pe + 6 -gt $bytes.Length -or [BitConverter]::ToUInt32($bytes,$pe) -ne 0x00004550) { throw 'Wrapper PE header is invalid.' }
$machine = [BitConverter]::ToUInt16($bytes,$pe + 4)
if ($machine -ne 0x8664) { throw ('Wrapper is not x64; machine=0x{0:X4}' -f $machine) }

if (Test-Path -LiteralPath $output -PathType Container) { [IO.Directory]::Delete($output,$true) }
$mods = Join-Path $output 'Mods'
$runtime = Join-Path $output 'Runtime'
[void][IO.Directory]::CreateDirectory($mods)
[void][IO.Directory]::CreateDirectory($runtime)
foreach ($name in $expectedNames) { [IO.File]::Copy((Join-Path (Join-Path $pack 'Mods') $name),(Join-Path $mods $name),$false) }
[IO.File]::Copy($wrapper,(Join-Path $runtime 'd3d11.dll'),$false)

$payload = @(
    Get-ChildItem -LiteralPath $mods -File | Sort-Object Name
    Get-Item -LiteralPath (Join-Path $runtime 'd3d11.dll')
)
$manifest = [ordered]@{
    schemaVersion = 1
    packageId = 'agent2-r3d-ssgi-private-temporal-live-v1'
    result = 'pass'
    kind = 'controlled-live-candidate'
    adapter = 'FF7RemakeIntergrade-D3D11'
    executable = [ordered]@{ name='ff7remake_.exe'; sha256='25B54C345C94EE9F6C6876B9C7537A69E6B0EEF25F322207C32A8DDCEE816635' }
    predecessor = [ordered]@{
        shaderVariant = 'pre-temporal-native-c473-input'
        wrapperSha256 = $ExpectedPredecessorWrapperSha256.ToUpperInvariant()
    }
    wrapper = [ordered]@{
        relativePath = 'Runtime/d3d11.dll'
        sha256 = Get-Hash (Join-Path $runtime 'd3d11.dll')
        bytes = (Get-Item -LiteralPath (Join-Path $runtime 'd3d11.dll')).Length
        peMachine = '0x8664'
        sourceHeaderSha256 = [string]$sourceManifest.engine.clearOnCreateHeaderSha256
        sourceImplementationSha256 = [string]$sourceManifest.engine.clearOnCreateImplementationSha256
    }
    controls = $sourceManifest.controls
    architecture = $sourceManifest.architecture
    validation = [ordered]@{
        temporalPackGatePassed = $true
        compiledShaderCount = [int]$sourceManifest.validation.compiledShaderCount
        nativeShaderReplacementIncluded = $false
        exactNativeOffPath = $true
        deterministicInitialization = $true
        resolutionRecreationClear = $true
        finishedSceneFeedbackAbsent = $true
        wrapperBuiltReleaseX64 = $true
        motionSignLiveValidationPending = $true
    }
    files = @($payload | ForEach-Object { Get-FileRecord $output $_.FullName })
    rollback = [ordered]@{
        backupBeforeWrite = $true
        refuseWithoutExactPredecessor = $true
        refuseWhileGameRunning = $true
        verifyInstalledHashesBeforeRestore = $true
        restoreExactBackups = $true
        removeCandidateCreatedFiles = $true
    }
    runtimeEligible = $true
    installed = $false
    liveTestsPerformed = $false
    gameFilesModified = $false
    generatedUtc = [DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),($manifest | ConvertTo-Json -Depth 16) + [Environment]::NewLine,$utf8)
[pscustomobject]@{Result='pass';Package=$output;Files=@($manifest.files).Count;WrapperSha256=$manifest.wrapper.sha256;RuntimeEligible=$true;Installed=$false;GameFilesModified=$false}
