[CmdletBinding()]
param(
    [string]$ProfileReportPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-tiled-light-profile-branch-20260904.json'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-tiled-local-light-dataflow-20260904.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$profilePath = [IO.Path]::GetFullPath($ProfileReportPath)
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $profilePath.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "ProfileReportPath must remain under artifacts: $profilePath" }
if (-not $output.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "OutputPath must remain under artifacts: $output" }
if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) { throw "Profile report is missing: $profilePath" }

function Normalize-Dxbc([string]$Text) {
    return (($Text -split '\r?\n') | ForEach-Object { (($_.Trim() -replace '\s+\[precise(?:\([^\]]+\))?\]','') -replace '\s+',' ') }) -join "`n"
}

$profile = Get-Content -Raw -LiteralPath $profilePath | ConvertFrom-Json
if ($profile.detector -ne 'ff7-remake-tiled-light-angular-profile-branch-v1') { throw 'Unexpected angular-profile report' }
if ($profile.variantCount -ne 5) { throw 'Expected five accepted tiled-light variants' }

$variants = foreach ($profileVariant in @($profile.variants | Sort-Object hash)) {
    $assembly = [IO.Path]::GetFullPath((Join-Path $root $profileVariant.assemblyPath))
    if (-not (Test-Path -LiteralPath $assembly -PathType Leaf)) { throw "Assembly missing: $assembly" }
    $text = Normalize-Dxbc (Get-Content -Raw -LiteralPath $assembly)

    $position = [regex]::Match($text,'(?m)^add (?<vector>r\d+)\.xyz, -r\d+\.yzwy, cb4\[(?<index>r\d+\.[xyzw]) \+ 0\]\.xyzx$')
    if (-not $position.Success) { throw "Per-light position subtraction missing in $($profileVariant.hash)" }
    $vector = $position.Groups['vector'].Value
    $index = $position.Groups['index'].Value
    $tail = $text.Substring($position.Index,[Math]::Min(2300,$text.Length-$position.Index))

    $distance = [regex]::Match($tail,('(?m)^dp3 (?<distance>r\d+\.[xyzw]), ' + [regex]::Escape($vector) + '\.xyzx, ' + [regex]::Escape($vector) + '\.xyzx$'))
    if (-not $distance.Success) { throw "Squared distance from local-light vector missing in $($profileVariant.hash)" }
    $distanceRegister = $distance.Groups['distance'].Value
    $normalization = $tail -match ('(?m)^rsq r\d+\.[xyzw], ' + [regex]::Escape($distanceRegister) + '$') -and $tail -match ('(?m)^mul ' + [regex]::Escape($vector) + '\.xyz, r\d+\.[xyzw]{4}, ' + [regex]::Escape($vector) + '\.xyzx$')

    $mode = [regex]::Match($tail,('(?ms)^ne (?<flag>r\d+\.[xyzw]), l\(0(?:\.0+)?\), cb4\[' + [regex]::Escape($index) + ' \+ 512\]\.w\nif_nz \k<flag>\nmov \k<flag>, l\(1(?:\.0+)?\)\nelse\n(?<radial>.*?)\nendif'))
    if (-not $mode.Success) { throw "Distance-attenuation mode branch missing in $($profileVariant.hash)" }
    $radial = $mode.Groups['radial'].Value
    $radiusSquared = $radial -match ('(?m)^mul r\d+\.[xyzw], cb4\[' + [regex]::Escape($index) + ' \+ 0\]\.w, cb4\[' + [regex]::Escape($index) + ' \+ 0\]\.w$')
    $inverseSquareCutoff = $radial -match '(?m)^mad r\d+\.[xyzw], -r\d+\.[xyzw], r\d+\.[xyzw], l\(1(?:\.0+)?\)$' -and $radial -match '(?m)^rcp r\d+\.[xyzw], r\d+\.[xyzw]$'

    $spotFlag = $text -match ('(?m)^ne r\d+\.[xyzw], l\(0(?:\.0+)?\), cb3\[' + [regex]::Escape($index) + ' \+ 256\]\.w$')
    $spotCone = $tail -match ('(?m)^dp3 r\d+\.[xyzw], ' + [regex]::Escape($vector) + '\.xyzx, cb3\[' + [regex]::Escape($index) + ' \+ 0\]\.xyzx\nadd r\d+\.[xyzw], r\d+\.[xyzw], -cb3\[' + [regex]::Escape($index) + ' \+ 512\]\.x\nmul_sat r\d+\.[xyzw], r\d+\.[xyzw], cb3\[' + [regex]::Escape($index) + ' \+ 512\]\.y')

    $checks = [ordered]@{
        perLightPositionMinusWorldPosition = $position.Success
        distanceSquaredFromPerLightVector = $distance.Success
        normalizedPixelToLightVector = $normalization
        distanceAttenuationModeFlag = $mode.Success
        inverseRadiusSquaredInput = $radiusSquared
        inverseSquareRadiusCutoff = $inverseSquareCutoff
        perLightSpotFlag = $spotFlag
        spotDirectionAndAngles = $spotCone
        conditionalAngularProfile = @($profileVariant.checks.psobject.Properties.Value) -notcontains $false
        readModifyWritePriorLighting = $profileVariant.outputComposition -eq 'read-modify-write-existing-lighting'
    }
    if ($checks.Values -contains $false) { throw "Local-light dataflow invariant failed for $($profileVariant.hash)" }

    [ordered]@{
        hash = $profileVariant.hash
        lightIndexRegister = $index
        pixelToLightVectorRegister = $vector
        distanceSquaredRegister = $distanceRegister
        attenuationModeField = 'cb4[index+512].w'
        positionAndInverseRadiusField = 'cb4[index+0].xyzw'
        spotFlagField = 'cb3[index+256].w'
        directionField = 'cb3[index+0].xyz'
        spotAnglesField = 'cb3[index+512].xy'
        classification = 'shared-tiled-local-light-evaluator'
        checks = $checks
        assemblyPath = $profileVariant.assemblyPath
        assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assembly).Hash
    }
}

