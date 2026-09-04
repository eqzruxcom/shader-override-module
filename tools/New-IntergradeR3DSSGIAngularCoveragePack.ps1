[CmdletBinding()]
param(
    [string]$SourcePackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-temporal-history-pack-static-reprojection-v2'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-angular-coverage-pack-v1'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$source = [IO.Path]::GetFullPath($SourcePackRoot).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$utf8 = [Text.UTF8Encoding]::new($false)
$lf = [char]10

foreach ($path in @($source,$output)) {
    if (-not $path.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'SourcePackRoot and OutputRoot must remain below workspace artifacts.'
    }
}
if (-not (Test-Path -LiteralPath $FxcPath -PathType Leaf)) { throw "FXC is missing: $FxcPath" }
if (Test-Path -LiteralPath $output) { throw "OutputRoot already exists; preserve prior evidence: $output" }

$baselineTest = Join-Path $PSScriptRoot 'Test-IntergradeR3DSSGITemporalHistoryPack.ps1'
& $baselineTest -PackRoot $source | Out-Null
$sourceManifestPath = Join-Path $source 'manifest.json'
$sourceManifest = Get-Content -Raw -LiteralPath $sourceManifestPath | ConvertFrom-Json
if ($sourceManifest.variant -ne 'private-temporal-indirect-history' -or
    $sourceManifest.result -ne 'pass' -or
    [bool]$sourceManifest.runtimeEligible -or
    [bool]$sourceManifest.installed -or
    [bool]$sourceManifest.liveTestsPerformed -or
    -not [bool]$sourceManifest.validation.finishedSceneFeedbackAbsent -or
    -not [bool]$sourceManifest.validation.staticSurfaceFallbackMatchedNativeAssembly) {
    throw 'Source temporal pack failed its closed offline contract.'
}

$sourceMods = Join-Path $source 'Mods'
$mods = Join-Path $output 'Mods'
$compile = Join-Path $output 'compile-verification'
[void][IO.Directory]::CreateDirectory($mods)
[void][IO.Directory]::CreateDirectory($compile)
foreach ($entry in @($sourceManifest.files)) {
    $sourcePath = Join-Path $sourceMods ([string]$entry.name)
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash -ne [string]$entry.sha256) {
        throw "Source temporal payload drifted: $($entry.name)"
    }
    [IO.File]::Copy($sourcePath,(Join-Path $mods ([string]$entry.name)),$false)
}

$baselineTracePath = Join-Path $mods 'Agent2R3DSSGITraceE2AA_ps.hlsl'
$baselineTrace = [IO.File]::ReadAllText($baselineTracePath)
$anchor = 'static const uint AGENT2_SLICE_COUNT = 4;'
if ([regex]::Matches($baselineTrace,[regex]::Escape($anchor)).Count -ne 1) {
    throw 'Baseline four-slice trace anchor is not unique.'
}
$dense8Path = Join-Path $mods 'Agent2R3DSSGITrace8E2AA_ps.hlsl'
$dense16Path = Join-Path $mods 'Agent2R3DSSGITrace16E2AA_ps.hlsl'
[IO.File]::WriteAllText($dense8Path,$baselineTrace.Replace($anchor,'static const uint AGENT2_SLICE_COUNT = 8;'),$utf8)
[IO.File]::WriteAllText($dense16Path,$baselineTrace.Replace($anchor,'static const uint AGENT2_SLICE_COUNT = 16;'),$utf8)

