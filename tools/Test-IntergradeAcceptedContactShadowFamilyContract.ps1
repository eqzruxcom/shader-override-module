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

function Get-SectionLines([string[]]$Lines, [string]$Name) {
    $marker = '[' + $Name + ']'
    $start = [array]::IndexOf($Lines, $marker)
    if ($start -lt 0) { throw "INI section is missing: $marker" }
    $result = [Collections.Generic.List[string]]::new()
    for ($index = $start + 1; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index].Trim() -match '^\[[^\]]+\]$') { break }
        $result.Add($Lines[$index])
    }
    return @($result)
}

function Get-Setting([string[]]$Lines, [string]$Key) {
    foreach ($line in $Lines) {
        if ($line -match ('^\s*' + [regex]::Escape($Key) + '\s*=\s*(.*?)\s*$')) { return $Matches[1] }
    }
    throw "Required setting is missing: $Key"
}

function Split-Words([string]$Value) {
    return @(($Value -replace '[,;]', ' ') -split '\s+' | Where-Object { $_ })
}

function Test-DeclarationBinding([string]$Assembly, [string]$Requested) {
    $binding = $Requested.ToLowerInvariant()
    if ($binding -match '^b\d') { $binding = 'c' + $binding }
    $token = '(?<![A-Za-z0-9_])' + [regex]::Escape($binding) + '(?![A-Za-z0-9_])'
    foreach ($line in ($Assembly -split "`n")) {
        $lowered = $line.TrimStart(" `t`r").ToLowerInvariant()
        if ($lowered.StartsWith('dcl_') -and $lowered -match $token) { return $true }
    }
    return $false
}

function Get-InstructionCount([string]$Assembly) {
    $count = 0
    foreach ($line in ($Assembly -split "`n")) {
        $lowered = $line.TrimStart(" `t`r").ToLowerInvariant()
        if (-not $lowered -or $lowered.StartsWith('//') -or $lowered.StartsWith('dcl_') -or
            $lowered.StartsWith('globalflags ') -or $lowered -match '^.._[45]_0(?:\s|$)') { continue }
        $count++
    }
    return $count
}

$generation = Get-Content -Raw -LiteralPath $resolvedGeneration | ConvertFrom-Json
$iniSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedIni).Hash
if ($generation.outputIniSha256 -ne $iniSha -or @($generation.automaticFamilies).Count -ne 3) {
    throw 'Generation report does not describe the selected three-family INI.'
}

$ini = @(Get-Content -LiteralPath $resolvedIni)
$families = [ordered]@{}
foreach ($family in $generation.automaticFamilies) {
    $name = [string]$family.name
    $rootLines = Get-SectionLines -Lines $ini -Name $name
    $patternLines = @(Get-SectionLines -Lines $ini -Name ($name + '.Pattern') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith(';') })
    if (-not $patternLines.Count) { throw "Pattern is empty: $name" }
    $pcre = $patternLines -join ''
    $dotnet = [regex]::Replace($pcre, '\(\?P<([A-Za-z_][A-Za-z0-9_]*)>', '(?<$1>')
    $dotnet = [regex]::Replace($dotnet, '\(\?P=([A-Za-z_][A-Za-z0-9_]*)\)', '\k<$1>')
    $families[$name] = [ordered]@{
        expected = @($family.members | ForEach-Object { $_ + '-cs.asm' })
        regex = [regex]::new($dotnet, [Text.RegularExpressions.RegexOptions]::IgnoreCase, [TimeSpan]::FromSeconds(2))
        required = @(Split-Words (Get-Setting -Lines $rootLines -Key 'required_bindings'))
        forbidden = @(Split-Words (Get-Setting -Lines $rootLines -Key 'forbidden_bindings'))
        minimum = [int](Get-Setting -Lines $rootLines -Key 'min_instructions')
        maximum = [int](Get-Setting -Lines $rootLines -Key 'max_instructions')
    }
}