$report = [ordered]@{
    schemaVersion = 1
    detector = 'ff7-remake-tiled-local-light-dataflow-v1'
    scope = 'Read-only semantic proof that the five accepted tiled surface-light compute variants evaluate local point/spot/profiled lights; it corrects the prior directional inference from one attenuation bypass flag.'
    variantCount = $variants.Count
    variants = @($variants)
    familyInvariant = [ordered]@{
        geometry = 'every light iteration subtracts reconstructed world position from cb4[index+0].xyz and normalizes the resulting pixel-to-light vector'
        distance = 'every variant derives squared distance from that vector and uses cb4[index+0].w in a smooth inverse-radius cutoff with inverse-square attenuation'
        spot = 'every variant conditionally applies cb3[index+0].xyz direction and cb3[index+512].xy spot angles under cb3[index+256].w'
        profile = 'every variant conditionally samples the angular profile atlas and modulates the current local-light color'
        composition = 'every variant combines the current light with prior lighting before writing u0'
    }
    correctedInterpretation = [ordered]@{
        priorLabel = 'infinite/non-radial attenuation bypass'
        evidenceProblem = 'cb4[index+512].w only selects between unity and the local distance-attenuation expression; it does not bypass per-light position reconstruction, local light direction, spot logic, or profile logic'
        safeLabel = 'local-light distance-attenuation-mode flag'
        directionalOwnership = 'not evidenced by this family; retain a separate capture gate for the sun/directional evaluator'
        exactFieldIdentity = 'unresolved; do not assign a UE field name from DXBC structure alone'
    }
    implementationConsequences = @(
        'Treat all five hashes as material/tile specializations of one local-light evaluator family.',
        'Apply contact-shadow and falloff transforms inside the current-light term and preserve the spot, angular-profile, and prior-lighting chains.',
        'Do not use cb4[index+512].w as a directional-light classifier.',
        'Do not claim directional-light coverage until an outdoor directional capture identifies its actual draw or dispatch owner.'
    )
    nextEvidenceGates = @(
        'Runtime-capture cb4[index+512].w on representative point and spot lights to name its local attenuation mode safely.',
        'Capture an outdoor sun-lit scene and correlate the dominant directional contribution independently.',
        'Capture a visibly patterned profiled light and record cb3[index+768].x/.z to prove live angular-profile activation.'
    )
}

[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,(($report | ConvertTo-Json -Depth 14)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Variants=$variants.Count; LocalLightVariants=@($variants | Where-Object classification -eq 'shared-tiled-local-light-evaluator').Count; DirectionalOwned=$false; Output=$output }

