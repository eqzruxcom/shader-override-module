[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateRange(0.0, 1.0)]
    [double]$TargetSteadyState,

    [Parameter(Mandatory)]
    [string]$OutputHlsl,

    [string]$DescriptorPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Engine\UE4\PassDescriptors\volumetric-scattering-history-sm5.json'),
    [ValidateRange(0, 127)]
    [int]$SourceSrv = 113,
    [ValidateRange(0, 7)]
    [int]$OutputUav = 0,
    [switch]$Compile,
    [string]$FxcPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$descriptorFull = (Resolve-Path -LiteralPath $DescriptorPath).Path
$outputFull = [IO.Path]::GetFullPath($OutputHlsl)
if (-not $outputFull.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Output must stay inside the project workspace: $outputFull"
}

$descriptor = Get-Content -Raw -LiteralPath $descriptorFull | ConvertFrom-Json
$contract = $descriptor.runtimeContract
$currentWeight = [double]$contract.temporalCurrentWeight
$historyWeight = [double]$contract.temporalHistoryWeight
if ([Math]::Abs(($currentWeight + $historyWeight) - 1.0) -gt 0.000001) {
    throw "Temporal weights must sum to 1.0; got current=$currentWeight history=$historyWeight."
}
if ($currentWeight -le 0.0) {
    throw 'Temporal current weight must be greater than zero.'
}

$threadGroup = @($contract.verifiedThreadGroup)
if ($threadGroup.Count -ne 3 -or @($threadGroup | Where-Object { [int]$_ -lt 1 }).Count -ne 0) {
    throw 'Descriptor verifiedThreadGroup must contain three positive integers.'
}

$denominator = $currentWeight + ($historyWeight * $TargetSteadyState)
$perFrameScale = if ($TargetSteadyState -eq 0.0) { 0.0 } else { $TargetSteadyState / $denominator }
$scaleText = $perFrameScale.ToString('0.0000000000', [Globalization.CultureInfo]::InvariantCulture)
$targetText = $TargetSteadyState.ToString('0.##########', [Globalization.CultureInfo]::InvariantCulture)

$outputDirectory = Split-Path -Parent $outputFull
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$hlsl = @"
// Generated from $($descriptor.id).
// Target steady-state scattering: $targetText
// Per-frame scale: target / (currentWeight + historyWeight * target) = $scaleText

Texture3D<float4> RebirthFogSource : register(t$SourceSrv);
RWTexture3D<float4> RebirthFogOutput : register(u$OutputUav);

[numthreads($([int]$threadGroup[0]), $([int]$threadGroup[1]), $([int]$threadGroup[2]))]
void main(uint3 threadID : SV_DispatchThreadID)
{
    uint width, height, depth;
    RebirthFogOutput.GetDimensions(width, height, depth);
    if (any(threadID >= uint3(width, height, depth)))
        return;

    float4 value = RebirthFogSource.Load(int4(threadID, 0));
    RebirthFogOutput[threadID] = float4(value.xyz * $scaleText, value.w);
}
"@
[IO.File]::WriteAllText($outputFull, ($hlsl -replace "`r?`n", "`r`n"), [Text.UTF8Encoding]::new($false))

$manifest = [ordered]@{
    schemaVersion = 1
    descriptorId = [string]$descriptor.id
    descriptorSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $descriptorFull).Hash
    targetSteadyState = $TargetSteadyState
    temporalCurrentWeight = $currentWeight
    temporalHistoryWeight = $historyWeight
    perFrameScale = $perFrameScale
    threadGroup = @($threadGroup | ForEach-Object { [int]$_ })
    registers = [ordered]@{ sourceSrv = "t$SourceSrv"; outputUav = "u$OutputUav" }
    source = $outputFull
    sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputFull).Hash
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
}

if ($Compile) {
    if ([string]::IsNullOrWhiteSpace($FxcPath)) {
        $kitsRoot = 'C:\Program Files (x86)\Windows Kits\10\bin'
        $FxcPath = Get-ChildItem -LiteralPath $kitsRoot -Filter fxc.exe -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\x64\\fxc\.exe$' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if ([string]::IsNullOrWhiteSpace($FxcPath) -or -not (Test-Path -LiteralPath $FxcPath -PathType Leaf)) {
        throw 'FXC was requested but no x64 fxc.exe was found.'
    }

    $objectPath = [IO.Path]::ChangeExtension($outputFull, '.cso')
    $assemblyPath = [IO.Path]::ChangeExtension($outputFull, '.asm')
    $compilerOutput = & $FxcPath /nologo /T cs_5_0 /E main /Ges /WX /O3 /Fo $objectPath /Fc $assemblyPath $outputFull 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "FXC failed with exit code $LASTEXITCODE.`n$($compilerOutput -join [Environment]::NewLine)"
    }

    $assemblyText = [IO.File]::ReadAllText($assemblyPath)
    if ($assemblyText -notmatch "dcl_resource_texture3d.*t$SourceSrv" -or
        $assemblyText -notmatch "dcl_uav_typed.*u$OutputUav") {
        throw 'Compiled register contract did not match the requested SRV/UAV slots.'
    }
    $manifest.compiler = $FxcPath
    $manifest.profile = 'cs_5_0'
    $manifest.object = $objectPath
    $manifest.objectSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectPath).Hash
    $manifest.assembly = $assemblyPath
    $manifest.assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assemblyPath).Hash
}

$manifestPath = $outputFull + '.manifest.json'
[IO.File]::WriteAllText(
    $manifestPath,
    (($manifest | ConvertTo-Json -Depth 6) + [Environment]::NewLine),
    [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Source = $outputFull
    Manifest = $manifestPath
    TargetSteadyState = $TargetSteadyState
    PerFrameScale = $perFrameScale
    Compiled = [bool]$Compile
}
