[CmdletBinding()]
param(
    [string]$PackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-angular-coverage-pack-v1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$pack = [IO.Path]::GetFullPath($PackRoot).TrimEnd('\')
if (-not $pack.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) {
    throw 'PackRoot must remain below workspace artifacts.'
}

$manifestPath = Join-Path $pack 'manifest.json'
$mods = Join-Path $pack 'Mods'
$compile = Join-Path $pack 'compile-verification'
foreach ($path in @($manifestPath,$mods,$compile)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required pack input is missing: $path" }
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.result -ne 'pass' -or
    $manifest.variant -ne 'angular-source-coverage-diagnostic-v1' -or
    [bool]$manifest.runtimeEligible -or [bool]$manifest.installed -or [bool]$manifest.liveTestsPerformed) {
    throw 'Angular-coverage manifest state is invalid.'
}
if (-not [bool]$manifest.validation.sourceTemporalPackGatePassed -or
    [int]$manifest.validation.compiledShaderCount -ne 10 -or
    -not [bool]$manifest.validation.exactNativeOffPath -or
    -not [bool]$manifest.validation.finishedSceneFeedbackAbsent -or
    -not [bool]$manifest.validation.F10Unchanged -or
    -not [bool]$manifest.validation.F2MasterPreserved -or
    -not [bool]$manifest.validation.PageUpDiagnosticOnly -or
    -not [bool]$manifest.validation.PageDownUnchanged) {
    throw 'Angular-coverage validation contract is incomplete.'
}

$sourceManifestPath = [string]$manifest.source.temporalPackManifest
if (-not (Test-Path -LiteralPath $sourceManifestPath -PathType Leaf) -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceManifestPath).Hash -ne [string]$manifest.source.temporalPackManifestSha256) {
    throw 'Pinned temporal source pack is missing or drifted.'
}
& (Join-Path $PSScriptRoot 'Test-IntergradeR3DSSGITemporalHistoryPack.ps1') -PackRoot (Split-Path -Parent $sourceManifestPath) | Out-Null

$baselinePath = Join-Path $mods 'Agent2R3DSSGITraceE2AA_ps.hlsl'
$dense8Path = Join-Path $mods 'Agent2R3DSSGITrace8E2AA_ps.hlsl'
$dense16Path = Join-Path $mods 'Agent2R3DSSGITrace16E2AA_ps.hlsl'
foreach ($path in @($baselinePath,$dense8Path,$dense16Path)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Trace shader is missing: $path" }
}
$baseline = [IO.File]::ReadAllText($baselinePath)
$anchor = 'static const uint AGENT2_SLICE_COUNT = 4;'
if ([regex]::Matches($baseline,[regex]::Escape($anchor)).Count -ne 1) { throw 'Baseline trace no longer has exactly four slices.' }
if ([IO.File]::ReadAllText($dense8Path) -cne $baseline.Replace($anchor,'static const uint AGENT2_SLICE_COUNT = 8;')) {
    throw 'Eight-slice trace differs from baseline beyond the one controlled constant.'
}
if ([IO.File]::ReadAllText($dense16Path) -cne $baseline.Replace($anchor,'static const uint AGENT2_SLICE_COUNT = 16;')) {
    throw 'Sixteen-slice trace differs from baseline beyond the one controlled constant.'
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $baselinePath).Hash -ne [string]$manifest.source.baselineTraceSha256) {
    throw 'Baseline trace drifted after the experiment was generated.'
}

$iniPath = Join-Path $mods 'Agent2R3DSSGITest.ini'
$ini = [IO.File]::ReadAllText($iniPath)
foreach ($required in @(
    'key = no_modifiers F2',
    'key = no_modifiers VK_PRIOR',
    '$agent2_ssgi_angular_coverage = 0, 1, 2',
    'run = CustomShaderAgent2R3DSSGITrace',
    'run = CustomShaderAgent2R3DSSGITrace8',
    'run = CustomShaderAgent2R3DSSGITrace16',
    'run = CustomShaderAgent2R3DSSGITemporalHistory',
    'clear = ResourceAgent2SSGIHistory 0.0',
    'ResourceAgent2SSGIScene = reference ps-t2',
    'post ps-t2 = reference ResourceAgent2SSGIOriginalT2'
)) {
    if (-not $ini.Contains($required)) { throw "INI contract is missing: $required" }
}
foreach ($forbidden in @(
    'ResourceAgent2SSGITarget = reference o0',
    'ResourceAgent2SSGIScene = copy o0',
    'ResourceAgent2SSGIHistory = copy o0',
    'ResourceAgent2SSGIHistory = reference o0',
    'hash = af6cd28a0108a18a'
)) {
    if ($ini.Contains($forbidden)) { throw "Feedback or obsolete hook survived: $forbidden" }
}
if ($ini -match '(?im)^\s*key\s*=.*(?:F10|VK_NEXT).*$') { throw 'F10 or Page Down was rebound.' }
if ([regex]::Matches($ini,'(?im)^\s*key\s*=.*F2\s*$').Count -ne 1) { throw 'F2 must have exactly one binding.' }
if ([regex]::Matches($ini,'(?im)^\s*key\s*=.*VK_PRIOR\s*$').Count -ne 1) { throw 'Page Up must have exactly one diagnostic binding.' }
if ([regex]::Matches($ini,'(?m)^\s*run\s*=\s*CustomShaderAgent2R3DSSGITrace(?:8|16)?\s*$').Count -ne 3) {
    throw 'Exactly three mutually selected trace invocations are required.'
}

$files = @($manifest.files)
if ($files.Count -ne 11) { throw "Expected eleven Mods payload files; found $($files.Count)." }
foreach ($entry in $files) {
    $path = Join-Path $mods ([string]$entry.name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$entry.sha256) {
        throw "Payload file drifted: $($entry.name)"
    }
}
$compiled = @($manifest.compile)
if ($compiled.Count -ne 10) { throw "Expected ten compile receipts; found $($compiled.Count)." }
foreach ($entry in $compiled) {
    $base = [IO.Path]::GetFileNameWithoutExtension([string]$entry.name)
    $hlsl = Join-Path $mods ([string]$entry.name)
    $binary = Join-Path $compile ($base + '.bin')
    $assembly = Join-Path $compile ($base + '.asm')
    foreach ($path in @($hlsl,$binary,$assembly)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Compile artifact is missing: $path" }
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $hlsl).Hash -ne [string]$entry.hlslSha256 -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $binary).Hash -ne [string]$entry.dxbcSha256 -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $assembly).Hash -ne [string]$entry.assemblySha256) {
        throw "Compile artifact drifted: $($entry.name)"
    }
}
if ((@($manifest.experiment.sliceCounts) -join ',') -ne '4,8,16' -or
    (@($manifest.experiment.samplesPerPixel) -join ',') -ne '64,128,256' -or
    [int]$manifest.experiment.radialStepsPerSlice -ne 16) {
    throw 'Experiment dimensions changed.'
}

Write-Host 'PASS: the angular-coverage diagnostic strictly compiles identical 4/8/16-slice traces, preserves F2 as master, binds only Page Up for the test cycle, leaves F10/Page Down untouched, retains native OFF/history/composite behavior, and contains no finished-scene feedback.'
