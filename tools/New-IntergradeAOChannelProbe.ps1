[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('x','y','z','w')]
    [string]$ZeroChannel,
    [string]$SourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\captured-shaders\a77b589dce5822d6-ps\a77b589dce5822d6-ps_decompiled.txt'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-channel-probes'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')

function Resolve-WorkspacePath([string]$Path, [switch]$AllowMissing) {
    $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $repoRoot $Path)) }
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Path must remain inside the project workspace: $full" }
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "File does not exist: $full" }
    $full
}

$sourceFull = Resolve-WorkspacePath $SourcePath
$outputFull = Resolve-WorkspacePath $OutputDirectory -AllowMissing
New-Item -ItemType Directory -Path $outputFull -Force | Out-Null
if (-not (Test-Path -LiteralPath $FxcPath -PathType Leaf)) { throw "FXC was not found: $FxcPath" }

$baseName = "RebirthAOZeroChannel$($ZeroChannel.ToUpperInvariant())_ps"
$hlslPath = Join-Path $outputFull "$baseName.hlsl"
$objectPath = Join-Path $outputFull "$baseName.cso"
$assemblyPath = Join-Path $outputFull "$baseName.asm"
$manifestPath = Join-Path $outputFull "$baseName.json"

$components = [ordered]@{ x = 'r2.w'; y = 'r2.x'; z = 'r2.y'; w = 'r2.z' }
$components[$ZeroChannel] = '0'
$replacement = "  // Diagnostic: zero only packed temporal-SSAO output channel $ZeroChannel.`n  o0.xyzw = float4($($components.x), $($components.y), $($components.z), $($components.w));"
$source = [IO.File]::ReadAllText($sourceFull)
$pattern = '(?m)^  o0\.xyzw = r2\.wxyz;$'
$matches = [regex]::Matches($source, $pattern)
if ($matches.Count -ne 1) { throw "Expected exactly one packed temporal-SSAO output assignment, found $($matches.Count)." }
$generated = [regex]::Replace($source, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement }, 1)
[IO.File]::WriteAllText($hlslPath, $generated, [Text.UTF8Encoding]::new($false))

$compilerOutput = & $FxcPath /nologo /T ps_5_0 /E main /Ges /WX /O3 /Fo $objectPath /Fc $assemblyPath $hlslPath 2>&1
if ($LASTEXITCODE -ne 0) { throw "FXC failed for $baseName`n$($compilerOutput -join [Environment]::NewLine)" }

$assembly = [IO.File]::ReadAllText($assemblyPath)
foreach ($binding in @('t0','t1','t2','t3','t4','t5','cb0','cb1')) {
    if ($assembly -notmatch "(?m)^//\s+$binding\s+") { throw "Compiled probe is missing expected binding $binding." }
}
if ($assembly -notmatch '(?m)^//\s+s0_s\s+sampler\s+' -or $assembly -notmatch '(?m)^dcl_sampler\s+s0,\s*mode_default\s*$') {
    throw 'Compiled probe is missing the expected s0 sampler binding or declaration.'
}
if ($assembly -notmatch '(?m)^//\s+SV_Target\s+0\s+xyzw') { throw 'Compiled probe is missing SV_Target0.' }

$manifest = [ordered]@{
    schemaVersion = 1
    adapter = 'FF7RemakeIntergrade'
    shaderHash = 'a77b589dce5822d6'
    stage = 'ps'
    effect = 'temporal-ssao-packed-channel-isolation'
    zeroChannel = $ZeroChannel
    originalPacking = [ordered]@{ x = 'r2.w'; y = 'r2.x'; z = 'r2.y'; w = 'r2.z' }
    source = $hlslPath.Substring($repoRoot.Length + 1).Replace('\','/')
    sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hlslPath).Hash
    object = $objectPath.Substring($repoRoot.Length + 1).Replace('\','/')
    objectSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectPath).Hash
    assembly = $assemblyPath.Substring($repoRoot.Length + 1).Replace('\','/')
    assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assemblyPath).Hash
    verification = 'strict-compile-diagnostic-only'
    safety = 'Do not uniformly scale packed AO history data. Preserve temporal weight and signed depth until channel roles are fully live-verified.'
}
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    ZeroChannel = $ZeroChannel
    Source = $hlslPath
    Object = $objectPath
    Manifest = $manifestPath
    SourceSha256 = $manifest.sourceSha256
    ObjectSha256 = $manifest.objectSha256
}
