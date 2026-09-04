[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-standalone-pack'),
    [string]$OwnerPackDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-owner-integration-pack')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$ownerPack = [IO.Path]::GetFullPath($OwnerPackDirectory).TrimEnd('\')
$ownerManifestPath = Join-Path $ownerPack 'manifest.json'
$ownerIniPath = Join-Path $ownerPack 'Mods\RebirthEffectsDX11.ini'
$liveTopologyPath = Join-Path $root 'artifacts\analysis\agent2-r3d-ssgi-live-topology.json'
foreach ($required in @($ownerManifestPath, $ownerIniPath, $liveTopologyPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required standalone-pack input is missing: $required" }
}

function Get-Hash([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

$ownerManifest = Get-Content -Raw -LiteralPath $ownerManifestPath | ConvertFrom-Json
if ($ownerManifest.schemaVersion -ne 1 -or $ownerManifest.result -ne 'pass' -or
    $ownerManifest.classification -ne 'offline-f2-owner-integration-candidate' -or
    $ownerManifest.target.shader -ne 'e2aa1c8cb39e0a55' -or
    $ownerManifest.policy.runtimeEligible -ne $false -or $ownerManifest.policy.installed -ne $false -or
    $ownerManifest.policy.gameFilesTouched -ne $false) {
    throw 'Source owner pack is not the verified fail-closed R3D SSGI pack.'
}
foreach ($file in @($ownerManifest.files)) {
    $path = [IO.Path]::GetFullPath((Join-Path $ownerPack ([string]$file.path)))
    if (-not $path.StartsWith($ownerPack + '\', [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-Hash $path) -ne [string]$file.sha256) {
        throw "Source owner-pack payload failed validation: $($file.path)"
    }
}

$topology = Get-Content -Raw -LiteralPath $liveTopologyPath | ConvertFrom-Json
if ($topology.result -ne 'pass' -or $topology.classification -ne 'live-topology-requires-standalone-f2-hook' -or
    $topology.activeOwnerPresent -ne $false -or $topology.ownerIntegrationEligible -ne $false -or
    $topology.standalonePreflightEligible -ne $true -or $topology.gameFilesTouched -ne $false) {
    throw 'Live topology evidence does not require the standalone hook.'
}

$ownerText = Get-Content -Raw -LiteralPath $ownerIniPath
$agentBlockMatch = [regex]::Match(
    $ownerText,
    '(?ms)^; AGENT 2 R3D SSGI F2 TEST BEGIN\r?\n.*?^; AGENT 2 R3D SSGI F2 TEST END\r?$'
)
if (-not $agentBlockMatch.Success) { throw 'Source owner pack is missing the exact Agent 2 section block.' }
$agentBlock = $agentBlockMatch.Value
$agentBlock = $agentBlock.Replace(
    '; F1 remains reserved for the future global switch. F3 remains rolling A/B.',
    '; F1 remains reserved for the future global switch. F3 remains unbound.'
)

$f2OverrideMatch = [regex]::Match(
    $ownerText,
    '(?ms)^\[ShaderOverrideRebirthABShared\]\r?\nhash = e2aa1c8cb39e0a55\r?\nallow_duplicate_hash = true\r?\n(?<body>if \$agent2_ssgi_test == 1\r?\n.*?^endif\r?$)'
)
if (-not $f2OverrideMatch.Success) { throw 'Source owner pack is missing the isolated F2 override body.' }
$f2Body = $f2OverrideMatch.Groups['body'].Value.TrimEnd("`r", "`n")
if ($f2Body -match 'rebirth_ab_current|CustomShaderRebirthAB') { throw 'Standalone F2 body captured rolling A/B owner logic.' }

$outputFull = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$allowedOutputRoot = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
if (-not $outputFull.StartsWith($allowedOutputRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Standalone pack output must remain under $allowedOutputRoot"
}
$mods = Join-Path $outputFull 'Mods'
[IO.Directory]::CreateDirectory($mods) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)

$crlf = [Environment]::NewLine
$standaloneIni = [string]::Join($crlf, @(
    '; Agent 2 standalone R3D SSGI test for the current live topology.',
    '; It does not activate the disabled Rebirth owner or bind F1/F3.',
    '[Constants]',
    'global $agent2_ssgi_test = 0',
    '',
    ($agentBlock -replace '\r?\n', $crlf),
    '',
    '[ShaderOverrideAgent2R3DSSGIF2Test]',
    'hash = e2aa1c8cb39e0a55',
    'allow_duplicate_hash = true',
    ($f2Body -replace '\r?\n', $crlf),
    ''
))
$standaloneIniPath = Join-Path $mods 'Agent2R3DSSGITest.ini'
[IO.File]::WriteAllText($standaloneIniPath, $standaloneIni, $utf8)

$shaderNames = @(
    'Agent2R3DSSGICompositeE2AA_ps.hlsl',
    'Agent2R3DSSGIDenoise16_ps.hlsl',
    'Agent2R3DSSGIDenoise2_ps.hlsl',
    'Agent2R3DSSGIDenoise4_ps.hlsl',
    'Agent2R3DSSGIDenoise8_ps.hlsl',
    'Agent2R3DSSGITraceE2AA_ps.hlsl'
)
foreach ($name in $shaderNames) {
    $source = Join-Path $ownerPack ('Mods\' + $name)
    [IO.File]::Copy($source, (Join-Path $mods $name), $true)
}

$actualFiles = @(Get-ChildItem -LiteralPath $mods -File | Sort-Object Name)
if ($actualFiles.Count -ne 7) { throw "Standalone Mods payload must contain exactly seven files; found $($actualFiles.Count)." }

$manifest = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    classification = 'offline-f2-standalone-live-topology-candidate'
    target = [ordered]@{
        shader = 'e2aa1c8cb39e0a55'
        event = 1096
        ini = 'Mods\Agent2R3DSSGITest.ini'
        activeOwnerRequired = $false
    }
    source = [ordered]@{
        ownerPackManifest = [IO.Path]::GetRelativePath($root, $ownerManifestPath)
        ownerPackManifestSha256 = Get-Hash $ownerManifestPath
        liveTopologyEvidence = [IO.Path]::GetRelativePath($root, $liveTopologyPath)
        liveTopologyEvidenceSha256 = Get-Hash $liveTopologyPath
    }
    baseline = [ordered]@{
        activeRebirthOwnerPresent = $false
        disabledRebirthOwner = [ordered]@{name='RebirthEffectsDX11.ini.disabled'; sha256='EFA15E2A820D6CEE6A919AD3B14B736A8ED428B9C779693FF832479B2CC40ECD'}
        generatedIni = [ordered]@{name='UE4EffectsGenerated.ini'; sha256='D198023FB70F9F02CC8588D3E022AA7AC43AC2BC04AA460B70353285DD065B08'}
        activeClaims = [ordered]@{F1=0; F2=0; F3=0; e2aa=0}
    }
    effect = $ownerManifest.effect
    controls = [ordered]@{
        F1 = 'reserved and unbound'
        F2 = 'standalone SSGI candidate off/on'
        F3 = 'current live unbound state preserved'
    }
    compile = @($ownerManifest.compile)
    files = @($actualFiles | ForEach-Object {
        [ordered]@{path='Mods\' + $_.Name; sha256=Get-Hash $_.FullName}
    })
    policy = [ordered]@{
        exactLiveBaselineRequired = $true
        activatesDisabledOwner = $false
        runtimeEligible = $false
        installed = $false
        gameFilesTouched = $false
        liveCaptureRequired = $true
    }
}
$manifestPath = Join-Path $outputFull 'manifest.json'
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 12) + $crlf), $utf8)

[pscustomobject]@{
    Result = 'pass'
    Output = $outputFull
    PayloadFiles = $actualFiles.Count
    ShadersCompiledBySourcePack = @($manifest.compile).Count
    F1Bound = $false
    F2Bound = $true
    F3Bound = $false
    ActivatesDisabledOwner = $false
    RuntimeEligible = $false
    Installed = $false
}
