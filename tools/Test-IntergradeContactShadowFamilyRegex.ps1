[CmdletBinding()]
param(
    [string]$ShaderDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\assembly'),
    [string]$IniPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Adapters\FF7RemakeIntergrade\ContactShadowFamilyAudit.ini'),
    [string]$OutputPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\remake-contact-family-regex-audit.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts'))
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
if (-not $resolvedOutput.StartsWith($artifactRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must remain beneath $artifactRoot"
}

$expected = @(
    '08bb8764f1840179-cs.asm',
    '0e97888f9a8767da-cs.asm',
    '5a9fbefe0ab6f815-cs.asm',
    '62b33a2d1e505241-cs.asm',
    'c30cdc8365df9840-cs.asm'
)

$ini = Get-Content -LiteralPath $IniPath
$section = '[ShaderRegexUE4FXRemakeTiledSurfaceLightContactAudit.Pattern]'
$start = [array]::IndexOf($ini, $section)
if ($start -lt 0) { throw "Pattern section missing: $section" }
$patternLines = [Collections.Generic.List[string]]::new()
for ($i = $start + 1; $i -lt $ini.Count; ++$i) {
    $line = $ini[$i].Trim()
    if ($line -match '^\[[^\]]+\]$') { break }
    if ($line -and -not $line.StartsWith(';')) { $patternLines.Add($line) }
}
if ($patternLines.Count -lt 1) { throw 'Contact family pattern is empty' }

# 3Dmigoto uses PCRE2 Python-style named groups. Translate only those two
# constructs for the .NET regression runner; the actual INI remains PCRE2.
$pcre = $patternLines -join ''
$dotnet = [regex]::Replace($pcre, '\(\?P<([A-Za-z_][A-Za-z0-9_]*)>', '(?<$1>')
$dotnet = [regex]::Replace($dotnet, '\(\?P=([A-Za-z_][A-Za-z0-9_]*)\)', '\k<$1>')
$regex = [regex]::new($dotnet, [Text.RegularExpressions.RegexOptions]::IgnoreCase,
    [TimeSpan]::FromSeconds(1))

$matches = [Collections.Generic.List[object]]::new()
$timeouts = [Collections.Generic.List[string]]::new()
foreach ($file in Get-ChildItem -LiteralPath $ShaderDirectory -Filter '*.asm' -File | Sort-Object Name) {
    $text = ([IO.File]::ReadAllText($file.FullName) -replace "`r`n", "`n")
    try { $match = $regex.Match($text) }
    catch [Text.RegularExpressions.RegexMatchTimeoutException] {
        $timeouts.Add($file.Name)
        continue
    }
    if (-not $match.Success) { continue }
    $captures = [ordered]@{}
    foreach ($name in @('light_index','light_index_component','light_loop','light_list',
            'light_shift','light_shift_component','diffuse','specular','specular_mask',
            'diffuse_accumulator','specular_accumulator','specular_pack','scene_color')) {
        $captures[$name] = $match.Groups[$name].Value
    }
    $matches.Add([ordered]@{ file = $file.Name; captures = $captures })
}

$actual = @($matches | ForEach-Object file | Sort-Object)
$difference = @(Compare-Object ($expected | Sort-Object) $actual)
$report = [ordered]@{
    schemaVersion = 1
    kind = 'remake-contact-family-regex-audit'
    mode = 'offline-fail-closed'
    shaderDirectory = [IO.Path]::GetFullPath($ShaderDirectory)
    shaderCount = @(Get-ChildItem -LiteralPath $ShaderDirectory -Filter '*.asm' -File).Count
    patternIni = [IO.Path]::GetFullPath($IniPath)
    patternIniSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $IniPath).Hash
    expected = $expected
    matches = @($matches)
    matchCount = $matches.Count
    timeouts = @($timeouts)
    exactExpectedSet = $difference.Count -eq 0
    runtimePolicy = 'Audit only. Unknown matches are logged and never patched.'
}
[void](New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput -Parent))
[IO.File]::WriteAllText($resolvedOutput, ($report | ConvertTo-Json -Depth 8) + "`n", [Text.UTF8Encoding]::new($false))

if ($timeouts.Count) { throw "Regex timed out on $($timeouts.Count) shader(s)" }
if ($difference.Count) { throw "Contact family regex mismatch: $($difference | Out-String)" }
Write-Host "PASS: contact family regex matched exactly $($matches.Count) of $($report.shaderCount) shaders."
Write-Host "Report: $resolvedOutput"
