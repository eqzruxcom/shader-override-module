[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')][string]$CaptureId,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$InstallManifestPath,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($InstallManifestPath)) { $InstallManifestPath = Join-Path $projectPath "artifacts\installed-validation-capture-kits\$CaptureId.json" }
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $projectPath "artifacts\validation-capture-status\$CaptureId.json" }
$manifestFull = (Resolve-Path -LiteralPath $InstallManifestPath).Path
$outputFull = [IO.Path]::GetFullPath($OutputPath)
if (-not $manifestFull.StartsWith($projectPath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Install manifest escaped the project.' }
if (-not $outputFull.StartsWith($projectPath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Status output must remain inside the project.' }
$manifest = & (Join-Path $PSScriptRoot 'Assert-UE4ValidationManifest.ps1') -Kind Install -Path $manifestFull -ProjectRoot $projectPath
if ([string]$manifest.captureId -ne $CaptureId) { throw 'Capture id does not match the install manifest.' }
$targetRoot = [IO.Path]::GetFullPath([string]$manifest.targetRoot).TrimEnd('\')
$exePath = [string]$manifest.gameExecutable.path
$exePresent = Test-Path -LiteralPath $exePath -PathType Leaf
$exeHashMatches = $exePresent -and (Get-FileHash -Algorithm SHA256 -LiteralPath $exePath).Hash -eq [string]$manifest.gameExecutable.sha256
$logPath = Join-Path $targetRoot 'd3d11_log.txt'
$logPresent = Test-Path -LiteralPath $logPath -PathType Leaf
$logText = if ($logPresent) { [IO.File]::ReadAllText($logPath) } else { '' }
$wrapperMarkers = [ordered]@{
    migotoPath = $logText -match '(?im)^3DMigoto path:'
    d3d11Device = $logText -match '(?i)D3D11CreateDevice returned device handle'
    swapChain = $logText -match '(?i)HackerSwapChain .* created to wrap'
}
$configErrorLines = @($logText -split "`r?`n" | Where-Object {
    $_ -match '(?i)(?:unrecognised|unrecognized) entry|endif missing|(?:d3dx|\.ini).*syntax error|syntax error.*(?:d3dx|\.ini)'
} | Select-Object -Unique)
$shaderCache = Join-Path $targetRoot 'ShaderCache'
$validShaders = @(if (Test-Path -LiteralPath $shaderCache -PathType Container) {
    Get-ChildItem -LiteralPath $shaderCache -Filter '*.bin' -File | Where-Object Name -match '^[0-9A-Fa-f]{16}-(ps|vs|cs|gs|hs|ds)\.bin$'
})
$stageCounts = @($validShaders | ForEach-Object { if ($_.Name -match '-(?<stage>ps|vs|cs|gs|hs|ds)\.bin$') { $Matches.stage } } | Group-Object | Sort-Object Name | ForEach-Object { [pscustomobject]@{ stage=$_.Name; count=$_.Count } })
$processName = [IO.Path]::GetFileNameWithoutExtension($exePath)
$process = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
$classification = if (-not $exeHashMatches) {
    'failed-executable-fingerprint'
} elseif (-not $logPresent) {
    'awaiting-first-launch'
} elseif ($configErrorLines.Count) {
    'failed-config-parse'
} elseif (@($wrapperMarkers.Values | Where-Object { -not $_ }).Count) {
    'failed-wrapper-not-active'
} elseif (-not $validShaders.Count) {
    'capturing-no-valid-shaders-yet'
} else {
    'ready-to-import'
}
$status = [ordered]@{
    schemaVersion = 1
    captureId = $CaptureId
    checkedAtUtc = [DateTime]::UtcNow.ToString('o')
    classification = $classification
    gameExecutable = [ordered]@{ path=$exePath; present=$exePresent; fingerprintMatches=$exeHashMatches }
    process = [ordered]@{ running=$process.Count -gt 0; responding=if($process.Count -eq 1){[bool]$process[0].Responding}else{$null} }
    log = [ordered]@{ path=$logPath; present=$logPresent; wrapperMarkers=$wrapperMarkers; configErrorLines=@($configErrorLines) }
    shaderCache = [ordered]@{ path=$shaderCache; validShaderCount=$validShaders.Count; stageCounts=@($stageCounts) }
    readyToImport = $classification -eq 'ready-to-import'
}
[IO.Directory]::CreateDirectory((Split-Path -Parent $outputFull)) | Out-Null
[IO.File]::WriteAllText($outputFull, ($status | ConvertTo-Json -Depth 7) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
[pscustomobject]@{ CaptureId=$CaptureId; Classification=$classification; ValidShaders=$validShaders.Count; ProcessRunning=$status.process.running; ReadyToImport=$status.readyToImport; Status=$outputFull }