$iniPath = Join-Path $mods 'Agent2R3DSSGITest.ini'
$ini = [regex]::Replace([IO.File]::ReadAllText($iniPath),"\r\n?",[string]$lf)
$keyAnchor = '$agent2_ssgi_test = 0, 1' + $lf + $lf + '[ResourceAgent2SSGITarget]'
if ([regex]::Matches($ini,[regex]::Escape($keyAnchor)).Count -ne 1) {
    throw 'F2-to-resource key insertion anchor is not unique.'
}
$pageUp = @(
    '$agent2_ssgi_test = 0, 1',
    '',
    '; PAGE UP cycles only angular source coverage while F2 is ON.',
    '[KeyAgent2R3DSSGIAngularCoveragePageUp]',
    'key = no_modifiers VK_PRIOR',
    'type = cycle',
    'smart = true',
    '$agent2_ssgi_angular_coverage = 0, 1, 2',
    '',
    '[ResourceAgent2SSGITarget]'
) -join $lf
$ini = $ini.Replace($keyAnchor,$pageUp)
$constantAnchor = 'global $agent2_ssgi_test = 0'
if ([regex]::Matches($ini,[regex]::Escape($constantAnchor)).Count -ne 1) {
    throw 'Coverage constant insertion anchor is not unique.'
}
$ini = $ini.Replace($constantAnchor,$constantAnchor + $lf + 'global $agent2_ssgi_angular_coverage = 0')

$tracePattern = '(?ms)^\[CustomShaderAgent2R3DSSGITrace\]\n.*?(?=^\[CustomShaderAgent2R3DSSGIDenoise16\])'
$traceMatch = [regex]::Match($ini,$tracePattern)
if (-not $traceMatch.Success) { throw 'Baseline trace custom-shader section is not unique.' }
$traceSection = $traceMatch.Value
$dense8Section = $traceSection.Replace(
    '[CustomShaderAgent2R3DSSGITrace]',
    '[CustomShaderAgent2R3DSSGITrace8]').Replace(
    'ps = Agent2R3DSSGITraceE2AA_ps.hlsl',
    'ps = Agent2R3DSSGITrace8E2AA_ps.hlsl')
$dense16Section = $traceSection.Replace(
    '[CustomShaderAgent2R3DSSGITrace]',
    '[CustomShaderAgent2R3DSSGITrace16]').Replace(
    'ps = Agent2R3DSSGITraceE2AA_ps.hlsl',
    'ps = Agent2R3DSSGITrace16E2AA_ps.hlsl')
$ini = [regex]::Replace($ini,$tracePattern,$traceSection + $dense8Section + $dense16Section,1)

$runAnchor = '    run = CustomShaderAgent2R3DSSGITrace'
if ([regex]::Matches($ini,[regex]::Escape($runAnchor)).Count -ne 1) {
    throw 'Baseline trace invocation is not unique.'
}
$runBlock = @(
    '    if $agent2_ssgi_angular_coverage == 0',
    '        run = CustomShaderAgent2R3DSSGITrace',
    '    else if $agent2_ssgi_angular_coverage == 1',
    '        run = CustomShaderAgent2R3DSSGITrace8',
    '    else',
    '        run = CustomShaderAgent2R3DSSGITrace16',
    '    endif'
) -join $lf
$ini = $ini.Replace($runAnchor,$runBlock)

foreach ($required in @(
    'key = no_modifiers F2',
    'key = no_modifiers VK_PRIOR',
    '$agent2_ssgi_angular_coverage = 0, 1, 2',
    '[CustomShaderAgent2R3DSSGITrace]',
    '[CustomShaderAgent2R3DSSGITrace8]',
    '[CustomShaderAgent2R3DSSGITrace16]',
    'ps = Agent2R3DSSGITrace8E2AA_ps.hlsl',
    'ps = Agent2R3DSSGITrace16E2AA_ps.hlsl',
    'run = CustomShaderAgent2R3DSSGITemporalHistory',
    'clear = ResourceAgent2SSGIHistory 0.0'
)) {
    if (-not $ini.Contains($required)) { throw "Coverage INI lacks: $required" }
}
if ($ini -match '(?im)^\s*key\s*=.*(?:F10|VK_NEXT).*$') {
    throw 'F10 or Page Down was rebound by the angular-coverage diagnostic.'
}
if ([regex]::Matches($ini,'(?im)^\s*key\s*=.*F2\s*$').Count -ne 1 -or
    [regex]::Matches($ini,'(?im)^\s*key\s*=.*VK_PRIOR\s*$').Count -ne 1) {
    throw 'F2 and Page Up must each have exactly one binding.'
}
[IO.File]::WriteAllText($iniPath,$ini,$utf8)

