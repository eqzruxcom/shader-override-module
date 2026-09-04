[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-character-safe-pack'),
    [ValidateRange(0.0,1.0)]
    [double]$CharacterMaterialBoost = 0.025,
    [int[]]$CharacterShadingModels = @(3,7,9),
    [string]$Variant = 'material-aware-bounded-hdr-character-safe-v1',
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if (-not $output.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Output escaped project: $output" }
if (-not (Test-Path -LiteralPath $FxcPath -PathType Leaf)) { throw "FXC is missing: $FxcPath" }
$models = @($CharacterShadingModels | Sort-Object -Unique)
if (-not $models.Count -or @($models | Where-Object { $_ -lt 1 -or $_ -gt 15 }).Count) {
    throw 'Character shading models must be unique values from 1 through 15.'
}
$boostText = $CharacterMaterialBoost.ToString('0.###############',[Globalization.CultureInfo]::InvariantCulture)
$conditionText = ($models | ForEach-Object { "shadingModel == $($_)u" }) -join ' || '

$baseRoot = Join-Path $root 'artifacts\agent2-r3d-ssgi-f2-radiance-stable-pack'
$baseManifestPath = Join-Path $baseRoot 'manifest.json'
$compositeRelative = 'Mods\Agent2R3DSSGICompositeE2AA_ps.hlsl'
$compositePath = Join-Path $baseRoot $compositeRelative
$expected = [ordered]@{
    $baseManifestPath = 'E99F5F2E395A6F86EE824C154983A12CCBF5F2F2EC557C1223EFA6B4D8FDAFC4'
    $compositePath = '684B749B4932844B2B61D650049AF51788FFC94EE06DED10526583B6B7A30245'
}
foreach ($entry in $expected.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Key -PathType Leaf)) { throw "Required input is missing: $($entry.Key)" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Key).Hash
    if ($actual -ne $entry.Value) { throw "Pinned input drifted: $($entry.Key) expected $($entry.Value), found $actual" }
}

$base = Get-Content -Raw -LiteralPath $baseManifestPath | ConvertFrom-Json
if ($base.classification -ne 'offline-f2-standalone-live-topology-candidate' -or
    $base.variant -ne 'material-aware-bounded-hdr-radiance-v1' -or
    $base.target.shader -ne 'e2aa1c8cb39e0a55' -or @($base.files).Count -ne 7 -or
    $base.policy.runtimeEligible -or $base.policy.installed -or $base.policy.gameFilesTouched) {
    throw 'Radiance-stable base package contract changed.'
}

$composite = Get-Content -Raw -LiteralPath $compositePath
$oldBoost = '        materialBoost = 0.25;'
$oldCommentPattern = '    // Rebirth keeps ordinary lit surfaces at its visible environmental strength,\r?\n    // but reduces the response on character skin, hair, and eyes\.'
if ([regex]::Matches($composite, [regex]::Escape($oldBoost)).Count -ne 1) { throw 'Character-response anchor changed.' }
if ([regex]::Matches($composite, $oldCommentPattern).Count -ne 1) { throw 'Character-response comment anchor changed.' }
$composite = [regex]::Replace($composite, $oldCommentPattern,
    '    // Keep the accepted world response unchanged, but tightly bound character receivers.' + [Environment]::NewLine +
    "    // Pale skin reached the bloom chain even after the HDR caps; $boostText limits that upstream.")
$composite = $composite.Replace('shadingModel == 3u || shadingModel == 7u || shadingModel == 9u', $conditionText)
$composite = $composite.Replace($oldBoost, "        materialBoost = $boostText;")

$modsOut = Join-Path $output 'Mods'
$compileOut = Join-Path $output 'compile'
[IO.Directory]::CreateDirectory($modsOut) | Out-Null
[IO.Directory]::CreateDirectory($compileOut) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)

foreach ($entry in @($base.files)) {
    $relative = ([string]$entry.path).Replace('/', '\')
    $source = Join-Path $baseRoot $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash -ne [string]$entry.sha256) {
        throw "Base payload drifted: $relative"
    }
    $destination = Join-Path $output $relative
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    if ($relative -eq $compositeRelative) {
        [IO.File]::WriteAllText($destination, $composite, $utf8)
    } else {
        [IO.File]::Copy($source, $destination, $true)
    }
}

