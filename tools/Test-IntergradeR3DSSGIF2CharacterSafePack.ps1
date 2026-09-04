[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$generator = Join-Path $PSScriptRoot 'New-IntergradeR3DSSGIF2CharacterSafePack.ps1'
$a = Join-Path $root 'artifacts\agent2-r3d-ssgi-f2-character-safe-pack-test-a'
$b = Join-Path $root 'artifacts\agent2-r3d-ssgi-f2-character-safe-pack-test-b'

& $generator -OutputDirectory $a | Out-Null
& $generator -OutputDirectory $b | Out-Null

function Get-Tree([string]$Path) {
    @(Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName | ForEach-Object {
        [pscustomobject]@{
            Relative = $_.FullName.Substring($Path.Length).TrimStart('\')
            Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
        }
    })
}

$treeA = Get-Tree $a
$treeB = Get-Tree $b
$delta = @(Compare-Object $treeA $treeB -Property Relative,Hash)
if ($delta.Count) { throw "Character-safe pack generation is not deterministic: $($delta | ConvertTo-Json -Compress)" }

$manifest = Get-Content -Raw -LiteralPath (Join-Path $a 'manifest.json') | ConvertFrom-Json
if ($manifest.result -ne 'pass' -or
    $manifest.variant -ne 'material-aware-bounded-hdr-character-safe-v1' -or
    [double]$manifest.effect.characterMaterialBoost -ne 0.025 -or
    [double]$manifest.effect.sourceRadianceCap -ne 4.0 -or
    [double]$manifest.effect.reconstructedIrradianceCap -ne 1.0 -or
    [double]$manifest.effect.diagnosticStrength -ne 1.25 -or
    @($manifest.files).Count -ne 7 -or $manifest.policy.runtimeEligible -or $manifest.policy.installed) {
    throw 'Character-safe manifest contract failed.'
}

$hlsl = Get-Content -Raw -LiteralPath (Join-Path $a 'Mods\Agent2R3DSSGICompositeE2AA_ps.hlsl')
if ([regex]::Matches($hlsl,'materialBoost = 0\.025;').Count -ne 1 -or
    $hlsl -match 'materialBoost = 0\.25;' -or
    $hlsl -notmatch 'materialBoost = AGENT2_PI;' -or
    $hlsl -notmatch 'shadingModel == 3u \|\| shadingModel == 7u \|\| shadingModel == 9u') {
    throw 'Character-only receiver edit was not isolated correctly.'
}

$base = Join-Path $root 'artifacts\agent2-r3d-ssgi-f2-radiance-stable-pack\Mods'
foreach ($name in @(
    'Agent2R3DSSGITraceE2AA_ps.hlsl',
    'Agent2R3DSSGIDenoise16_ps.hlsl',
    'Agent2R3DSSGIDenoise8_ps.hlsl',
    'Agent2R3DSSGIDenoise4_ps.hlsl',
    'Agent2R3DSSGIDenoise2_ps.hlsl',
    'Agent2R3DSSGITest.ini'
)) {
    $baseHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $base $name)).Hash
    $newHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $a "Mods\$name")).Hash
    if ($baseHash -ne $newHash) { throw "Non-composite payload changed: $name" }
}

$objectPath = Join-Path $a 'compile\Agent2R3DSSGICompositeE2AA_ps.obj'
$bytes = [IO.File]::ReadAllBytes($objectPath)
if ($bytes.Length -lt 4 -or [Text.Encoding]::ASCII.GetString($bytes,0,4) -ne 'DXBC') { throw 'Compiled object is not DXBC.' }

[pscustomobject]@{
    Result = 'pass'
    Deterministic = $true
    CharacterMaterialBoost = 0.025
    WorldResponsePreserved = $true
    BloomShaderUntouched = $true
    PayloadFiles = @($manifest.files).Count
    RuntimeEligible = $false
}
