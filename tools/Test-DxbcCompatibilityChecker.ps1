[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$toolRoot = Join-Path $root 'artifacts\dxbc-compatibility-tool'
$build = & (Join-Path $PSScriptRoot 'Build-DxbcCompatibilityChecker.ps1') -OutputDirectory $toolRoot
$checker = [string]$build.Executable
$fxc = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
if (-not (Test-Path -LiteralPath $fxc -PathType Leaf)) { throw "Missing FXC: $fxc" }

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$work = Join-Path $tempRoot ('ue4fx-dxbc-contract-test-' + [guid]::NewGuid().ToString('N'))
$utf8 = [Text.UTF8Encoding]::new($false)

function Compile-Fixture([string]$Name, [string]$Profile, [string]$Source) {
    $hlsl = Join-Path $work ($Name + '.hlsl')
    $bin = Join-Path $work ($Name + '.bin')
    [IO.File]::WriteAllText($hlsl, $Source.Trim() + [Environment]::NewLine, $utf8)
    $messages = & $fxc /nologo /Ges /Gis /WX /O3 /T $Profile /E main /Fo $bin $hlsl 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $messages | Write-Host
        throw "FXC failed for fixture $Name"
    }
    return $bin
}

function Assert-Compatible([string]$Original, [string]$Replacement) {
    & $checker $Original $Replacement
    if ($LASTEXITCODE -ne 0) { throw "Expected compatibility: $Original -> $Replacement" }
}

function Assert-Incompatible([string]$Original, [string]$Replacement, [string]$Label, [string]$ExpectedDiagnostic) {
    $messages = & $checker $Original $Replacement 2>&1
    if ($LASTEXITCODE -ne 2) { throw "Expected incompatibility ($Label), got exit $LASTEXITCODE`: $messages" }
    if($ExpectedDiagnostic -and ($messages -join [Environment]::NewLine) -notmatch [regex]::Escape($ExpectedDiagnostic)){throw "Missing detailed diagnostic '$ExpectedDiagnostic' for $Label`: $messages"}
    Write-Host "PASS: rejected $Label."
}

try {
    [IO.Directory]::CreateDirectory($work) | Out-Null
    $originalPs = Compile-Fixture 'original-ps' 'ps_5_0' @'
cbuffer Params : register(b0) { float4 Tint; float2 Scale; float2 Padding; };
Texture2D<float4> InputTexture : register(t0);
SamplerState InputSampler : register(s0);
float4 main(float2 uv : TEXCOORD0) : SV_Target0 {
  return InputTexture.SampleLevel(InputSampler, uv * Scale, 0) * Tint;
}
'@
    $compatiblePs = Compile-Fixture 'compatible-ps' 'ps_5_0' @'
cbuffer Params : register(b0) { float4 Tint; float2 Scale; float2 Padding; };
Texture2D<float4> InputTexture : register(t0);
SamplerState InputSampler : register(s0);
float4 main(float2 uv : TEXCOORD0) : SV_Target0 {
  return saturate(InputTexture.SampleLevel(InputSampler, uv * Scale, 0) + Tint);
}
'@
    $resourceMismatch = Compile-Fixture 'resource-mismatch-ps' 'ps_5_0' @'
cbuffer Params : register(b0) { float4 Tint; float2 Scale; float2 Padding; };
Texture3D<float4> InputTexture : register(t0);
SamplerState InputSampler : register(s0);
float4 main(float2 uv : TEXCOORD0) : SV_Target0 {
  return InputTexture.SampleLevel(InputSampler, float3(uv * Scale, 0.5), 0) * Tint;
}
'@
    $cbufferMismatch = Compile-Fixture 'cbuffer-mismatch-ps' 'ps_5_0' @'
cbuffer Params : register(b0) { float4 Tint; float4 ScaleAndPadding; };
Texture2D<float4> InputTexture : register(t0);
SamplerState InputSampler : register(s0);
float4 main(float2 uv : TEXCOORD0) : SV_Target0 {
  return InputTexture.SampleLevel(InputSampler, uv * ScaleAndPadding.xy, 0) * Tint;
}
'@
    $signatureMismatch = Compile-Fixture 'signature-mismatch-ps' 'ps_5_0' @'
cbuffer Params : register(b0) { float4 Tint; float2 Scale; float2 Padding; };
Texture2D<float4> InputTexture : register(t0);
SamplerState InputSampler : register(s0);
float4 main(float2 uv : TEXCOORD1) : SV_Target0 {
  return InputTexture.SampleLevel(InputSampler, uv * Scale, 0) * Tint;
}
'@
    $compute8 = Compile-Fixture 'compute-8' 'cs_5_0' @'
RWTexture2D<float4> Output : register(u0);
[numthreads(8, 8, 1)] void main(uint3 id : SV_DispatchThreadID) { Output[id.xy] = 1.0; }
'@
    $compute16 = Compile-Fixture 'compute-16' 'cs_5_0' @'
RWTexture2D<float4> Output : register(u0);
[numthreads(16, 8, 1)] void main(uint3 id : SV_DispatchThreadID) { Output[id.xy] = 1.0; }
'@

    Assert-Compatible $originalPs $compatiblePs
    Assert-Incompatible $originalPs $resourceMismatch 'resource dimension mismatch' 'original resources'
    Assert-Incompatible $originalPs $cbufferMismatch 'same-size but different constant-buffer member layout' 'original constant buffers'
    Assert-Incompatible $originalPs $signatureMismatch 'input semantic mismatch' 'original inputs'
    Assert-Incompatible $compute8 $compute16 'compute thread-group mismatch' 'original thread group'
    Write-Host 'PASS: DXBC reflection compatibility checker accepts changed math and rejects contract changes.'
}
finally {
    if (Test-Path -LiteralPath $work) {
        $resolvedWork = [IO.Path]::GetFullPath($work)
        $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
        if (-not $resolvedWork.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Split-Path -Leaf $resolvedWork).StartsWith('ue4fx-dxbc-contract-test-')) {
            throw "Refusing to remove unexpected test path: $resolvedWork"
        }
        Remove-Item -LiteralPath $resolvedWork -Recurse -Force
    }
}
