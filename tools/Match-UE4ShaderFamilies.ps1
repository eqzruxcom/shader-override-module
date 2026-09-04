[CmdletBinding()]
param(
    [string]$ShaderDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\ShaderFixes',
    [string]$RegexIni = (Join-Path (Split-Path -Parent $PSScriptRoot) 'reference\HelixMod-FF7R\FixFiles\ShaderFixes\ShaderRegEx_UE4_UNIVERSAL2_C44.ini'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\intergrade-ue4-family-matches.json'),
    [string]$FamilyFilter,
    [double]$MatchTimeoutSeconds = 2.0,
    [switch]$CompileOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RegexIni -PathType Leaf)) {
    throw "Universal UE4 ShaderRegex file not found: $RegexIni"
}

function Get-ShaderFamily {
    param([Parameter(Mandatory)][string]$Name)

    switch -Regex ($Name) {
        'SSR|ScreenReflect|WaterSSR'       { return 'screen-space-reflections' }
        'Reflect|Mirror|Specular'          { return 'reflections-and-specular' }
        'Volumetric|VolFog|Fog'            { return 'volumetrics-and-fog' }
        'AO|Ambient'                       { return 'ambient-occlusion' }
        'Light|Sun|Moon'                   { return 'lighting' }
        'Velocity|Motion|TAA|AAFix'        { return 'temporal-and-motion' }
        'Object|Decal|Glass|Clipping'      { return 'objects-and-materials' }
        'Halo|Lens|Shaft|Horizon|Mono|Distortion|Dissortion' { return 'screen-effects' }
        default                            { return 'other' }
    }
}

function Convert-Pcre2PatternToDotNet {
    param([Parameter(Mandatory)][string]$Pattern)

    $translated = [regex]::Replace($Pattern, '\(\?P<(?<name>[A-Za-z_][A-Za-z0-9_]*)>', '(?<$1>')
    $translated = [regex]::Replace($translated, '\(\?P=(?<name>[A-Za-z_][A-Za-z0-9_]*)\)', '\k<$1>')
    return $translated
}

$sections = [ordered]@{}
$currentSection = $null
foreach ($line in Get-Content -LiteralPath $RegexIni) {
    if ($line -match '^\[(?<name>[^\]]+)\]\s*$') {
        $currentSection = $Matches.name
        if (-not $sections.Contains($currentSection)) {
            $sections[$currentSection] = [Collections.Generic.List[string]]::new()
        }
        continue
    }

    if (-not $currentSection) {
        continue
    }

    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith(';') -or $trimmed.StartsWith('#')) {
        continue
    }

    $sections[$currentSection].Add($trimmed)
}

$baseMetadata = @{}
foreach ($sectionName in $sections.Keys) {
    if ($sectionName -notmatch '^(ShaderRegex_[^\.]+)$') {
        continue
    }

    $shaderModels = @()
    foreach ($line in $sections[$sectionName]) {
        if ($line -match '^shader_model\s*=\s*(?<models>.+)$') {
            $shaderModels = @($Matches.models -split '\s+' | Where-Object { $_ })
        }
    }

    $baseMetadata[$sectionName] = [ordered]@{
        shaderModels = $shaderModels
        family = Get-ShaderFamily -Name $sectionName
    }
}

$compiledPatterns = [Collections.Generic.List[object]]::new()
$compileFailures = [Collections.Generic.List[object]]::new()
$timeout = [TimeSpan]::FromSeconds($MatchTimeoutSeconds)

