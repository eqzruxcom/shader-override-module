[CmdletBinding()]
param(
    [ValidateRange(2, 64)]
    [double]$Strength = 16.0,
    [string]$SourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ssr-composite-strength-variants\RebirthSSRCompositeStrength100_ps.hlsl'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ssr-composite-strength-diagnostics'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$sourceFull = (Resolve-Path -LiteralPath $SourcePath).Path
if (-not $sourceFull.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Source must remain inside the workspace.' }
if (-not (Test-Path -LiteralPath $FxcPath -PathType Leaf)) { throw "FXC was not found: $FxcPath" }
$outputFull = [IO.Path]::GetFullPath($OutputDirectory)
if (-not $outputFull.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Output must remain inside the workspace.' }
New-Item -ItemType Directory -Force -Path $outputFull | Out-Null

$literal = $Strength.ToString('0.0###', [Globalization.CultureInfo]::InvariantCulture)
$label = ([int][Math]::Round($Strength * 100)).ToString('0000', [Globalization.CultureInfo]::InvariantCulture)
$baseName = "RebirthSSRCompositeDiagnostic$($label)_ps"
$hlslPath = Join-Path $outputFull "$baseName.hlsl"
$objectPath = Join-Path $outputFull "$baseName.cso"
$assemblyPath = Join-Path $outputFull "$baseName.asm"
$manifestPath = Join-Path $outputFull "$baseName.json"

$source = [IO.File]::ReadAllText($sourceFull)
$neutralDeclaration = 'float ssrCompositeStrength = 1.0;'
if (($source.Split($neutralDeclaration).Count - 1) -ne 1) { throw 'Expected exactly one neutral strength declaration.' }
$generated = $source.Replace($neutralDeclaration, "float ssrCompositeStrength = $literal;")
foreach ($required in @(
    'r11.w = 1 + -r11.w;',
    'r2.xyz = r2.xyz * r11.www;',
    'r2.xyz = r2.xyz * r0.www + r11.xyz * ssrCompositeStrength;')) {
    if (($generated.Split($required).Count - 1) -ne 1) { throw "Required composite expression is missing or duplicated: $required" }
}
[IO.File]::WriteAllText($hlslPath, $generated, [Text.UTF8Encoding]::new($false))

$compilerOutput = & $FxcPath /nologo /T ps_5_0 /E main /Ges /WX /O3 /Fo $objectPath /Fc $assemblyPath $hlslPath 2>&1
if ($LASTEXITCODE -ne 0) { throw "FXC failed for $baseName`n$($compilerOutput -join [Environment]::NewLine)" }
$assembly = [IO.File]::ReadAllText($assemblyPath)
foreach ($contract in @(
    '(?m)^//\s+t11\s+texture\s+float4\s+2d\s+t11\s+1\s*$',
    '(?m)^//\s+t10\s+texture\s+float4\s+cubearray\s+t10\s+1\s*$',
    '(?m)^//\s+SV_Target\s+0\s+xyzw')) {
    if ($assembly -notmatch $contract) { throw "Compiled diagnostic is missing expected contract pattern: $contract" }
}
if ($assembly -notmatch "(?m)^\s*mul\s+[^\r\n]*r11\.xyz[^\r\n]*l\($([regex]::Escape($Strength.ToString('0.000000', [Globalization.CultureInfo]::InvariantCulture)))") {
    throw 'Compiled diagnostic does not contain the amplified r11.rgb multiplication.'
}

$manifest = [ordered]@{
    schemaVersion = 1
    adapter = 'FF7RemakeIntergrade'
    shaderHash = 'e2aa1c8cb39e0a55'
    stage = 'ps'
    mode = 'diagnostic-amplified-downstream-ssr-strength'
    strength = $Strength
    diagnosticOnly = $true
    formula = 'combinedReflection = materialWeightedEnvironment * (1 - originalSSR.a) + originalSSR.rgb * diagnosticStrength'
    source = $hlslPath.Substring($repoRoot.Length + 1).Replace('\','/')
    sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hlslPath).Hash
    object = $objectPath.Substring($repoRoot.Length + 1).Replace('\','/')
    objectSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectPath).Hash
    assembly = $assemblyPath.Substring($repoRoot.Length + 1).Replace('\','/')
    assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assemblyPath).Hash
    comparisonBaseline = '0% downstream SSR composite'
    liveStatus = 'pending'
    runtimeAdapterEligible = $false
}
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Strength = $Strength
    Source = $hlslPath
    Object = $objectPath
    Manifest = $manifestPath
    SourceSha256 = $manifest.sourceSha256
    ObjectSha256 = $manifest.objectSha256
}