$shaderFiles = @(Get-ChildItem -LiteralPath $resolvedShaders -Filter '*.asm' -File | Sort-Object Name)
$matches = [Collections.Generic.List[object]]::new()
$timeouts = [Collections.Generic.List[object]]::new()
$failures = [Collections.Generic.List[string]]::new()
foreach ($file in $shaderFiles) {
    $text = ([IO.File]::ReadAllText($file.FullName) -replace "`r`n", "`n")
    $instructionCount = Get-InstructionCount $text
    $matched = [Collections.Generic.List[string]]::new()
    foreach ($entry in $families.GetEnumerator()) {
        $contract = $entry.Value
        if ($instructionCount -lt $contract.minimum -or $instructionCount -gt $contract.maximum) { continue }
        $bindingFailure = $false
        foreach ($binding in $contract.required) {
            if (-not (Test-DeclarationBinding -Assembly $text -Requested $binding)) { $bindingFailure = $true; break }
        }
        if ($bindingFailure) { continue }
        foreach ($binding in $contract.forbidden) {
            if (Test-DeclarationBinding -Assembly $text -Requested $binding) { $bindingFailure = $true; break }
        }
        if ($bindingFailure) { continue }
        try {
            if ($contract.regex.IsMatch($text)) { $matched.Add($entry.Key) }
        }
        catch [Text.RegularExpressions.RegexMatchTimeoutException] {
            $timeouts.Add([ordered]@{ file=$file.Name; family=$entry.Key })
        }
    }
    if ($matched.Count) { $matches.Add([ordered]@{ file=$file.Name; instructionCount=$instructionCount; families=@($matched) }) }
    if ($matched.Count -gt 1) { $failures.Add("shader matched multiple automatic families: $($file.Name)") }
}

$expectedFiles = @($families.Values | ForEach-Object { $_.expected } | Sort-Object)
$actualFiles = @($matches | ForEach-Object file | Sort-Object)
if (@(Compare-Object $expectedFiles $actualFiles).Count) {
    $failures.Add('union of automatic family contracts did not match the exact expected five-shader set')
}
foreach ($entry in $families.GetEnumerator()) {
    $actual = @($matches | Where-Object { $_.families -contains $entry.Key } | ForEach-Object file | Sort-Object)
    if (@(Compare-Object @($entry.Value.expected | Sort-Object) $actual).Count) {
        $failures.Add("family membership mismatch: $($entry.Key)")
    }
}
if ($shaderFiles.Count -ne 184) { $failures.Add("regional corpus changed from 184 shaders to $($shaderFiles.Count)") }
if ($timeouts.Count) { $failures.Add("regex timed out $($timeouts.Count) time(s)") }

$report = [ordered]@{
    schemaVersion = 3
    kind = 'remake-accepted-contact-family-full-contract'
    mode = 'offline-fail-closed-three-family-engine-equivalent-contract'
    shaderDirectory = $resolvedShaders
    shaderCount = $shaderFiles.Count
    patternIni = $resolvedIni
    patternIniSha256 = $iniSha
    generationReport = $resolvedGeneration
    expectedByFamily = [ordered]@{}
    matches = @($matches)
    matchCount = $matches.Count
    timeouts = @($timeouts)
    exactExpectedSet = @(Compare-Object $expectedFiles $actualFiles).Count -eq 0
    passed = $failures.Count -eq 0
    failures = @($failures)
}
foreach ($entry in $families.GetEnumerator()) { $report.expectedByFamily[$entry.Key] = $entry.Value.expected }
[void](New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput -Parent))
[IO.File]::WriteAllText($resolvedOutput, ($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
if ($failures.Count) { throw "Accepted contact-family contract test failed: $($failures -join '; ')" }
Write-Host "PASS: engine-equivalent contracts matched exactly five of $($shaderFiles.Count) shaders with the expected 3+1+1 split."
Write-Host "REPORT=$resolvedOutput"
