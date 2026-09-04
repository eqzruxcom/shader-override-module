[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$GeneratedRuntimeDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\generated-runtime\FF7RemakeIntergrade')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$generatedRoot = (Resolve-Path -LiteralPath $GeneratedRuntimeDirectory).Path.TrimEnd('\')
$baselinePath = Join-Path $generatedRoot 'live-reload-baseline.json'
$statusPath = Join-Path $generatedRoot 'live-reload-status.json'
$utf8 = [Text.UTF8Encoding]::new($false)
if (-not (Test-Path -LiteralPath $baselinePath -PathType Leaf)) { throw "Live-reload baseline is missing: $baselinePath" }
$baseline = Get-Content -Raw -LiteralPath $baselinePath | ConvertFrom-Json
$logPath = [string]$baseline.logPath
if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) { throw "Live 3Dmigoto log is missing: $logPath" }
$log = Get-Item -LiteralPath $logPath
if ([long]$log.Length -lt [long]$baseline.byteOffset) { throw 'Live log was truncated after the baseline; capture a new baseline.' }

$stream = [IO.File]::Open($logPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
try {
    $null = $stream.Seek([long]$baseline.byteOffset, [IO.SeekOrigin]::Begin)
    $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true, 4096, $true)
    try { $appended = $reader.ReadToEnd() } finally { $reader.Dispose() }
} finally { $stream.Dispose() }

$reloadSeen = $appended -match '(?m)^> d3dx\.ini reloaded\s*$'
$generatedIniSeen = $appended -match '(?i)UE4EffectsGenerated\.ini'
$keyResults = foreach ($key in @($baseline.expectedControlKeys)) {
    # 3Dmigoto logs [KeyFoo] as [Key\path\Foo], dropping the source
    # section's leading "Key" token. Accept both baseline representations.
    $sectionTail = ([string]$key) -replace '^Key', ''
    $logPattern = '(?im)^\[Key\\Mods\\UE4EffectsGenerated\.ini\\' + [regex]::Escape($sectionTail) + '\]\s*$'
    [pscustomobject]@{ key = $sectionTail; seen = $appended -match $logPattern }
}
$eligibleHashResults = foreach ($hash in @($baseline.expectedEligibleHashes)) {
    [pscustomobject]@{ hash = [string]$hash; seen = $appended -match [regex]::Escape([string]$hash) }
}
$generatedSectionBodies = [Collections.Generic.List[string]]::new()
$inGeneratedSection = $false
foreach ($line in @($appended -split "`r?`n")) {
    if ($line -match '^\[([^\]]+)\]\s*$') {
        $inGeneratedSection = $Matches[1] -match '(?i)\\Mods\\UE4EffectsGenerated\.ini\\'
    }
    if ($inGeneratedSection) { $generatedSectionBodies.Add($line) }
}
$generatedSectionText = $generatedSectionBodies -join "`n"
$forbiddenHashResults = foreach ($hash in @($baseline.forbiddenBlockedHashes)) {
    [pscustomobject]@{
        hash = [string]$hash
        leakedInGeneratedLines = $generatedSectionText -match ('(?im)^\s*Hash\s*=\s*' + [regex]::Escape([string]$hash) + '\s*$')
    }
}
$errorPatterns = @(
    '(?i)syntax\s+error',
    '(?i)unrecognised\s+entry',
    '(?i)unrecognized\s+entry',
    '(?i)endif\s+missing',
    '(?i)failed\s+to\s+(?:compile|parse|load)',
    '(?i)error.*UE4EffectsGenerated',
    '(?i)UE4EffectsGenerated.*error'
)
$errorLines = @($appended -split "`r?`n" | Where-Object {
    $line = $_
    @($errorPatterns | Where-Object { $line -match $_ }).Count -gt 0
} | Select-Object -Unique)

$classification = if (-not $reloadSeen) {
    'pending-no-reload'
} elseif ($errorLines.Count) {
    'failed-parser-or-compile-error'
} elseif (-not $generatedIniSeen) {
    'failed-generated-ini-not-loaded'
} elseif (@($keyResults | Where-Object { -not $_.seen }).Count) {
    'failed-generated-keys-incomplete'
} elseif (@($eligibleHashResults | Where-Object { -not $_.seen }).Count) {
    'failed-eligible-overrides-incomplete'
} elseif (@($forbiddenHashResults | Where-Object leakedInGeneratedLines).Count) {
    'failed-blocked-hash-leak'
} else {
    'passed-live-parser-reload'
}

$process = @(Get-Process -Id ([int]$baseline.processId) -ErrorAction SilentlyContinue)
$status = [ordered]@{
    schemaVersion = 1
    adapterId = [string]$baseline.adapterId
    checkedAtUtc = [DateTime]::UtcNow.ToString('o')
    baseline = $baselinePath.Substring($projectPath.Length + 1).Replace('\', '/')
    baselineSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $baselinePath).Hash
    processAlive = $process.Count -eq 1
    processResponding = if ($process.Count -eq 1) { [bool]$process[0].Responding } else { $false }
    appendedBytes = [long]$log.Length - [long]$baseline.byteOffset
    logLastWriteTimeUtc = $log.LastWriteTimeUtc.ToString('o')
    reloadSeen = $reloadSeen
    generatedIniSeen = $generatedIniSeen
    keyResults = @($keyResults)
    eligibleHashResults = @($eligibleHashResults)
    forbiddenHashResults = @($forbiddenHashResults)
    errorLines = @($errorLines)
    classification = $classification
}
[IO.File]::WriteAllText($statusPath, ($status | ConvertTo-Json -Depth 7) + [Environment]::NewLine, $utf8)

[pscustomobject]@{
    Classification = $classification
    ProcessAlive = $status.processAlive
    ProcessResponding = $status.processResponding
    AppendedBytes = $status.appendedBytes
    ReloadSeen = $reloadSeen
    GeneratedIniSeen = $generatedIniSeen
    ErrorLines = $errorLines.Count
    Status = $statusPath
}
