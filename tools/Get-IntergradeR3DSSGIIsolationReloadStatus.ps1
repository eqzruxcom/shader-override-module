[CmdletBinding()]
param(
    [string]$BaselinePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\agent2-r3d-ssgi-isolation-reload-baseline.json'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\agent2-r3d-ssgi-isolation-reload-status.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$baselineFull = [IO.Path]::GetFullPath($BaselinePath)
$output = [IO.Path]::GetFullPath($OutputPath)
foreach ($path in @($baselineFull,$output)) {
    if (-not $path.StartsWith($workspace + '\',[StringComparison]::OrdinalIgnoreCase)) {
        throw "Reload-status path escaped the workspace: $path"
    }
}
if (-not (Test-Path -LiteralPath $baselineFull -PathType Leaf)) { throw "Reload baseline is missing: $baselineFull" }
$baseline = Get-Content -Raw -LiteralPath $baselineFull | ConvertFrom-Json
if ($baseline.schemaVersion -ne 1 -or $baseline.kind -ne 'agent2-r3d-ssgi-isolation-reload-baseline' -or
    $baseline.classification -ne 'captured-before-F10' -or $baseline.runtimeEligible -ne $false) {
    throw 'Reload baseline contract is invalid.'
}

$target = [IO.Path]::GetFullPath([string]$baseline.targetModsDirectory).TrimEnd('\')
$changedLive = [Collections.Generic.List[string]]::new()
foreach ($file in @($baseline.liveFiles)) {
    $path = Join-Path $target ([string]$file.name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$file.sha256 -or
        (Get-Item -LiteralPath $path).Length -ne [long]$file.bytes) {
        $changedLive.Add([string]$file.name)
    }
}
$win64 = Split-Path -Parent $target
$changedProtected = [Collections.Generic.List[string]]::new()
foreach ($file in @($baseline.protectedFiles)) {
    $path = Join-Path $win64 ([string]$file.relativePath)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$file.sha256) {
        $changedProtected.Add([string]$file.relativePath)
    }
}

$processes = @(Get-Process -Id ([int]$baseline.process.id) -ErrorAction SilentlyContinue)
$processAlive = $processes.Count -eq 1 -and
    [string]::Equals([string]$processes[0].Path,[string]$baseline.process.path,[StringComparison]::OrdinalIgnoreCase)
$processResponding = $processAlive -and [bool]$processes[0].Responding

$logPath = [IO.Path]::GetFullPath([string]$baseline.log.path)
$stream = [IO.File]::Open($logPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
try {
    $truncated = $stream.Length -lt [long]$baseline.log.byteOffset
    $appendedBytes = if ($truncated) { 0L } else { $stream.Length - [long]$baseline.log.byteOffset }
    $appended = ''
    if (-not $truncated -and $appendedBytes -gt 0) {
        $null = $stream.Seek([long]$baseline.log.byteOffset,[IO.SeekOrigin]::Begin)
        $reader = [IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true,4096,$true)
        try { $appended = $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
} finally { $stream.Dispose() }

$iniName = [regex]::Escape([string]$baseline.expected.ini)
$reloadSeen = $appended -match '(?m)^> d3dx\.ini reloaded\s*$'
$reloadComplete = $appended -match '(?m)^> successfully reloaded shaders from ShaderFixes\s*$'
$keySeen = $appended -match ('(?im)^\[Key\\Mods\\' + $iniName + '\\' + [regex]::Escape([string]$baseline.expected.keySection) + '\]\s*$')
$overrideSeen = $appended -match ('(?im)^\[ShaderOverride\\Mods\\' + $iniName + '\\' + [regex]::Escape([string]$baseline.expected.overrideSection) + '\]\s*$')
$hashSeen = $appended -match ('(?im)^\s*Hash\s*=\s*' + [regex]::Escape([string]$baseline.expected.shaderHash) + '\s*$')
$customResults = @(
    foreach ($name in @($baseline.expected.customSections)) {
        [ordered]@{name=[string]$name;parsed=($appended -match ('(?im)^\[CustomShader\\Mods\\' + $iniName + '\\' + [regex]::Escape([string]$name) + '\]\s*$'))}
    }
)
$shaderResults = @(
    foreach ($name in @($baseline.expected.shaderFiles)) {
        [ordered]@{name=[string]$name;compileEntrySeen=($appended -match ('(?im)^\s*ps\s*=\s*' + [regex]::Escape([string]$name) + '\s*$'))}
    }
)
$errorPatterns = @(
    '(?i)syntax\s+error','(?i)unrecognised\s+entry','(?i)unrecognized\s+entry','(?i)endif\s+missing',
    '(?i)shader\s+not\s+found','(?i)error\s+reading\s+HLSL\s+file','(?i)error\s+compiling\s+custom\s+shader',
    '(?i)failed\s+to\s+(?:compile|parse|load|reload)','(?i)\berror\s+[A-Z]\d{4}:',
    '(?i)Agent2R3DSSGI.*\berror\b','(?i)\berror\b.*Agent2R3DSSGI','(?i)warning.*(?:Agent2R3DSSGI|duplicate|override)'
)
$errorLines = @($appended -split '\r?\n' | Where-Object {
    $line=$_; @($errorPatterns | Where-Object {$line -match $_}).Count -gt 0
} | Select-Object -Unique)
$customComplete = @($customResults | Where-Object {-not $_.parsed}).Count -eq 0
$shaderComplete = @($shaderResults | Where-Object {-not $_.compileEntrySeen}).Count -eq 0

$classification = if ($changedLive.Count -or $changedProtected.Count) {
    'failed-file-hash-drift'
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
} elseif (-not $customComplete -or -not $shaderComplete) {
    'failed-custom-sections-or-HLSL-incomplete'
} elseif (-not $reloadComplete) {
    'pending-reload-completion'
} else {
    'passed-parser-and-custom-HLSL-compile-clean'
}

$status = [ordered]@{
    schemaVersion=1
    kind='agent2-r3d-ssgi-isolation-reload-status'
    checkedUtc=[DateTime]::UtcNow.ToString('o')
    variant=[string]$baseline.variant
    classification=$classification
    processAlive=$processAlive
    processResponding=$processResponding
    logTruncated=$truncated
    appendedBytes=$appendedBytes
    reloadSeen=$reloadSeen
    reloadComplete=$reloadComplete
    keyParsed=$keySeen
    overrideParsed=$overrideSeen
    hashParsed=$hashSeen
    customSections=$customResults
    shaderCompileEntries=$shaderResults
    errorLines=$errorLines
    changedLiveFiles=@($changedLive)
    changedProtectedFiles=@($changedProtected)
    visualResult='pending user F2 comparison'
    runtimeEligible=$false
}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,(($status | ConvertTo-Json -Depth 10) + "`r`n"),[Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Classification=$classification
    Variant=[string]$baseline.variant
    ProcessAlive=$processAlive
    ProcessResponding=$processResponding
    AppendedBytes=$appendedBytes
    ReloadSeen=$reloadSeen
    KeyParsed=$keySeen
    OverrideParsed=$overrideSeen
    CustomSections=@($customResults | Where-Object parsed).Count
    ShaderEntries=@($shaderResults | Where-Object compileEntrySeen).Count
    ErrorLines=$errorLines.Count
    LiveFileDrift=$changedLive.Count
    ProtectedFileDrift=$changedProtected.Count
    Output=$output
}
