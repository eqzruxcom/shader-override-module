[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IniPath,
    [Parameter(Mandatory)][string]$GenerationReportPath,
    [string]$ShaderDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\assembly'),
    [Parameter(Mandatory)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts'))
$resolvedIni = [IO.Path]::GetFullPath($IniPath)
$resolvedGeneration = [IO.Path]::GetFullPath($GenerationReportPath)
$resolvedShaders = [IO.Path]::GetFullPath($ShaderDirectory)
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
if (-not $resolvedOutput.StartsWith($artifactRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must remain beneath $artifactRoot"
}
foreach ($requiredPath in @($resolvedIni, $resolvedGeneration, $resolvedShaders)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) { throw "Required path is missing: $requiredPath" }
}

$generation = Get-Content -Raw -LiteralPath $resolvedGeneration | ConvertFrom-Json
$iniSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedIni).Hash
if ($generation.outputIniSha256 -ne $iniSha -or @($generation.automaticFamilies).Count -ne 3) {
    throw 'Generation report does not describe the selected three-family INI.'
}

$families = [ordered]@{}
foreach ($family in $generation.automaticFamilies) {
    $families[$family.name] = @($family.members | ForEach-Object { $_ + '-cs.asm' })
}
$ini = @(Get-Content -LiteralPath $resolvedIni)
$compiled = [ordered]@{}
foreach ($name in $families.Keys) {
    $section = '[' + $name + '.Pattern]'
    $start = [array]::IndexOf($ini, $section)
    if ($start -lt 0) { throw "Pattern section is missing: $section" }
    $patternLines = [Collections.Generic.List[string]]::new()
    for ($index = $start + 1; $index -lt $ini.Count; $index++) {
        $line = $ini[$index].Trim()
        if ($line -match '^\[[^\]]+\]$') { break }
        if ($line -and -not $line.StartsWith(';')) { $patternLines.Add($line) }
    }
    if (-not $patternLines.Count) { throw "Pattern is empty: $section" }
    $pcre = $patternLines -join ''
    $dotnet = [regex]::Replace($pcre, '\(\?P<([A-Za-z_][A-Za-z0-9_]*)>', '(?<$1>')
    $dotnet = [regex]::Replace($dotnet, '\(\?P=([A-Za-z_][A-Za-z0-9_]*)\)', '\k<$1>')
    $compiled[$name] = [regex]::new($dotnet, [Text.RegularExpressions.RegexOptions]::IgnoreCase, [TimeSpan]::FromSeconds(2))
}

$shaderFiles = @(Get-ChildItem -LiteralPath $resolvedShaders -Filter '*.asm' -File | Sort-Object Name)
$matches = [Collections.Generic.List[object]]::new()
$timeouts = [Collections.Generic.List[object]]::new()
$failures = [Collections.Generic.List[string]]::new()
foreach ($file in $shaderFiles) {
    $text = ([IO.File]::ReadAllText($file.FullName) -replace "`r`n", "`n")
    $matched = [Collections.Generic.List[string]]::new()
    foreach ($entry in $compiled.GetEnumerator()) {
        try {
            if ($entry.Value.IsMatch($text)) { $matched.Add($entry.Key) }
        }
        catch [Text.RegularExpressions.RegexMatchTimeoutException] {
            $timeouts.Add([ordered]@{ file=$file.Name; family=$entry.Key })
        }
    }
    if ($matched.Count) { $matches.Add([ordered]@{ file=$file.Name; families=@($matched) }) }
    if ($matched.Count -gt 1) { $failures.Add("shader matched multiple automatic families: $($file.Name)") }
}

$expectedFiles = @($families.Values | ForEach-Object { $_ } | Sort-Object)
$actualFiles = @($matches | ForEach-Object file | Sort-Object)
if (@(Compare-Object $expectedFiles $actualFiles).Count) {
    $failures.Add('union of automatic families did not match the exact expected five-shader set')
}
foreach ($entry in $families.GetEnumerator()) {
    $actual = @($matches | Where-Object { $_.families -contains $entry.Key } | ForEach-Object file | Sort-Object)
    if (@(Compare-Object @($entry.Value | Sort-Object) $actual).Count) {
        $failures.Add("family membership mismatch: $($entry.Key)")
    }
}
if ($shaderFiles.Count -ne 184) { $failures.Add("regional corpus changed from 184 shaders to $($shaderFiles.Count)") }
if ($timeouts.Count) { $failures.Add("regex timed out $($timeouts.Count) time(s)") }

$report = [ordered]@{
    schemaVersion = 2
    kind = 'remake-accepted-contact-family-full-corpus-regex'
    mode = 'offline-fail-closed-three-family'
    shaderDirectory = $resolvedShaders
    shaderCount = $shaderFiles.Count
    patternIni = $resolvedIni
    patternIniSha256 = $iniSha
    generationReport = $resolvedGeneration
    expectedByFamily = $families
    matches = @($matches)
    matchCount = $matches.Count
    timeouts = @($timeouts)
    exactExpectedSet = @(Compare-Object $expectedFiles $actualFiles).Count -eq 0
    exactFamilyMembership = @($failures | Where-Object { $_ -like 'family membership mismatch:*' }).Count -eq 0
    passed = $failures.Count -eq 0
    failures = @($failures)
}
[void](New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput -Parent))
[IO.File]::WriteAllText($resolvedOutput, ($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
if ($failures.Count) { throw "Accepted contact-family corpus test failed: $($failures -join '; ')" }
Write-Host "PASS: accepted families matched exactly five of $($shaderFiles.Count) shaders with the expected 3+1+1 split."
Write-Host "REPORT=$resolvedOutput"
