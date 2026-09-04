[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$GameRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes',
    [int]$ProcessId = 0,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$gamePath = (Resolve-Path -LiteralPath $GameRoot).Path.TrimEnd('\')
$runtimeRoot = Join-Path $gamePath 'End\Binaries\Win64'
$modsRoot = Join-Path $runtimeRoot 'Mods'
$logPath = Join-Path $runtimeRoot 'd3d11_log.txt'
$schemaPath = Join-Path $projectPath 'src\Engine\UE4\RuntimeHealth\schema.json'
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $projectPath 'artifacts\runtime-health\latest.json' }
$outputFull = [IO.Path]::GetFullPath($OutputPath)
$allowedOutput = [IO.Path]::GetFullPath((Join-Path $projectPath 'artifacts\runtime-health')).TrimEnd('\')
if (-not $outputFull.StartsWith($allowedOutput + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Runtime-health output must remain below artifacts/runtime-health.' }

$process = $null
if ($ProcessId -gt 0) { $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue }
else { $process = Get-Process -Name 'ff7remake_' -ErrorAction SilentlyContinue | Sort-Object StartTime -Descending | Select-Object -First 1 }
$processRecord = if ($null -eq $process) {
    [ordered]@{running=$false;id=$null;responding=$null;startTimeUtc=$null;workingSetBytes=$null;cpuSeconds=$null}
} else {
    [ordered]@{
        running=$true;id=[int]$process.Id;responding=[bool]$process.Responding
        startTimeUtc=$process.StartTime.ToUniversalTime().ToString('o')
        workingSetBytes=[long]$process.WorkingSet64;cpuSeconds=[double]$process.CPU
    }
}

$logPresent = Test-Path -LiteralPath $logPath -PathType Leaf
$logText = ''
$logBytes = [byte[]]@()
if ($logPresent) {
    $stream = [IO.File]::Open($logPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $memory = [IO.MemoryStream]::new()
        $stream.CopyTo($memory)
        $logBytes = $memory.ToArray()
        $logText = [Text.Encoding]::UTF8.GetString($logBytes)
    } finally {
        if ($memory) { $memory.Dispose() }
        $stream.Dispose()
    }
}
$logLines = if ($logText.Length) { @($logText -split "\r?\n") } else { @() }
$tailStart = [Math]::Max(0, $logLines.Count - 80)
$tail = if ($logLines.Count) { @($logLines[$tailStart..($logLines.Count-1)]) } else { @() }
$parserWarnings = if ($logText.Length) { ([regex]::Matches($logText, '(?im)^\s*(WARNING: Unrecognised entry|Syntax Error|ERROR:)')).Count } else { 0 }
$generatedIni = Join-Path $modsRoot 'UE4EffectsGenerated.ini'
$d3dxIni = Join-Path $runtimeRoot 'd3dx.ini'
$activeLegacy = @('RebirthEffectsDX11.ini','RebirthFogGlobalDX11.ini') | Where-Object { Test-Path -LiteralPath (Join-Path $modsRoot $_) -PathType Leaf }
$generatedLoaded = $logText -match '\[ShaderOverride\\Mods\\UE4EffectsGenerated\.ini'
$deviceCreated = $logText -match 'D3D11CreateDevice returned device handle'
$swapChainWrapped = $logText -match 'HackerSwapChain .+ created to wrap'

$classification = if ($null -eq $process) { 'process-exited' }
elseif (-not $logPresent) { 'awaiting-log' }
elseif ($parserWarnings -gt 0) { 'failed-parser' }
elseif (@($activeLegacy).Count) { 'failed-legacy-conflict' }
elseif (-not $deviceCreated -or -not $swapChainWrapped -or -not $generatedLoaded -or -not (Test-Path -LiteralPath $generatedIni -PathType Leaf)) { 'capturing-incomplete' }
else { 'healthy-generated-runtime' }
$result = if ($classification -eq 'healthy-generated-runtime') { 'pass' } elseif ($classification -in @('awaiting-log','capturing-incomplete')) { 'pending' } else { 'fail' }
$logItem = if ($logPresent) { Get-Item -LiteralPath $logPath } else { $null }
$report = [ordered]@{
    schemaVersion=1;capturedAtUtc=[DateTime]::UtcNow.ToString('o');classification=$classification;gameRoot=$gamePath
    process=$processRecord
    log=[ordered]@{
        present=$logPresent;path=$logPath;size=if($logPresent){[long]$logBytes.Length}else{0}
        sha256=if($logPresent){[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($logBytes))}else{$null}
        lastWriteUtc=if($logPresent){$logItem.LastWriteTimeUtc.ToString('o')}else{$null}
        deviceCreated=$deviceCreated;swapChainWrapped=$swapChainWrapped;parserWarningCount=$parserWarnings;tail=@($tail)
    }
    runtime=[ordered]@{
        generatedIniPresent=(Test-Path -LiteralPath $generatedIni -PathType Leaf);generatedRuntimeLoaded=$generatedLoaded
        generatedIniSha256=if(Test-Path -LiteralPath $generatedIni -PathType Leaf){(Get-FileHash -Algorithm SHA256 -LiteralPath $generatedIni).Hash}else{$null}
        d3dxIniSha256=if(Test-Path -LiteralPath $d3dxIni -PathType Leaf){(Get-FileHash -Algorithm SHA256 -LiteralPath $d3dxIni).Hash}else{$null}
        activeLegacyDiagnostics=@($activeLegacy)
    }
    result=$result
}
$json = ($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine
if (-not ($json | Test-Json -SchemaFile $schemaPath -ErrorAction Stop)) { throw 'Runtime-health snapshot failed its schema.' }
[IO.Directory]::CreateDirectory((Split-Path -Parent $outputFull)) | Out-Null
[IO.File]::WriteAllText($outputFull, $json, [Text.UTF8Encoding]::new($false))
[pscustomobject]@{Classification=$classification;Result=$result;ProcessId=$processRecord.id;Output=$outputFull;Sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $outputFull).Hash}
