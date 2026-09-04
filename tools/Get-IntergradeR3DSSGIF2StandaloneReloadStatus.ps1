[CmdletBinding()]
param(
    [string]$BaselinePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\agent2-r3d-ssgi-live-reload-baseline.json'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\agent2-r3d-ssgi-live-reload-status.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$baselineFull = [IO.Path]::GetFullPath($BaselinePath)
$outputFull = [IO.Path]::GetFullPath($OutputPath)
foreach ($path in @($baselineFull,$outputFull)) {
    if (-not $path.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase)) {
        throw "Reload status workspace path escaped the project: $path"
    }
}
if (-not (Test-Path -LiteralPath $baselineFull -PathType Leaf)) { throw "Reload baseline is missing: $baselineFull" }

function Get-Hash([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

$baseline = Get-Content -Raw -LiteralPath $baselineFull | ConvertFrom-Json
if ($baseline.schemaVersion -ne 1 -or $baseline.packageId -ne 'agent2-r3d-ssgi-f2-standalone' -or
    $baseline.classification -ne 'captured-before-F10-reload' -or $baseline.runtimeEligible -ne $false) {
    throw 'Reload baseline is not the reviewed Agent 2 standalone contract.'
}
$target = [IO.Path]::GetFullPath([string]$baseline.targetModsDirectory).TrimEnd('\')
$logPath = [IO.Path]::GetFullPath([string]$baseline.logPath)
$statePath = [IO.Path]::GetFullPath([string]$baseline.stageStatePath)
$manifestPath = [IO.Path]::GetFullPath([string]$baseline.packManifestPath)
foreach ($path in @($statePath,$manifestPath,$logPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Reload status input is missing: $path" }
}

$changedPayload = [Collections.Generic.List[string]]::new()
foreach ($file in @($baseline.installedFiles)) {
    $path = Join-Path $target ([string]$file.relativePath)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Hash $path) -ne [string]$file.sha256) {
        $changedPayload.Add([string]$file.relativePath)
    }
}
$changedProtected = [Collections.Generic.List[string]]::new()
foreach ($file in @($baseline.protectedFingerprints)) {
    $path = Join-Path $target ([string]$file.relativePath)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Hash $path) -ne [string]$file.sha256) {
        $changedProtected.Add([string]$file.relativePath)
    }
}
if ((Get-Hash $statePath) -ne [string]$baseline.stageStateSha256) { $changedProtected.Add('stage-state-receipt') }
if ((Get-Hash $manifestPath) -ne [string]$baseline.packManifestSha256) { $changedProtected.Add('pack-manifest') }

$process = @(Get-Process -Id ([int]$baseline.processId) -ErrorAction SilentlyContinue)
$processAlive = $process.Count -eq 1 -and [string]::Equals([string]$process[0].Path,[string]$baseline.processPath,[StringComparison]::OrdinalIgnoreCase)
$processResponding = $processAlive -and [bool]$process[0].Responding