function Compile-Hlsl([string]$Name, [string]$Path) {
    $object = Join-Path $compileOut ($Name + '.obj')
    $assembly = Join-Path $compileOut ($Name + '.asm')
    $temporary = Join-Path $compileOut ('.' + $Name + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $messages = & $FxcPath /nologo /T ps_5_0 /E main /Ges /WX /O3 /Fo $temporary /Fc $assembly $Path 2>&1
        if ($LASTEXITCODE -ne 0) { throw "FXC failed for ${Name}: $($messages -join ' ')" }
        $bytes = [IO.File]::ReadAllBytes($temporary)
        if ($bytes.Length -lt 4 -or [Text.Encoding]::ASCII.GetString($bytes,0,4) -ne 'DXBC') { throw "$Name did not compile to DXBC." }
        [IO.File]::Copy($temporary,$object,$true)
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
    }
    [ordered]@{
        name = $Name
        profile = 'ps_5_0'
        objectSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $object).Hash
        assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assembly).Hash
    }
}

$compositeCompile = Compile-Hlsl 'Agent2R3DSSGICompositeE2AA_ps' (Join-Path $output $compositeRelative)
$compile = @($base.compile | ForEach-Object {
    if ($_.name -eq 'Agent2R3DSSGICompositeE2AA_ps') { $compositeCompile }
    else { [ordered]@{name=[string]$_.name;profile=[string]$_.profile;objectSha256=[string]$_.objectSha256;assemblySha256=[string]$_.assemblySha256} }
})

$manifest = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    classification = 'offline-f2-standalone-live-topology-candidate'
    variant = $Variant
    target = $base.target
    source = [ordered]@{
        radianceStableManifest = 'artifacts\agent2-r3d-ssgi-f2-radiance-stable-pack\manifest.json'
        radianceStableManifestSha256 = $expected[$baseManifestPath]
        observation = 'The bounded-HDR live test still whitened character skin; c583 was proven to be a downstream bloom-pyramid shader rather than the indirect-light owner.'
    }
    baseline = $base.baseline
    effect = [ordered]@{
        algorithm = [string]$base.effect.algorithm
        resolution = [string]$base.effect.resolution
        unrealUnitsToMeters = [double]$base.effect.unrealUnitsToMeters
        depthClear = [double]$base.effect.depthClear
        depthConvention = [string]$base.effect.depthConvention
        sampling = [string]$base.effect.sampling
        denoiseSteps = @($base.effect.denoiseSteps)
        upsample = [string]$base.effect.upsample
        receiverDiffuse = "unlit 0 excluded; shading models $($models -join ',') use $boostText material boost after 1/pi; all other lit surfaces retain the reviewed pi boost"
        characterShadingModels = $models
        characterMaterialBoost = $CharacterMaterialBoost
        sourceRadianceCap = [double]$base.effect.sourceRadianceCap
        reconstructedIrradianceCap = [double]$base.effect.reconstructedIrradianceCap
        capBehavior = [string]$base.effect.capBehavior
        composite = [string]$base.effect.composite
        diagnosticStrength = [double]$base.effect.diagnosticStrength
        highSrvSlotsRestored = @($base.effect.highSrvSlotsRestored)
    }
    controls = $base.controls
    compile = $compile
    files = @(Get-ChildItem -LiteralPath $modsOut -File | Sort-Object Name | ForEach-Object {
        [ordered]@{path=('Mods\' + $_.Name);sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash}
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
$manifestPath = Join-Path $output 'manifest.json'
[IO.File]::WriteAllText($manifestPath,(($manifest | ConvertTo-Json -Depth 16)+[Environment]::NewLine),$utf8)

[pscustomobject]@{
    Result = 'pass'
    Variant = $manifest.variant
    CharacterMaterialBoost = $manifest.effect.characterMaterialBoost
    WorldResponseChanged = $false
    BloomShaderChanged = $false
    PayloadFiles = $manifest.files.Count
    CompiledShaders = 1
    LiveFilesTouched = $false
    RuntimeEligible = $false
    Output = $manifestPath
}
