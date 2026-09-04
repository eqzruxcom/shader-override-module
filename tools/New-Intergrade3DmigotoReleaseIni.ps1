[CmdletBinding()]
param(
    [string]$SourcePath = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\d3dx.ini',
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\3dmigoto-release-ini-candidate-20260831-v1')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "Source INI was not found: $SourcePath"
}

$sourceBytes = [IO.File]::ReadAllBytes($SourcePath)
$encoding = $null
$preambleLength = 0
if ($sourceBytes.Length -ge 3 -and $sourceBytes[0] -eq 0xEF -and $sourceBytes[1] -eq 0xBB -and $sourceBytes[2] -eq 0xBF) {
    $encoding = [Text.UTF8Encoding]::new($true, $true)
    $preambleLength = 3
} elseif ($sourceBytes.Length -ge 2 -and $sourceBytes[0] -eq 0xFF -and $sourceBytes[1] -eq 0xFE) {
    $encoding = [Text.UnicodeEncoding]::new($false, $true, $true)
    $preambleLength = 2
} elseif ($sourceBytes.Length -ge 2 -and $sourceBytes[0] -eq 0xFE -and $sourceBytes[1] -eq 0xFF) {
    $encoding = [Text.UnicodeEncoding]::new($true, $true, $true)
    $preambleLength = 2
} else {
    try {
        $encoding = [Text.UTF8Encoding]::new($false, $true)
        $null = $encoding.GetString($sourceBytes)
    } catch {
        $encoding = [Text.Encoding]::Default
    }
}

$text = $encoding.GetString($sourceBytes, $preambleLength, $sourceBytes.Length - $preambleLength)
$changes = [ordered]@{
    calls = '0'
    hunting = '0'
    verbose_overlay = '0'
    dump_usage = '0'
}
$changed = @()

foreach ($entry in $changes.GetEnumerator()) {
    $key = [regex]::Escape($entry.Key)
    $pattern = "(?im)^(?<prefix>[ \t]*$key[ \t]*=[ \t]*)(?<value>[^;\r\n]*?)(?<suffix>[ \t]*(?:;[^\r\n]*)?)(?<eol>\r?)$"
    $matches = [regex]::Matches($text, $pattern)
    if ($matches.Count -ne 1) {
        throw "Expected exactly one active '$($entry.Key)' setting, found $($matches.Count)"
    }

    $oldValue = $matches[0].Groups['value'].Value.Trim()
    $replacement = '${prefix}' + $entry.Value + '${suffix}${eol}'
    $text = [regex]::Replace($text, $pattern, $replacement, 1)
    $changed += [ordered]@{
        key = $entry.Key
        from = $oldValue
        to = $entry.Value
    }
}

foreach ($preserved in @('force_stereo', 'automatic_mode', 'allow_check_interface')) {
    $count = [regex]::Matches($text, "(?im)^[ \t]*$([regex]::Escape($preserved))[ \t]*=").Count
    if ($count -ne 1) {
        throw "Expected exactly one preserved '$preserved' setting, found $count"
    }
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$outputPath = Join-Path $OutputDirectory 'd3dx.ini'
$manifestPath = Join-Path $OutputDirectory 'manifest.json'

$bodyBytes = $encoding.GetBytes($text)
$preamble = $encoding.GetPreamble()
if ($preambleLength -eq 0) {
    $preamble = [byte[]]::new(0)
}
$outputBytes = [byte[]]::new($preamble.Length + $bodyBytes.Length)
[Array]::Copy($preamble, 0, $outputBytes, 0, $preamble.Length)
[Array]::Copy($bodyBytes, 0, $outputBytes, $preamble.Length, $bodyBytes.Length)
[IO.File]::WriteAllBytes($outputPath, $outputBytes)

$sourceHash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
$outputHash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
$gameProcesses = @(Get-Process -Name 'ff7remake_' -ErrorAction SilentlyContinue)
$manifest = [ordered]@{
    schemaVersion = 1
    createdUtc = [DateTime]::UtcNow.ToString('o')
    sourcePath = [IO.Path]::GetFullPath($SourcePath)
    sourceSha256 = $sourceHash
    outputPath = [IO.Path]::GetFullPath($outputPath)
    outputSha256 = $outputHash
    changedSettings = $changed
    preservedSettings = [ordered]@{
        force_stereo = ([regex]::Match($text, '(?im)^[ \t]*force_stereo[ \t]*=[ \t]*([^;\r\n]+)').Groups[1].Value.Trim())
        automatic_mode = ([regex]::Match($text, '(?im)^[ \t]*automatic_mode[ \t]*=[ \t]*([^;\r\n]+)').Groups[1].Value.Trim())
        allow_check_interface = ([regex]::Match($text, '(?im)^[ \t]*allow_check_interface[ \t]*=[ \t]*([^;\r\n]+)').Groups[1].Value.Trim())
    }
    gameRunning = ($gameProcesses.Count -gt 0)
    installed = $false
}
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6) + "`r`n", [Text.UTF8Encoding]::new($false))

Write-Host "PASS: staged release-mode INI at $outputPath"
Write-Host "PASS: source $sourceHash -> candidate $outputHash; live game was not modified."