foreach ($sectionName in $sections.Keys) {
    if ($sectionName -notmatch '^(?<base>ShaderRegex_[^\.]+)\.(?<pattern>Pattern[^\.]*)$') {
        continue
    }

    $baseName = $Matches.base
    $patternName = $Matches.pattern
    if (-not $baseMetadata.ContainsKey($baseName)) {
        continue
    }

    $family = $baseMetadata[$baseName].family
    if ($FamilyFilter -and $family -notmatch $FamilyFilter -and $baseName -notmatch $FamilyFilter) {
        continue
    }

    $pcre2Pattern = [string]::Concat([string[]]$sections[$sectionName])
    $dotNetPattern = Convert-Pcre2PatternToDotNet -Pattern $pcre2Pattern

    try {
        $regex = [regex]::new(
            $dotNetPattern,
            [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::Multiline,
            $timeout
        )
        $compiledPatterns.Add([pscustomobject]@{
            section = $baseName
            pattern = $patternName
            family = $family
            shaderModels = @($baseMetadata[$baseName].shaderModels)
            regex = $regex
        })
    }
    catch {
        $compileFailures.Add([pscustomobject]@{
            section = $baseName
            pattern = $patternName
            family = $family
            error = $_.Exception.Message
        })
    }
}

$shaderMatches = [Collections.Generic.List[object]]::new()
$matchTimeouts = [Collections.Generic.List[object]]::new()
$shaderCount = 0

if (-not $CompileOnly) {
    if (-not (Test-Path -LiteralPath $ShaderDirectory -PathType Container)) {
        throw "Exported shader directory not found: $ShaderDirectory"
    }

    $shaders = @(Get-ChildItem -LiteralPath $ShaderDirectory -Recurse -File -Filter '*.txt' |
        Where-Object { $_.Name -match '^(?<hash>[0-9a-fA-F]{16})-(?<stage>vs|ps|cs|hs|ds|gs)(?:_replace)?\.txt$' })
    $shaderCount = $shaders.Count

    foreach ($shader in $shaders) {
        if ($shader.Name -notmatch '^(?<hash>[0-9a-fA-F]{16})-(?<stage>vs|ps|cs|hs|ds|gs)(?:_replace)?\.txt$') {
            continue
        }

        $hash = $Matches.hash.ToLowerInvariant()
        $stage = $Matches.stage.ToLowerInvariant()
        $shaderModel = "${stage}_5_0"
        $assembly = (Get-Content -Raw -LiteralPath $shader.FullName) -replace "`r`n", "`n"

        foreach ($candidate in $compiledPatterns) {
            if ($candidate.shaderModels.Count -and $shaderModel -notin $candidate.shaderModels) {
                continue
            }

            try {
                if ($candidate.regex.IsMatch($assembly)) {
                    $shaderMatches.Add([pscustomobject]@{
                        hash = $hash
                        stage = $stage
                        file = $shader.FullName
                        family = $candidate.family
                        section = $candidate.section
                        pattern = $candidate.pattern
                    })
                }
            }
            catch [Text.RegularExpressions.RegexMatchTimeoutException] {
                $matchTimeouts.Add([pscustomobject]@{
                    hash = $hash
                    stage = $stage
                    section = $candidate.section
                    pattern = $candidate.pattern
                })
            }
        }
    }
}

$report = [ordered]@{
    schemaVersion = 2
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    regexSource = (Resolve-Path -LiteralPath $RegexIni).Path
    regexSourceSha256 = (Get-FileHash -LiteralPath $RegexIni -Algorithm SHA256).Hash
    familyFilter = $FamilyFilter
    compileOnly = [bool]$CompileOnly
    patternSections = [ordered]@{
        compiled = $compiledPatterns.Count
        failed = $compileFailures.Count
        failures = @($compileFailures)
    }
    shaders = [ordered]@{
        directory = $ShaderDirectory
        scanned = $shaderCount
    }
    matchTimeouts = @($matchTimeouts)
    matches = @($shaderMatches | Sort-Object family, section, hash)
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Output "Compiled ShaderRegex patterns: $($compiledPatterns.Count)"
Write-Output "Pattern compile failures: $($compileFailures.Count)"
Write-Output "Exported shaders scanned: $shaderCount"
Write-Output "Matches: $($shaderMatches.Count)"
Write-Output "Report: $OutputPath"
