[CmdletBinding()]
param(
    [string]$MatrixRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-isolation-matrix')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$matrix = [IO.Path]::GetFullPath($MatrixRoot).TrimEnd('\')
$manifestPath = Join-Path $matrix 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Isolation manifest is missing: $manifestPath"
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$expectedVariants = @(
    '00-true-noop',
    '01-references-only',
    '02-scene-copy-only',
    '03-trace-only',
    '04-trace-denoise',
    '05-zero-composite',
    '06-zero-composite-no-depth',
    '07-zero-composite-no-draw'
)
$actualVariants = @($manifest.Variants | ForEach-Object Name)
if (@(Compare-Object $expectedVariants $actualVariants -SyncWindow 0).Count -ne 0) {
    throw "Unexpected isolation variants: $($actualVariants -join ', ')"
}

$expectedIniHashes = [ordered]@{
    '00-true-noop'='C9FFE50CC4630F9BB7CF4EA27E335612C7725D0D3604DEA609B040391EE4898E'
    '01-references-only'='6A65006627E374A1260F0926E0626BD18CC77A752E8F09C5F7D69718B409D964'
    '02-scene-copy-only'='6A426527AD63F183D087A77F4B72A6AB8AC510543AC5AF354E052D5CD2F1F409'
    '03-trace-only'='6C6CAF525119B8578213CFA8C8F5F6109FB114D420604C9E530F21A5D71B08CD'
    '04-trace-denoise'='D52031FC5D8EAC3117BEB4FDE2B9A38CE7AACD27DDEB363DBD3BCA0ECA967D85'
    '05-zero-composite'='CF2B9887F1AF9144FF84EF1B07FA08FA34A951D7421E23C09AD9DA859E96F353'
    '06-zero-composite-no-depth'='33A0C167D185C1CE2FCAB6ACC018FA774375FD1E3B7E9B42B22499D015FCE227'
    '07-zero-composite-no-draw'='1EC83FA7B6B5B260D16E7655C4478DF23A1245F77ADAEED4379CEFF62C7200A5'
}

foreach ($name in $expectedVariants) {
    $entry = @($manifest.Variants | Where-Object Name -eq $name)
    if ($entry.Count -ne 1) { throw "Variant is missing or duplicated: $name" }
    $iniRecord = @($entry[0].Files | Where-Object Name -eq 'Agent2R3DSSGITest.ini')
    if ($iniRecord.Count -ne 1 -or [string]$iniRecord[0].Sha256 -ne $expectedIniHashes[$name]) {
        throw "Recorded INI hash changed for $name."
    }
    $iniPath = Join-Path $matrix $name | Join-Path -ChildPath 'Mods\Agent2R3DSSGITest.ini'
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $iniPath).Hash -ne $expectedIniHashes[$name]) {
        throw "Generated INI hash changed for $name."
    }
    $ini = Get-Content -Raw -LiteralPath $iniPath
    if ([regex]::Matches($ini, '(?im)^\s*key\s*=.*(?<![A-Z0-9_])F2(?![A-Z0-9_]).*\r?$').Count -ne 1 -or
        $ini -match '(?im)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F10(?![A-Z0-9_]).*\r?$') {
        throw "Key ownership changed for $name."
    }
    if ($ini -match '(?im)^\s*ResourceAgent2R3DSSGIScene\s*=') {
        throw "Legacy mistyped scene resource remains in $name."
    }
    $declaredResources = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($match in [regex]::Matches($ini, '(?im)^\[(Resource[A-Z0-9_]+)\]\s*\r?$')) {
        [void]$declaredResources.Add($match.Groups[1].Value)
    }
    foreach ($match in [regex]::Matches($ini, '(?im)^\s*(Resource[A-Z0-9_]+)\s*=')) {
        if (-not $declaredResources.Contains($match.Groups[1].Value)) {
            throw "Operation writes undeclared resource $($match.Groups[1].Value) in $name."
        }
    }
}

$zeroCompositePath = Join-Path $matrix '05-zero-composite\Mods\Agent2R3DSSGICompositeE2AA_ps.hlsl'
$noDepthCompositePath = Join-Path $matrix '06-zero-composite-no-depth\Mods\Agent2R3DSSGICompositeE2AA_ps.hlsl'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $zeroCompositePath).Hash -ne
    (Get-FileHash -Algorithm SHA256 -LiteralPath $noDepthCompositePath).Hash) {
    throw 'The no-depth test changed the zero-output composite shader.'
}

$noDepthIni = Get-Content -Raw -LiteralPath (Join-Path $matrix '06-zero-composite-no-depth\Mods\Agent2R3DSSGITest.ini')
foreach ($line in @('depth_enable = false','depth_write_mask = zero','stencil_enable = false')) {
    if ([regex]::Matches($noDepthIni, "(?m)^$([regex]::Escape($line))\r?$").Count -ne 1) {
        throw "No-depth composite state is missing or duplicated: $line"
    }
}
foreach ($name in $expectedVariants | Where-Object { $_ -ne '06-zero-composite-no-depth' }) {
    $ini = Get-Content -Raw -LiteralPath (Join-Path $matrix "$name\Mods\Agent2R3DSSGITest.ini")
    if ($ini -match '(?im)^(?:depth_enable|depth_write_mask|stencil_enable)\s*=') {
        throw "Composite state isolation leaked into prior variant $name."
    }
}

$noDrawIni = Get-Content -Raw -LiteralPath (Join-Path $matrix '07-zero-composite-no-draw\Mods\Agent2R3DSSGITest.ini')
$compositeSection = [regex]::Match($noDrawIni, '(?ms)^\[CustomShaderAgent2R3DSSGIComposite\]\r?\n(?<body>.*?)(?=^\[|\z)')
if (-not $compositeSection.Success -or
    $compositeSection.Groups['body'].Value -match '(?im)^draw\s*=' -or
    [regex]::Matches($noDrawIni, '(?im)^draw = from_caller\r?$').Count -ne 5) {
    throw 'The no-draw variant did not remove exactly the composite draw.'
}

[pscustomobject]@{
    Result='pass'
    Variants=$expectedVariants.Count
    PriorHashesFrozen=6
    NewVariants='06-zero-composite-no-depth, 07-zero-composite-no-draw'
    F10='unbound'
}
