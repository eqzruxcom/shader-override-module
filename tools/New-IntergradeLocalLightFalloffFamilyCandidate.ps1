[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$FamilyScanPath,

    [Parameter(Mandatory)]
    [string]$BaseShaderDirectory,

    [Parameter(Mandatory)]
    [string]$OutputDirectory,

    [switch]$AllowStructuralExceptions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$artifacts = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts'))
$resolvedOutput = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if (-not $resolvedOutput.StartsWith($artifacts + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDirectory must remain beneath $artifacts"
}

$scanFile = (Resolve-Path -LiteralPath $FamilyScanPath -ErrorAction Stop).Path
$baseDirectory = (Resolve-Path -LiteralPath $BaseShaderDirectory -ErrorAction Stop).Path
$scan = Get-Content -Raw -LiteralPath $scanFile | ConvertFrom-Json
if ([string]$scan.detector -ne 'ff7-remake-dxbc-local-light-radial-semantic-v1') {
    throw 'FamilyScanPath is not a supported local-light radial scan.'
}
$exceptions = @($scan.structuralExceptions)
if ($exceptions.Count -gt 0 -and -not $AllowStructuralExceptions) {
    throw "The scan contains $($exceptions.Count) structural exceptions. Automatic transformation is refused."
}
$matches = @($scan.compatibleMatches)
if ($matches.Count -lt 1) { throw 'The scan contains no compatible local-light radial variants.' }

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Find-BaseShader([string]$Hash) {
    $candidates = @(
        (Join-Path $baseDirectory "$Hash-cs.txt"),
        (Join-Path $baseDirectory "$Hash-cs.asm")
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
    if ($candidates.Count -ne 1) {
        throw "Expected exactly one base assembly for $Hash beneath $baseDirectory; found $($candidates.Count)."
    }
    return $candidates[0]
}

$outputShaders = Join-Path $resolvedOutput 'ShaderFixes'
[void](New-Item -ItemType Directory -Force -Path $outputShaders)
$results = [Collections.Generic.List[object]]::new()

$attenuationPattern = [regex]::new(
    '(?m)^\s*mul (?<atten>r\d+\.[xyzw]), cb4\[(?<index>r\d+\.[xyzw]) \+ 0\]\.w, cb4\[\k<index> \+ 0\]\.w\r?\n' +
    '\s*mul \k<atten>, (?<distanceSq>r\d+\.[xyzw]), \k<atten>\r?\n' +
    '\s*mad \k<atten>, -\k<atten>, \k<atten>, l\(1\.000000\)'
)

foreach ($entry in $matches | Sort-Object hash) {
    $hash = ([string]$entry.hash).ToLowerInvariant()
    if ($hash -cnotmatch '^[0-9a-f]{16}$' -or [string]$entry.stage -ne 'cs') {
        throw "Invalid compatible entry in scan: $($entry.shader)"
    }
    if ([int]$entry.compatibleRadialBlockCount -ne 1) {
        throw "$hash does not have exactly one compatible radial block in the scan."
    }

    $source = Find-BaseShader $hash
    $destination = Join-Path $outputShaders "$hash-cs.txt"
    $text = [IO.File]::ReadAllText($source)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }

    if ($text -match '(?m)^\s*dcl_resource[^\r\n]*\bt120\b') {
        if ($text -notmatch '(?m)^\s*dcl_resource_texture1d \(float,float,float,float\) t120\s*$') {
            throw "$hash already binds t120 with an incompatible declaration."
        }
        $addedIniParamsBinding = $false
    } else {
        $resourceMatches = [regex]::Matches($text, '(?m)^\s*dcl_resource[^\r\n]*$')
        if ($resourceMatches.Count -lt 1) { throw "$hash has no resource declaration insertion point." }
        $lastResource = $resourceMatches[$resourceMatches.Count - 1]
        $insertAt = $lastResource.Index + $lastResource.Length
        $text = $text.Insert($insertAt, $newline + 'dcl_resource_texture1d (float,float,float,float) t120')
        $addedIniParamsBinding = $true
    }

    $tempMatches = [regex]::Matches($text, '(?m)^\s*dcl_temps (?<count>\d+)\s*$')
    if ($tempMatches.Count -ne 1) { throw "$hash expected one dcl_temps declaration; found $($tempMatches.Count)." }
    $tempMatch = $tempMatches[0]
    $oldTempCount = [int]$tempMatch.Groups['count'].Value
    $scratch = "r$oldTempCount"
    if ([regex]::IsMatch($text, ('(?<![A-Za-z0-9_])' + [regex]::Escape($scratch) + '(?:\.|\b)'))) {
        throw "$hash already references the proposed scratch register $scratch."
    }
    $text = $text.Remove($tempMatch.Index, $tempMatch.Length).Insert($tempMatch.Index, "dcl_temps $($oldTempCount + 1)")

    $radialMatches = $attenuationPattern.Matches($text)
    if ($radialMatches.Count -ne 1) {
        throw "$hash expected one native radial attenuation chain in the composed base; found $($radialMatches.Count)."
    }
    $radial = $radialMatches[0]
    $atten = $radial.Groups['atten'].Value
    $index = $radial.Groups['index'].Value
    $distanceSq = $radial.Groups['distanceSq'].Value

    $scanBlock = @($entry.radialBlocks | Where-Object compatible)[0]
    if ([string]$scanBlock.lightIndexRegister -ne $index -or
        [string]$scanBlock.attenuationRegister -ne $atten -or
        [string]$scanBlock.distanceSquaredRegister -ne $distanceSq) {
        throw "$hash composed-base register chain differs from the structurally verified capture."
    }

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
    $text = $text.Remove($radial.Index, $radial.Length).Insert($radial.Index, $replacement)
    $text = "// Remake Local Light Falloff Family Transform - generated only after structural verification.$newline" + $text
    [IO.File]::WriteAllText($destination, $text, [Text.UTF8Encoding]::new($false))

    $results.Add([pscustomobject][ordered]@{
        shader = "$hash-cs"
        source = $source
        sourceSha256 = Get-Sha256 $source
        output = $destination
        outputSha256 = Get-Sha256 $destination
        addedIniParamsBinding = $addedIniParamsBinding
        oldTempCount = $oldTempCount
        newTempCount = $oldTempCount + 1
        scratchRegister = $scratch
        lightIndexRegister = $index
        attenuationRegister = $atten
        distanceSquaredRegister = $distanceSq
    })
}

$fragment = [Collections.Generic.List[string]]::new()
$fragment.Add('; Generated local-light falloff family overrides. Merge with the single INI that owns:')
$fragment.Add('; $ue4fx_local_light_falloff_blend_v1 on Page Up and $ue4fx_master_injected_v1 on Page Down.')
$fragment.Add('; F10 remains shader reload only. This fragment does not declare keys or globals.')
foreach ($result in $results) {
    $hash = ([string]$result.shader).Substring(0,16)
    $fragment.Add('')
    $fragment.Add("[ShaderOverrideUE4FXLocalLightFalloff$hash]")
    $fragment.Add("hash = $hash")
    $fragment.Add('x30 = $ue4fx_local_light_falloff_blend_v1')
    $fragment.Add('x31 = $ue4fx_master_injected_v1')
}
$fragmentPath = Join-Path $resolvedOutput 'LocalLightFalloffFamily.overrides.ini.fragment'
[IO.File]::WriteAllLines($fragmentPath, $fragment, [Text.UTF8Encoding]::new($false))

$manifest = [ordered]@{
    schemaVersion = 1
    generator = 'New-IntergradeLocalLightFalloffFamilyCandidate.ps1'
    createdUtc = [DateTime]::UtcNow.ToString('o')
    installed = $false
    runtimeEligible = $false
    reasonNotRuntimeEligible = 'Requires assembly/interface validation and merge into the single existing Page Up/Page Down control owner before installation.'
    familyScan = [ordered]@{
        path = $scanFile
        sha256 = Get-Sha256 $scanFile
        detector = [string]$scan.detector
        compatibleMatchCount = $matches.Count
        structuralExceptionCount = $exceptions.Count
    }
    transformation = [ordered]@{
        nativeEquation = '(1 - x^4)^2'
        mediumEquation = '(1 - lerp(x^4,x^8,0.5))^2'
        strongEquation = '(1 - x^8)^2'
        preservesZeroAtAuthoredRadius = $true
        controls = [ordered]@{ blend = 't120[30].x'; master = 't120[31].x' }
        doesNotChange = @('light-list culling','authored light volume','shadow maps','contact shadows','spot or IES attenuation','BRDF','AO','GI')
    }
    iniFragment = [ordered]@{ path = $fragmentPath; sha256 = Get-Sha256 $fragmentPath }
    shaders = @($results)
}
$manifestPath = Join-Path $resolvedOutput 'manifest.json'
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

Write-Host "PASS: generated $($results.Count) structurally verified local-light falloff replacements."
Write-Host "Candidate: $resolvedOutput"
Write-Host 'Nothing was installed.'

