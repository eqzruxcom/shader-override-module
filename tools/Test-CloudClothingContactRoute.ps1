[CmdletBinding()]
param(
    [string]$ClassificationPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Adapters\FF7RemakeIntergrade\verified-shader-classifications.json'),
    [string]$CaptureDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831'),
    [string]$LiveShaderDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\ShaderFixes',
    [string]$DiagnosticManifest = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\clothing-shader-ownership-diagnostic-20260831-v1\diagnostic-manifest.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$classification = Get-Content -Raw -LiteralPath $ClassificationPath | ConvertFrom-Json
$materialFamily = @($classification.families | Where-Object familyId -eq 'material-gbuffer-producers')
if ($materialFamily.Count -ne 1 -or '8b1f6ebe443b5615' -notin @($materialFamily[0].hashes.hash)) {
    throw 'Cloud clothing shader is not retained in the verified material/GBuffer family.'
}

$diagnostic = Get-Content -Raw -LiteralPath $DiagnosticManifest | ConvertFrom-Json
if ([string]$diagnostic.runtimeObservation.status -ne 'confirmed' -or
    [string]$diagnostic.shader -ne '8b1f6ebe443b5615-ps') {
    throw 'Live Cloud clothing ownership is not confirmed by the diagnostic manifest.'
}

$assemblyDirectory = Join-Path $CaptureDirectory 'assembly'
$clothing = Get-Content -Raw -LiteralPath (Join-Path $assemblyDirectory '8b1f6ebe443b5615-ps.asm')
$classifier = Get-Content -Raw -LiteralPath (Join-Path $assemblyDirectory 'f97a821dddaa328a-cs.asm')
$live62b = Get-Content -Raw -LiteralPath (Join-Path $LiveShaderDirectory '62b33a2d1e505241-cs.txt')

foreach ($motif in @(
    'and r1.w, r1.w, l(32)',
    'movc r7.yz, r7.yyzy, l(0,64,128,0)',
    'iadd r1.x, r1.w, l(1)',
    'mul o2.w, r1.x, l(0.003922)'
)) {
    if (-not $clothing.Contains($motif)) { throw "Clothing GBuffer packing motif is missing: $motif" }
}

foreach ($motif in @(
    'mad r0.y, r0.y, l(255.000000), l(0.500000)',
    'and r0.y, r0.y, l(15)',
    'ieq r0.z, r0.y, l(1)',
    'mov r0.z, l(1)'
)) {
    if (-not $classifier.Contains($motif)) { throw "Tile classifier route motif is missing: $motif" }
}

foreach ($motif in @(
    'iadd r0.x, vThreadGroupID.x, l(0x00008700)',
    'mov r25.x, r27.y',
    'mul r18.xyz, r18.xyzw, r25.xxxx',
    'mul r17.yzw, r17.xyzw, r25.xxxx'
)) {
    if (-not $live62b.Contains($motif)) { throw "62b contact application motif is missing: $motif" }
}

Write-Host 'PASS: live-confirmed Cloud clothing structurally routes from GBuffer material ID 1 to the 62b contact-shadow specialization and both final lighting groups.'
