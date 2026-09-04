[CmdletBinding()]
param(
    [string]$PackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\intergrade-native-light-profile-capture-pack-v1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$manifestPath = Join-Path $PackRoot 'manifest.json'
$iniPath = Join-Path $PackRoot 'Mods\IntergradeNativeLightProfileCapture.ini'
foreach ($path in @($manifestPath,$iniPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required capture-pack file is missing: $path" }
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$ini = [IO.File]::ReadAllText($iniPath)
if ($manifest.schemaVersion -ne 1 -or $manifest.result -ne 'pass' -or
    $manifest.packId -ne 'ff7-remake-native-light-profile-activation-capture-v1' -or
    [bool]$manifest.runtimeEligible -or [bool]$manifest.installed -or [bool]$manifest.liveCapturePerformed -or [bool]$manifest.gameFilesModified) {
    throw 'Native light-profile capture manifest state is invalid.'
}
if (@($manifest.automaticFamilies).Count -ne 3 -or (@($manifest.automaticFamilies.memberCount) -join ',') -ne '3,1,1') {
    throw 'Accepted automatic family cardinality changed.'
}
$expected = @('08bb8764f1840179','0e97888f9a8767da','5a9fbefe0ab6f815','62b33a2d1e505241','c30cdc8365df9840','f97a821dddaa328a')
$actual = @(@($manifest.variants.hash) + [string]$manifest.classifier.hash | Sort-Object)
if (($actual -join '|') -cne ($expected -join '|')) { throw 'Capture target set changed.' }
foreach ($hash in $expected) {
    if ([regex]::Matches($ini,"(?im)^hash\s*=\s*$hash\s*$").Count -ne 1) { throw "Expected exactly one capture override for $hash" }
}
if ([regex]::Matches($ini,'(?im)^analyse_options\s*=\s*dump_rt dump_tex dump_cb mono desc\s*$').Count -ne 6) {
    throw 'Each exact target must have the narrowed read-only analysis options.'
}
foreach ($forbidden in @(
    '(?im)^\s*key\s*=',
    '(?im)^\s*handling\s*=',
    '(?im)^\s*run\s*=',
    '(?im)^\s*(?:draw|dispatch)\s*=',
    '(?im)^\s*(?:ps|cs|vs|gs|hs|ds)-t\d+\s*=',
    '(?im)^\s*(?:o\d+|ps|cs|vs|gs|hs|ds)\s*='
)) {
    if ($ini -match $forbidden) { throw "Rendering mutation leaked into capture-only INI: $forbidden" }
}
foreach ($variant in @($manifest.variants)) {
    if ([int]$variant.nativeInstructionCount -le 0 -or $variant.depthBinding -notmatch '^t[45]$' -or
        $variant.lightListBinding -notmatch '^t1[12]$' -or $variant.priorLightingBinding -notmatch '^t[89]$') {
        throw "Variant provenance is incomplete: $($variant.hash)"
    }
}
$record = @($manifest.files | Where-Object path -eq 'Mods/IntergradeNativeLightProfileCapture.ini')
if ($record.Count -ne 1 -or $record[0].sha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $iniPath).Hash) { throw 'Capture INI checksum does not match its manifest.' }
if ($manifest.invariants.F10 -ne 'unchanged shader reload' -or $manifest.invariants.F2 -ne 'unchanged indirect-light toggle' -or
    $manifest.invariants.PageUp -ne 'unchanged foreground test cycle' -or $manifest.invariants.PageDown -ne 'unchanged graduated master toggle') {
    throw 'Reserved-key contract changed.'
}
[pscustomobject]@{Result='pass';Families=3;Targets=6;RenderingMutated=$false;KeyBindings=0;PackRoot=(Resolve-Path -LiteralPath $PackRoot).Path}
