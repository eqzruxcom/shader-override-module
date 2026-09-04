[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('RawRgb', 'AmplifiedRgb', 'HitMask', 'RadianceMask')]
    [string]$Mode,
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ssr-composite-probes'),
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
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full)) {
        throw "Path does not exist: $full"
    }
    $full
}

$outputFull = Resolve-WorkspacePath $OutputDirectory -AllowMissing
New-Item -ItemType Directory -Path $outputFull -Force | Out-Null
if (-not (Test-Path -LiteralPath $FxcPath -PathType Leaf)) { throw "FXC was not found: $FxcPath" }

$modeBody = switch ($Mode) {
    'RawRgb' {
@'
    float3 rgb = max(ssr.rgb, 0.0);
    return float4(rgb, 1.0);
'@
    }
    'AmplifiedRgb' {
@'
    float3 rgb = saturate(max(ssr.rgb, 0.0) * 16.0);
    return float4(rgb, 1.0);
'@
    }
    'HitMask' {
@'
    float hit = saturate(ssr.a);
    return float4(hit, hit, hit, 1.0);
'@
    }
    'RadianceMask' {
@'
    float luminance = dot(abs(ssr.rgb), float3(0.2126, 0.7152, 0.0722));
    float present = luminance >= 0.00001 ? 1.0 : 0.0;
    return float4(0.0, present, present, 1.0);
'@
    }
}

$baseName = "RebirthSSRComposite$($Mode)_ps"
$hlslPath = Join-Path $outputFull "$baseName.hlsl"
$objectPath = Join-Path $outputFull "$baseName.cso"
$assemblyPath = Join-Path $outputFull "$baseName.asm"
$manifestPath = Join-Path $outputFull "$baseName.json"

$hlsl = @"
// Diagnostic replacement for FF7 Remake Intergrade ps:e2aa1c8cb39e0a55.
// t11 is proven by frame capture to be the exact o0 handle written by
// ps:b2bc6059f9a39c7f on the immediately preceding draw.
Texture2D<float4> SsrBuffer : register(t11);
SamplerState SsrSampler : register(s9);

float4 main(float4 texcoord : TEXCOORD0) : SV_Target0
{
    float4 ssr = SsrBuffer.SampleLevel(SsrSampler, texcoord.xy, 0.0);
$modeBody
}
"@
[IO.File]::WriteAllText($hlslPath, $hlsl, [Text.UTF8Encoding]::new($false))

$compilerOutput = & $FxcPath /nologo /T ps_5_0 /E main /Ges /WX /O3 /Fo $objectPath /Fc $assemblyPath $hlslPath 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "FXC failed for $baseName`n$($compilerOutput -join [Environment]::NewLine)"
}

$assembly = [IO.File]::ReadAllText($assemblyPath)
if ($assembly -notmatch '(?m)^//\s+SsrBuffer\s+texture\s+float4\s+2d\s+t11\s+1\s*$') {
    throw 'Compiled probe is missing the SsrBuffer texture at t11.'
}
if ($assembly -notmatch '(?m)^//\s+SsrSampler\s+sampler\s+NA\s+NA\s+s9\s+1\s*$') {
    throw 'Compiled probe is missing the SsrSampler binding at s9.'
}
if ($assembly -notmatch '(?m)^//\s+SV_Target\s+0\s+xyzw') { throw 'Compiled probe is missing SV_Target0.' }
if ($assembly -notmatch '(?m)^\s*sample_l_indexable\(texture2d\)') { throw 'Compiled probe does not sample the SSR buffer.' }

$manifest = [ordered]@{
    schemaVersion = 1
    adapter = 'FF7RemakeIntergrade'
    shaderHash = 'e2aa1c8cb39e0a55'
    stage = 'ps'
    effect = 'downstream-ssr-buffer-diagnostic'
    mode = $Mode
    producerShader = 'b2bc6059f9a39c7f'
    sourceSlot = 't11'
    sourceResourceHash = '36f63b9f'
    resourceFlowEvidence = 'artifacts/captured-shaders/e2aa1c8cb39e0a55-ps/resource-flow-evidence.json'
    source = $hlslPath.Substring($repoRoot.Length + 1).Replace('\','/')
    sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hlslPath).Hash
    object = $objectPath.Substring($repoRoot.Length + 1).Replace('\','/')
    objectSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectPath).Hash
    assembly = $assemblyPath.Substring($repoRoot.Length + 1).Replace('\','/')
    assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assemblyPath).Hash
    verification = 'strict-compile-diagnostic-only'
    liveStatus = 'pending'
}
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Mode = $Mode
    Source = $hlslPath
    Object = $objectPath
    Manifest = $manifestPath
    SourceSha256 = $manifest.sourceSha256
    ObjectSha256 = $manifest.objectSha256
}
