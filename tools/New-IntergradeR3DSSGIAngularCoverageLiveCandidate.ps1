[CmdletBinding()]
param(
    [string]$PackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-angular-coverage-pack-v1'),
    [string]$WrapperPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Backends\3DmigotoFork\builds\x64\Release\d3d11.dll'),
    [string]$PredecessorCandidateRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-temporal-live-candidate-static-reprojection-v2'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-angular-coverage-live-candidate-v1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$pack = [IO.Path]::GetFullPath($PackRoot).TrimEnd('\')
$wrapper = [IO.Path]::GetFullPath($WrapperPath)
$predecessor = [IO.Path]::GetFullPath($PredecessorCandidateRoot).TrimEnd('\')
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

foreach ($item in @(@($pack,'PackRoot'),@($wrapper,'WrapperPath'),@($predecessor,'PredecessorCandidateRoot'),@($output,'OutputRoot'))) {
    Assert-InRoot $item[0] $item[1]
}
if (Test-Path -LiteralPath $output) { throw "OutputRoot already exists; preserve prior evidence: $output" }
if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf)) { throw "Rebuilt wrapper is missing: $wrapper" }

& (Join-Path $PSScriptRoot 'Test-IntergradeR3DSSGIAngularCoveragePack.ps1') -PackRoot $pack | Out-Null
$sourceManifestPath = Join-Path $pack 'manifest.json'
$sourceManifest = Get-Content -Raw -LiteralPath $sourceManifestPath | ConvertFrom-Json
$predecessorManifestPath = Join-Path $predecessor 'manifest.json'
$predecessorManifest = Get-Content -Raw -LiteralPath $predecessorManifestPath | ConvertFrom-Json
if ($predecessorManifest.schemaVersion -ne 1 -or $predecessorManifest.packageId -ne 'agent2-r3d-ssgi-private-temporal-live-v1' -or
    $predecessorManifest.result -ne 'pass' -or $predecessorManifest.kind -ne 'controlled-live-candidate' -or
    -not [bool]$predecessorManifest.runtimeEligible -or [bool]$predecessorManifest.installed -or
    [bool]$predecessorManifest.liveTestsPerformed -or $predecessorManifest.controls.F10 -ne 'native reload, unchanged') {
    throw 'Temporal predecessor candidate failed its closed contract.'
}

$expectedNames = @(
    'Agent2R3DSSGICompositeE2AA_ps.hlsl','Agent2R3DSSGIDenoise16_ps.hlsl','Agent2R3DSSGIDenoise2_ps.hlsl',
    'Agent2R3DSSGIDenoise4_ps.hlsl','Agent2R3DSSGIDenoise8_ps.hlsl','Agent2R3DSSGIFullscreen_vs.hlsl',
    'Agent2R3DSSGITest.ini','Agent2R3DSSGITemporalHistory_ps.hlsl','Agent2R3DSSGITrace16E2AA_ps.hlsl',
    'Agent2R3DSSGITrace8E2AA_ps.hlsl','Agent2R3DSSGITraceE2AA_ps.hlsl'
)
if ((@($sourceManifest.files.name | Sort-Object) -join '|') -cne (@($expectedNames | Sort-Object) -join '|')) {
    throw 'Angular source inventory changed.'
}
foreach ($entry in @($sourceManifest.files)) {
    $path = Join-Path (Join-Path $pack 'Mods') ([string]$entry.name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Hash $path) -ne [string]$entry.sha256) {
        throw "Angular source payload is missing or drifted: $($entry.name)"
    }
}

$predecessorFiles = @($predecessorManifest.files)
if ($predecessorFiles.Count -ne 10) { throw 'Temporal predecessor inventory changed.' }
foreach ($entry in $predecessorFiles) {
    $path = Join-Path $predecessor (([string]$entry.relativePath).Replace('/','\'))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Hash $path) -ne [string]$entry.sha256) {
        throw "Temporal predecessor payload is missing or drifted: $($entry.relativePath)"
    }
}

$bytes = [IO.File]::ReadAllBytes($wrapper)
if ($bytes.Length -lt 512 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) { throw 'Wrapper is not an MZ executable.' }
$pe = [BitConverter]::ToInt32($bytes,0x3c)
if ($pe -lt 0 -or $pe + 6 -gt $bytes.Length -or [BitConverter]::ToUInt32($bytes,$pe) -ne 0x00004550) { throw 'Wrapper PE header is invalid.' }
if ([BitConverter]::ToUInt16($bytes,$pe + 4) -ne 0x8664) { throw 'Wrapper is not x64.' }
$wrapperHash = Get-Hash $wrapper
if ($wrapperHash -ne [string]$predecessorManifest.wrapper.sha256) { throw 'Angular wrapper is not byte-identical to the temporal predecessor wrapper.' }

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
    packageId = 'agent2-r3d-ssgi-angular-coverage-live-v1'
    result = 'pass'
    kind = 'controlled-live-candidate'
    adapter = 'FF7RemakeIntergrade-D3D11'
    executable = $predecessorManifest.executable
    predecessor = [ordered]@{
        packageId = [string]$predecessorManifest.packageId
        manifestSha256 = Get-Hash $predecessorManifestPath
        wrapperSha256 = [string]$predecessorManifest.wrapper.sha256
        payloadFileCount = $predecessorFiles.Count
    }
    wrapper = [ordered]@{
        relativePath = 'Runtime/d3d11.dll'
        sha256 = $wrapperHash
        bytes = (Get-Item -LiteralPath $wrapper).Length
        peMachine = '0x8664'
        unchangedFromPredecessor = $true
    }
    controls = $sourceManifest.controls
    experiment = $sourceManifest.experiment
    validation = [ordered]@{
        angularPackGatePassed = $true
        compiledShaderCount = [int]$sourceManifest.validation.compiledShaderCount
        exactNativeOffPath = $true
        finishedSceneFeedbackAbsent = $true
        wrapperBuiltReleaseX64 = $true
        wrapperUnchangedFromPredecessor = $true
        predecessorPayloadPinned = $true
        F10Unchanged = $true
        F2MasterPreserved = $true
        PageUpDiagnosticOnly = $true
        PageDownUnchanged = $true
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
[pscustomobject]@{Result='pass';Package=$output;Files=@($manifest.files).Count;WrapperSha256=$wrapperHash;RuntimeEligible=$true;Installed=$false;GameFilesModified=$false}