$appended = ''
$truncated = $false
$appendedBytes = 0L
$stream = [IO.File]::Open($logPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
try {
    $truncated = $stream.Length -lt [long]$baseline.byteOffset
    if (-not $truncated) {
        $null = $stream.Seek([long]$baseline.byteOffset,[IO.SeekOrigin]::Begin)
        $appendedBytes = $stream.Length - [long]$baseline.byteOffset
        $reader = [IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true,4096,$true)
        try { $appended = $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
} finally {
    $stream.Dispose()
}

$iniName = [regex]::Escape([string]$baseline.expected.ini)
$reloadSeen = $appended -match '(?m)^> d3dx\.ini reloaded\s*$'
$reloadComplete = $appended -match '(?m)^> successfully reloaded shaders from ShaderFixes\s*$'
$keyPattern = '(?im)^\[Key\\Mods\\' + $iniName + '\\' + [regex]::Escape([string]$baseline.expected.keySection) + '\]\s*$'
$overridePattern = '(?im)^\[ShaderOverride\\Mods\\' + $iniName + '\\' + [regex]::Escape([string]$baseline.expected.overrideSection) + '\]\s*$'
$keySeen = $appended -match $keyPattern
$overrideSeen = $appended -match $overridePattern
$hashSeen = $appended -match ('(?im)^\s*Hash\s*=\s*' + [regex]::Escape([string]$baseline.expected.shaderHash) + '\s*$')
$customResults = @(
    foreach ($name in @($baseline.expected.customSections)) {
        $pattern = '(?im)^\[CustomShader\\Mods\\' + $iniName + '\\' + [regex]::Escape([string]$name) + '\]\s*$'
        [ordered]@{name=[string]$name; parsed=($appended -match $pattern)}
    }
)
$shaderResults = @(
    foreach ($name in @($baseline.expected.shaderFiles)) {
        $pattern = '(?im)^\s*ps\s*=\s*' + [regex]::Escape([string]$name) + '\s*$'
        [ordered]@{name=[string]$name; compileEntrySeen=($appended -match $pattern)}
    }
)

$errorPatterns = @(
    '(?i)syntax\s+error',
    '(?i)unrecognised\s+entry',
    '(?i)unrecognized\s+entry',
    '(?i)endif\s+missing',
    '(?i)shader\s+not\s+found',
    '(?i)error\s+reading\s+HLSL\s+file',
    '(?i)error\s+compiling\s+custom\s+shader',
    '(?i)failed\s+to\s+(?:compile|parse|load|reload)',
    '(?i)\berror\s+[A-Z]\d{4}:',
    '(?i)Agent2R3DSSGI.*\berror\b',
    '(?i)\berror\b.*Agent2R3DSSGI',
    '(?i)warning.*(?:Agent2R3DSSGI|Agent2R3DSSGITest|duplicate|override)'
)
$errorLines = @(
    $appended -split '\r?\n' | Where-Object {
        $line = $_
        @($errorPatterns | Where-Object {$line -match $_}).Count -gt 0
    } | Select-Object -Unique
)
$customComplete = @($customResults | Where-Object {-not $_.parsed}).Count -eq 0
$shaderEntriesComplete = @($shaderResults | Where-Object {-not $_.compileEntrySeen}).Count -eq 0

$classification = if ($changedPayload.Count -or $changedProtected.Count) {
    'failed-live-or-receipt-hash-drift'
} elseif (-not $processAlive -or $truncated) {
    'process-or-log-restarted-rebaseline-required'
} elseif ($errorLines.Count) {
    'failed-parser-or-custom-shader-compile'
} elseif (-not $reloadSeen) {
    'pending-F10'
} elseif (-not $keySeen) {
    'failed-F2-key-not-parsed'
} elseif (-not $overrideSeen -or -not $hashSeen) {
    'failed-e2aa-override-not-parsed'
} elseif (-not $customComplete) {
    'failed-six-custom-sections-incomplete'
} elseif (-not $shaderEntriesComplete) {
    'failed-six-custom-HLSL-entries-incomplete'
} elseif (-not $reloadComplete) {
    'pending-reload-completion'
} else {
    'passed-parser-and-six-custom-HLSL-compile-clean'
}

$status = [ordered]@{
    schemaVersion = 1
    packageId = 'agent2-r3d-ssgi-f2-standalone'
    checkedAtUtc = [DateTime]::UtcNow.ToString('o')
    classification = $classification
    baselinePath = [IO.Path]::GetRelativePath($root,$baselineFull)
    baselineSha256 = Get-Hash $baselineFull
    processId = [int]$baseline.processId
    processAlive = $processAlive
    processResponding = $processResponding
    logTruncated = $truncated
    appendedBytes = $appendedBytes
    reloadSeen = $reloadSeen
    reloadComplete = $reloadComplete
    keyParsed = $keySeen
    overrideParsed = $overrideSeen
    hashParsed = $hashSeen
    customSections = $customResults
    shaderCompileEntries = $shaderResults
    errorLines = $errorLines
    changedPayloadFiles = @($changedPayload)
    changedProtectedFiles = @($changedProtected)
    parserAndCompileClean = $classification -eq 'passed-parser-and-six-custom-HLSL-compile-clean'
    visualResult = 'pending user F2 still and motion observation'
    performanceVerified = $false
    runtimeEligible = $false
}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull)) | Out-Null
[IO.File]::WriteAllText($outputFull,(($status|ConvertTo-Json -Depth 12)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Classification = $classification
    ProcessAlive = $processAlive
    ProcessResponding = $processResponding
    AppendedBytes = $appendedBytes
    ReloadSeen = $reloadSeen
    KeyParsed = $keySeen
    OverrideParsed = $overrideSeen
    CustomSections = @($customResults | Where-Object parsed).Count
    ShaderEntries = @($shaderResults | Where-Object compileEntrySeen).Count
    ErrorLines = $errorLines.Count
    RuntimeEligible = $false
    Output = $outputFull
}
