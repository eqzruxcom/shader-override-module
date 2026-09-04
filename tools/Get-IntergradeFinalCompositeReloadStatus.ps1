[CmdletBinding()]
param([string]$GeneratedRuntimeDirectory=(Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\generated-runtime\FF7RemakeIntergradeFinalCompositeIsolation'))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$generated=(Resolve-Path -LiteralPath $GeneratedRuntimeDirectory).Path
$generic=& (Join-Path $PSScriptRoot 'Get-UE4GeneratedRuntimeLiveReloadStatus.ps1') -GeneratedRuntimeDirectory $generated
$baseline=Get-Content -Raw -LiteralPath (Join-Path $generated 'live-reload-baseline.json') | ConvertFrom-Json
if ($baseline.adapterId -notin @('FF7RemakeIntergradeFinalCompositeIsolation','FF7RemakeIntergradeAuthorImageAdjustments')) { throw 'Wrong baseline.' }
$stream=[IO.File]::Open($baseline.logPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
try {
    $null=$stream.Seek([long]$baseline.byteOffset,[IO.SeekOrigin]::Begin)
    $reader=[IO.StreamReader]::new($stream)
    try { $text=$reader.ReadToEnd() } finally { $reader.Dispose() }
} finally { $stream.Dispose() }
$assembled=$text -match '(?im)Re-Loading replacement ASM code from 41f1bf8b79d01319-ps\.txt\s*$'
$created=$text -match '(?im)^> successfully reloaded shader: 41f1bf8b79d01319-ps\.txt\s*$'
$errors=@($text -split "`r?`n" | Where-Object { $_ -match '(?i)error assembling|FAILED to reload shaders|(?:error|failed).*(?:41f1bf8b79d01319|assembling)' })
$classification=if ($errors.Count) { 'failed-native-asm-reload' } elseif ($generic.Classification -ne 'passed-live-parser-reload') { $generic.Classification } elseif (-not $assembled -or -not $created) { 'pending-native-asm-load-not-proven' } else { 'passed-native-asm-and-parser-reload' }
$state=[ordered]@{
    classification=$classification; checkedAtUtc=[DateTime]::UtcNow.ToString('o')
    parser=$generic.Classification; assemblySourceSeen=$assembled; gpuShaderCreationSeen=$created
    errorLines=$errors; processAlive=$generic.ProcessAlive; processResponding=$generic.ProcessResponding
    visualSceneResponse='pending-user'; visualUiPreservation='pending-user'
}
[IO.File]::WriteAllText((Join-Path $generated 'final-composite-live-status.json'),($state | ConvertTo-Json -Depth 6)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
[pscustomobject]$state
