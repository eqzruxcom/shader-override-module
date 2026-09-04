[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('0', '0.25', '0.5', '0.75', '1')]
    [string]$Strength,
    [string]$SourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\captured-shaders\e2aa1c8cb39e0a55-ps\e2aa1c8cb39e0a55-ps_decompiled.txt'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ssr-composite-strength-variants'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')

function Resolve-WorkspacePath([string]$Path, [switch]$AllowMissing) {
    $full = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    } else {
        [IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
    }
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must remain inside the project workspace: $full"
    }
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "File does not exist: $full"
    }
    $full
}

$sourceFull = Resolve-WorkspacePath $SourcePath
$outputFull = Resolve-WorkspacePath $OutputDirectory -AllowMissing
New-Item -ItemType Directory -Path $outputFull -Force | Out-Null
if (-not (Test-Path -LiteralPath $FxcPath -PathType Leaf)) { throw "FXC was not found: $FxcPath" }

$strengthValue = [double]::Parse($Strength, [Globalization.CultureInfo]::InvariantCulture)
$level = [int][Math]::Round($strengthValue * 100)
$levelName = $level.ToString('000', [Globalization.CultureInfo]::InvariantCulture)
$hlslLiteral = $strengthValue.ToString('0.0###', [Globalization.CultureInfo]::InvariantCulture)
$baseName = "RebirthSSRCompositeStrength$($levelName)_ps"
$hlslPath = Join-Path $outputFull "$baseName.hlsl"
$objectPath = Join-Path $outputFull "$baseName.cso"
$assemblyPath = Join-Path $outputFull "$baseName.asm"
$manifestPath = Join-Path $outputFull "$baseName.json"

$replacement = @"
    // Control only the additive SSR radiance term. The existing r11.w path
    // continues to weight reflection-environment fallback by 1 - SSR alpha.
    float ssrCompositeStrength = $hlslLiteral;
    r2.xyz = r2.xyz * r0.www + r11.xyz * ssrCompositeStrength;
"@.TrimEnd()
$source = [IO.File]::ReadAllText($sourceFull)
$pattern = '(?m)^    r2\.xyz = r2\.xyz \* r0\.www \+ r11\.xyz;$'
$matches = [regex]::Matches($source, $pattern)
if ($matches.Count -ne 1) { throw "Expected exactly one additive SSR composition assignment, found $($matches.Count)." }
$generated = [regex]::Replace($source, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement }, 1)
foreach ($required in @(
    'r11.w = 1 + -r11.w;',
    'r2.xyz = r2.xyz * r11.www;')) {
    if ([regex]::Matches($generated, [regex]::Escape($required)).Count -ne 1) {
        throw "Generated source does not preserve the required fallback expression: $required"
    }
}
[IO.File]::WriteAllText($hlslPath, $generated, [Text.UTF8Encoding]::new($false))

$compilerOutput = & $FxcPath /nologo /T ps_5_0 /E main /Ges /WX /O3 /Fo $objectPath /Fc $assemblyPath $hlslPath 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "FXC failed for $baseName`n$($compilerOutput -join [Environment]::NewLine)"
}

$assembly = [IO.File]::ReadAllText($assemblyPath)
foreach ($contract in @(
    '(?m)^//\s+t11\s+texture\s+float4\s+2d\s+t11\s+1\s*$',
    '(?m)^//\s+t10\s+texture\s+float4\s+cubearray\s+t10\s+1\s*$',
    '(?m)^//\s+SV_Target\s+0\s+xyzw')) {
    if ($assembly -notmatch $contract) { throw "Compiled variant is missing expected contract pattern: $contract" }
}
if ($assembly -notmatch '(?m)^\s*sample_l_indexable\(texturecubearray\)') {
    throw 'Compiled variant no longer samples the reflection-environment cube array.'
}
if ($assembly -notmatch '(?m)^\s*sample_l_indexable\(texture2d\).*t11\.') {
    throw 'Compiled variant no longer samples the SSR buffer at t11.'
}

$manifest = [ordered]@{
    schemaVersion = 1
    adapter = 'FF7RemakeIntergrade'
    shaderHash = 'e2aa1c8cb39e0a55'
    stage = 'ps'
    effect = 'downstream-screen-space-reflection-strength'
    strength = $strengthValue
    formula = 'combinedReflection = materialWeightedEnvironment * (1 - originalSSR.a) + originalSSR.rgb * strength'
    controlledTerm = 'additive SSR radiance RGB'
    preservedTerms = @('SSR hit/confidence alpha', 'reflection-environment radiance', 'material and BRDF weighting', 'composite output alpha')
    source = $hlslPath.Substring($repoRoot.Length + 1).Replace('\','/')
    sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hlslPath).Hash
    object = $objectPath.Substring($repoRoot.Length + 1).Replace('\','/')
    objectSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectPath).Hash
    assembly = $assemblyPath.Substring($repoRoot.Length + 1).Replace('\','/')
    assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assemblyPath).Hash
    resourceFlowEvidence = 'artifacts/captured-shaders/e2aa1c8cb39e0a55-ps/resource-flow-evidence.json'
    verification = 'strict-compile-full-replacement-neutral-live-parity-pending'
    liveStatus = 'pending'
    runtimeAdapterEligible = $false
}
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 10) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Strength = $strengthValue
    Source = $hlslPath
    Object = $objectPath
    Manifest = $manifestPath
    SourceSha256 = $manifest.sourceSha256
    ObjectSha256 = $manifest.objectSha256
}
