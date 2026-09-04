param(
    [string]$BaseDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\offline-local-light-falloff-pageup\20260901-v1\base-live'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\offline-local-light-falloff-pageup\20260901-v1\candidate')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$shaderNames = @(
    '08bb8764f1840179-cs.txt',
    '0e97888f9a8767da-cs.txt',
    '5a9fbefe0ab6f815-cs.txt',
    '62b33a2d1e505241-cs.txt',
    'c30cdc8365df9840-cs.txt'
)

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Get-Sha256([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$baseShaderDirectory = Join-Path $BaseDirectory 'ShaderFixes'
$baseIni = Join-Path $BaseDirectory 'Mods\ContactShadows.ini'
$outputShaderDirectory = Join-Path $OutputDirectory 'ShaderFixes'
$outputModDirectory = Join-Path $OutputDirectory 'Mods'

Require (Test-Path -LiteralPath $baseIni -PathType Leaf) "Missing base INI: $baseIni"
New-Item -ItemType Directory -Path $outputShaderDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $outputModDirectory -Force | Out-Null

$results = @()
$attenuationPattern = [regex]::new(
    '(?m)^mul (?<atten>r\d+\.[xyzw]), cb4\[(?<index>r\d+\.[xyzw]) \+ 0\]\.w, cb4\[\k<index> \+ 0\]\.w\r?\n' +
    'mul \k<atten>, (?<distanceSq>r\d+\.[xyzw]), \k<atten>\r?\n' +
    'mad \k<atten>, -\k<atten>, \k<atten>, l\(1\.000000\)'
)

foreach ($shaderName in $shaderNames) {
    $source = Join-Path $baseShaderDirectory $shaderName
    $destination = Join-Path $outputShaderDirectory $shaderName
    Require (Test-Path -LiteralPath $source -PathType Leaf) "Missing base shader: $source"

    $text = [IO.File]::ReadAllText($source)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    Require ($text -match '(?m)^dcl_resource_texture1d \(float,float,float,float\) t120$') "$shaderName does not declare t120."

    $tempMatch = [regex]::Match($text, '(?m)^dcl_temps (?<count>\d+)$')
    Require $tempMatch.Success "$shaderName has no dcl_temps declaration."
    Require ([regex]::Matches($text, '(?m)^dcl_temps \d+$').Count -eq 1) "$shaderName has multiple dcl_temps declarations."
    $oldTempCount = [int]$tempMatch.Groups['count'].Value
    $scratch = "r$oldTempCount"
    $text = $text.Remove($tempMatch.Index, $tempMatch.Length).Insert($tempMatch.Index, "dcl_temps $($oldTempCount + 1)")

    $matches = $attenuationPattern.Matches($text)
    Require ($matches.Count -eq 1) "$shaderName expected one local-light radial attenuation block, found $($matches.Count)."
    $match = $matches[0]
    $atten = $match.Groups['atten'].Value
    $index = $match.Groups['index'].Value
    $distanceSq = $match.Groups['distanceSq'].Value

    # Native is (1 - x^4)^2, where x is distance/radius. Page Up blends the
    # cutoff polynomial toward x^8 while keeping both endpoints fixed. This
    # brightens the outer part of the authored light volume without extending
    # past its culling radius or touching shadow/contact-shadow attenuation.
    $replacement = @(
        "mul $atten, cb4[$index + 0].w, cb4[$index + 0].w",
        "mul $atten, $distanceSq, $atten",
        "mul $scratch.x, $atten, $atten",
        "mul $scratch.y, $scratch.x, $scratch.x",
        "add $scratch.y, -$scratch.x, $scratch.y",
        "ld_indexable(texture1d)(float,float,float,float) $scratch.z, l(30, 0, 0, 0), t120.xyzw",
        "ld_indexable(texture1d)(float,float,float,float) $scratch.w, l(31, 0, 0, 0), t120.xyzw",
        "mul $scratch.z, $scratch.z, $scratch.w",
        "mad $scratch.x, $scratch.z, $scratch.y, $scratch.x",
        "add $atten, -$scratch.x, l(1.000000)"
    ) -join $newline

    $text = $text.Remove($match.Index, $match.Length).Insert($match.Index, $replacement)
    $text = "// Remake Local Light Falloff Test - offline only; Page Up cycles native/mid/strong.$newline" + $text
    [IO.File]::WriteAllText($destination, $text, [Text.UTF8Encoding]::new($false))

    $results += [ordered]@{
        shader = $shaderName
        baseSha256 = Get-Sha256 $source
        candidateSha256 = Get-Sha256 $destination
        oldTempCount = $oldTempCount
        newTempCount = $oldTempCount + 1
        scratchRegister = $scratch
        lightIndexRegister = $index
        attenuationRegister = $atten
        distanceSquaredRegister = $distanceSq
        radialBlockMatches = $matches.Count
    }
}

$iniText = [IO.File]::ReadAllText($baseIni)
$newline = if ($iniText.Contains("`r`n")) { "`r`n" } else { "`n" }
Require ($iniText -match '(?m)^global \$ue4fx_master_injected_v1 = 1$') 'The base INI is not the accepted Page Down master version.'
Require (-not ($iniText -match '\$ue4fx_local_light_falloff_blend_v1')) 'The base INI already contains the falloff experiment.'

$iniText = $iniText.Replace(
    'global $ue4fx_contact_edge_cutoff_v2 = 0',
    'global $ue4fx_contact_edge_cutoff_v2 = 0' + $newline +
    'global $ue4fx_local_light_falloff_blend_v1 = 0'
)

$keyBlock = @(
    '',
    '; Local-light distance falloff only. It does not alter shadows, contact shadows,',
    '; light color, authored culling radius, exposure, bloom, fog, AO, or GI.',
    '; Page Up: native x^4 cutoff, 50% blend toward x^8, full x^8 cutoff.',
    '[KeyUE4FXLocalLightFalloffPageUp]',
    'key = no_modifiers VK_PRIOR',
    'type = cycle',
    'smart = true',
    '$ue4fx_local_light_falloff_blend_v1 = 0, 0.5, 1',
    ''
) -join $newline
$iniText = $iniText.Replace('[ShaderOverrideUE4FXContactc30cdc8365df9840]', $keyBlock + $newline + '[ShaderOverrideUE4FXContactc30cdc8365df9840]')

foreach ($shaderName in $shaderNames) {
    $hash = $shaderName.Substring(0, 16)
    $sectionPattern = '(?ms)(\[ShaderOverrideUE4FXContact' + [regex]::Escape($hash) + '\].*?^y29 = \$ue4fx_contact_edge_cutoff_v2$)'
    $sectionMatches = [regex]::Matches($iniText, $sectionPattern)
    Require ($sectionMatches.Count -eq 1) "Expected one INI override for $hash, found $($sectionMatches.Count)."
    $iniText = [regex]::Replace(
        $iniText,
        $sectionPattern,
        '$1' + $newline + 'x30 = $ue4fx_local_light_falloff_blend_v1',
        1
    )
}

$outputIni = Join-Path $outputModDirectory 'ContactShadows.ini'
[IO.File]::WriteAllText($outputIni, $iniText, [Text.UTF8Encoding]::new($false))

$manifest = [ordered]@{
    schemaVersion = 1
    name = 'FF7 Remake local-light falloff Page Up prototype'
    createdUtc = [DateTime]::UtcNow.ToString('o')
    runtimeEligible = $false
    installed = $false
    liveFilesChanged = $false
    baseDirectory = (Resolve-Path -LiteralPath $BaseDirectory).Path
    outputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
    controls = [ordered]@{
        pageDown = 'master injected-code toggle; OFF forces native falloff because the shader multiplies the blend by t120[31].x'
        pageUp = @(
            [ordered]@{ stage = 0; blend = 0.0; radialPolynomial = 'x^4'; label = 'native' },
            [ordered]@{ stage = 1; blend = 0.5; radialPolynomial = 'lerp(x^4,x^8,0.5)'; label = 'medium' },
            [ordered]@{ stage = 2; blend = 1.0; radialPolynomial = 'x^8'; label = 'strong' }
        )
        f10 = 'unchanged; shader reload only'
    }
    scope = [ordered]@{
        changes = 'radial distance attenuation inside the five already-proven tiled local-light compute variants'
        preserves = @('native zero at authored light radius','light culling volume','shadow-map attenuation','contact-shadow attenuation','light color','AO','GI','fog','bloom','exposure')
        limitation = 'cannot illuminate pixels outside the authored light volume/list; a larger true radius requires culling/bounds changes or a separate GI pass'
    }
    baseIniSha256 = Get-Sha256 $baseIni
    candidateIniSha256 = Get-Sha256 $outputIni
    shaders = $results
}

$manifestPath = Join-Path $OutputDirectory 'manifest.json'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))

Write-Host "PASS: built offline local-light falloff prototype for $($shaderNames.Count) shaders."
Write-Host "Candidate: $OutputDirectory"
Write-Host 'Nothing was installed into the game.'