$compiled = [Collections.Generic.List[object]]::new()
foreach ($file in @(Get-ChildItem -LiteralPath $mods -Filter '*.hlsl' -File | Sort-Object Name)) {
    $profile = if ($file.Name.EndsWith('_vs.hlsl',[StringComparison]::OrdinalIgnoreCase)) { 'vs_5_0' } else { 'ps_5_0' }
    $binary = Join-Path $compile ($file.BaseName + '.bin')
    $assembly = Join-Path $compile ($file.BaseName + '.asm')
    & $FxcPath /nologo /Ges /WX /O3 /T $profile /E main /Fo $binary /Fc $assembly $file.FullName
    if ($LASTEXITCODE -ne 0) { throw "Strict HLSL compilation failed ($profile): $($file.Name)" }
    $compiled.Add([ordered]@{
        name = $file.Name
        profile = $profile
        hlslSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
        dxbcSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $binary).Hash
        assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assembly).Hash
    })
}
if ($compiled.Count -ne 10) { throw "Expected ten compiled HLSL shaders; found $($compiled.Count)." }

$files = @(Get-ChildItem -LiteralPath $mods -File | Sort-Object Name | ForEach-Object {
    [ordered]@{
        name = $_.Name
        bytes = $_.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
    }
})
if ($files.Count -ne 11) { throw "Expected eleven Mods payload files; found $($files.Count)." }

$manifest = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    variant = 'angular-source-coverage-diagnostic-v1'
    purpose = 'Isolate sparse angular ray coverage from temporal-history behavior by cycling otherwise identical 4-, 8-, and 16-slice traces.'
    source = [ordered]@{
        temporalPackManifest = $sourceManifestPath
        temporalPackManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceManifestPath).Hash
        baselineTraceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $baselineTracePath).Hash
    }
    controls = [ordered]@{
        F2 = 'off/on master for this indirect-light candidate; OFF clears private history'
        PageUp = 'cycle angular coverage: 4 slices, 8 slices, 16 slices'
        F10 = 'native reload, unchanged'
        PageDown = 'graduated master, unchanged'
    }
    experiment = [ordered]@{
        independentVariable = 'angular slice count'
        sliceCounts = @(4,8,16)
        radialStepsPerSlice = 16
        samplesPerPixel = @(64,128,256)
        unchanged = @('radiance source','world reconstruction','denoise','temporal reprojection','history decay','composite strength')
        interpretation = 'If 8/16 slices materially stabilize a visible emitter while 4 slices cuts out, sparse angular sampling is causal. If all three cut out together, instrument history validity next.'
    }
    validation = [ordered]@{
        sourceTemporalPackGatePassed = $true
        compiledShaderCount = $compiled.Count
        exactNativeOffPath = $true
        finishedSceneFeedbackAbsent = $true
        F10Unchanged = $true
        F2MasterPreserved = $true
        PageUpDiagnosticOnly = $true
        PageDownUnchanged = $true
    }
    compile = @($compiled)
    files = $files
    runtimeEligible = $false
    installed = $false
    liveTestsPerformed = $false
    generatedUtc = [DateTime]::UtcNow.ToString('o')
}
$manifestPath = Join-Path $output 'manifest.json'
[IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 12) + [Environment]::NewLine,$utf8)

[pscustomobject]@{
    Result = 'pass'
    OutputRoot = $output
    Manifest = $manifestPath
    CompiledShaders = $compiled.Count
    PayloadFiles = $files.Count
    RuntimeEligible = $false
    Installed = $false
}
