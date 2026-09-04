[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IniPath,
    [string]$ShaderDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\assembly'),
    [Parameter(Mandatory)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts'))
$resolvedIni = [IO.Path]::GetFullPath($IniPath)
$resolvedShaders = [IO.Path]::GetFullPath($ShaderDirectory)
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
if (-not $resolvedOutput.StartsWith($artifactRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must remain beneath $artifactRoot"
}
foreach ($requiredPath in @($resolvedIni, $resolvedShaders)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required path is missing: $requiredPath"
    }
}

$families = [ordered]@{
    '[ShaderRegexUE4FXRemakeTiledSurfaceLightContactT4.Pattern]' = @(
        '5a9fbefe0ab6f815-cs.asm',
        '62b33a2d1e505241-cs.asm'
    )
    '[ShaderRegexUE4FXRemakeTiledSurfaceLightContactT5.Pattern]' = @(
        '08bb8764f1840179-cs.asm',
        '0e97888f9a8767da-cs.asm',
        'c30cdc8365df9840-cs.asm'
    )
}
$ini = @(Get-Content -LiteralPath $resolvedIni)
$compiled = [ordered]@{}
foreach ($section in $families.Keys) {
    $start = [array]::IndexOf($ini, $section)
    if ($start -lt 0) {
        throw "Pattern section is missing: $section"
    }
    $patternLines = [Collections.Generic.List[string]]::new()
    for ($index = $start + 1; $index -lt $ini.Count; $index++) {
        $line = $ini[$index].Trim()
        if ($line -match '^\[[^\]]+\]$') { break }
        if ($line -and -not $line.StartsWith(';')) { $patternLines.Add($line) }
    }
    if (-not $patternLines.Count) {
        throw "Pattern is empty: $section"
    }
    $pcre = $patternLines -join ''
    $dotnet = [regex]::Replace($pcre, '\(\?P<([A-Za-z_][A-Za-z0-9_]*)>', '(?<$1>')
    $dotnet = [regex]::Replace($dotnet, '\(\?P=([A-Za-z_][A-Za-z0-9_]*)\)', '\k<$1>')
    $compiled[$section] = [regex]::new(
        $dotnet,
        [Text.RegularExpressions.RegexOptions]::IgnoreCase,
        [TimeSpan]::FromSeconds(2))
}

$shaderFiles = @(Get-ChildItem -LiteralPath $resolvedShaders -Filter '*.asm' -File | Sort-Object Name)
$matches = [Collections.Generic.List[object]]::new()
$timeouts = [Collections.Generic.List[object]]::new()
$failures = [Collections.Generic.List[string]]::new()
foreach ($file in $shaderFiles) {
    $text = ([IO.File]::ReadAllText($file.FullName) -replace "`r`n", "`n")
    $matchedFamilies = [Collections.Generic.List[string]]::new()
    foreach ($entry in $compiled.GetEnumerator()) {
        try {
            if ($entry.Value.IsMatch($text)) {
                $matchedFamilies.Add($entry.Key)
            }
        }
        catch [Text.RegularExpressions.RegexMatchTimeoutException] {
            $timeouts.Add([ordered]@{ file=$file.Name; family=$entry.Key })
        }
    }
    if ($matchedFamilies.Count) {
        $matches.Add([ordered]@{ file=$file.Name; families=@($matchedFamilies) })
    }
    if ($matchedFamilies.Count -gt 1) {
        $failures.Add("shader matched multiple layouts: $($file.Name)")
    }
}

$expectedFiles = @($families.Values | ForEach-Object { $_ } | Sort-Object)
$actualFiles = @($matches | ForEach-Object file | Sort-Object)
$setDifference = @(Compare-Object $expectedFiles $actualFiles)
if ($setDifference.Count) {
    $failures.Add('union of generated patterns did not match the exact expected five-shader set')
}
foreach ($entry in $families.GetEnumerator()) {
    $actualForFamily = @($matches | Where-Object { $_.families -contains $entry.Key } | ForEach-Object file | Sort-Object)
    $expectedForFamily = @($entry.Value | Sort-Object)
    if (@(Compare-Object $expectedForFamily $actualForFamily).Count) {
        $failures.Add("layout membership mismatch: $($entry.Key)")
    }
}
if ($shaderFiles.Count -ne 184) {
    $failures.Add("authoritative regional corpus changed from 184 shaders to $($shaderFiles.Count)")
}
if ($timeouts.Count) {
    $failures.Add("regex timed out $($timeouts.Count) time(s)")
}

$report = [ordered]@{
    schemaVersion = 1
    kind = 'remake-generated-contact-family-full-corpus-regex'
    mode = 'offline-fail-closed-two-layout'
    shaderDirectory = $resolvedShaders
    shaderCount = $shaderFiles.Count
    patternIni = $resolvedIni
    patternIniSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedIni).Hash
    expectedByFamily = $families
    matches = @($matches)
    matchCount = $matches.Count
    timeouts = @($timeouts)
    exactExpectedSet = $setDifference.Count -eq 0
    exactFamilyMembership = @($failures | Where-Object { $_ -like 'layout membership mismatch:*' }).Count -eq 0
    passed = $failures.Count -eq 0
    failures = @($failures)
    runtimePolicy = 'Automatic only after exact five-of-184 corpus match plus runtime assembly/equivalence validation.'
}
[void](New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput -Parent))
[IO.File]::WriteAllText(
    $resolvedOutput,
    ($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))

if ($failures.Count) {
    throw "Generated contact-family corpus test failed: $($failures -join '; ')"
}
Write-Host "PASS: generated families matched exactly five of $($shaderFiles.Count) shaders with the expected 2+3 layout split."
Write-Host "REPORT=$resolvedOutput"
