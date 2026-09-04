[CmdletBinding()]
param(
    [string]$ReferenceRoot = (Join-Path $PSScriptRoot '..\reference\HelixMod-FF7R\FixFiles'),
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\artifacts\helix-reference-inventory.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedReferenceRoot = (Resolve-Path -LiteralPath $ReferenceRoot).Path
$regexPath = Join-Path $resolvedReferenceRoot 'ShaderFixes\ShaderRegEx_UE4_UNIVERSAL2_C44.ini'

if (-not (Test-Path -LiteralPath $regexPath -PathType Leaf)) {
    throw "Universal UE4 regex file not found: $regexPath"
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

$regexSections = foreach ($line in Get-Content -LiteralPath $regexPath) {
    if ($line -match '^\[(ShaderRegex_[^\.\]]+)\]\s*$') {
        $name = $Matches[1]
        [pscustomobject]@{
            name = $name
            family = Get-ShaderFamily -Name $name
        }
    }
}

$regexSections = @($regexSections | Sort-Object name -Unique)
$families = foreach ($group in ($regexSections | Group-Object family | Sort-Object Name)) {
    [pscustomobject]@{
        family = $group.Name
        count = $group.Count
        sections = @($group.Group.name | Sort-Object)
    }
}

$shaderFiles = foreach ($file in Get-ChildItem -LiteralPath $resolvedReferenceRoot -Recurse -File) {
    if ($file.Name -match '^(?<hash>[0-9A-Fa-f]{16})-(?<stage>vs|ps|cs)(?<replacement>_replace)?\.(?<extension>txt|bin)$') {
        [pscustomobject]@{
            hash = $Matches.hash.ToLowerInvariant()
            stage = $Matches.stage
            kind = if ($Matches.ContainsKey('replacement')) { 'replacement' } else { 'capture' }
            extension = $Matches.extension
            relativePath = $file.FullName.Substring($resolvedReferenceRoot.Length + 1)
        }
    }
}

$iniSections = foreach ($ini in Get-ChildItem -LiteralPath $resolvedReferenceRoot -Filter '*.ini' -File) {
    foreach ($line in Get-Content -LiteralPath $ini.FullName) {
        if ($line -match '^\[(ShaderOverride|TextureOverride|Resource|CustomShader|CommandList)([^\]]*)\]\s*$') {
            [pscustomobject]@{
                file = $ini.Name
                type = $Matches[1]
                name = $Matches[2]
            }
        }
    }
}

$stageCounts = foreach ($group in ($shaderFiles | Group-Object stage, kind | Sort-Object Name)) {
    [pscustomobject]@{
        stage = $group.Group[0].stage
        kind = $group.Group[0].kind
        count = $group.Count
    }
}

$report = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    source = [ordered]@{
        referenceRoot = $resolvedReferenceRoot
        universalRegexFile = $regexPath.Substring($resolvedReferenceRoot.Length + 1)
        universalRegexSha256 = (Get-FileHash -LiteralPath $regexPath -Algorithm SHA256).Hash
    }
    regex = [ordered]@{
        baseSectionCount = $regexSections.Count
        families = @($families)
    }
    shaders = [ordered]@{
        fileCount = @($shaderFiles).Count
        counts = @($stageCounts)
        files = @($shaderFiles | Sort-Object stage, hash, kind)
    }
    configuration = [ordered]@{
        sectionCount = @($iniSections).Count
        sections = @($iniSections | Sort-Object file, type, name)
    }
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Output "Wrote $OutputPath"
Write-Output "UE4 regex base sections: $($regexSections.Count)"
Write-Output "Captured/replacement shader files: $(@($shaderFiles).Count)"
Write-Output "Configuration sections: $(@($iniSections).Count)"
