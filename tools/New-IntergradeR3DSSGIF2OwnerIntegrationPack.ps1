[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-owner-integration-pack'),
    [string]$OwnerIni = (Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime\Intergrade\Mods\RebirthEffectsDX11.ini'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$expectedOwnerSha256 = 'EFA15E2A820D6CEE6A919AD3B14B736A8ED428B9C779693FF832479B2CC40ECD'
$traceSource = Join-Path $root 'src\Adapters\FF7RemakeIntergrade\R3DSSGITraceE2AA_ps.hlsl'
$denoiseSource = Join-Path $root 'src\Effects\Lighting\R3DSSGIDenoise_SM5.hlsl'
$compositeSource = Join-Path $root 'src\Adapters\FF7RemakeIntergrade\R3DSSGICompositeE2AA_ps.hlsl'
$analysisPath = Join-Path $root 'artifacts\analysis\agent2-r3d-ssgi-injection.json'
$analyzer = Join-Path $root 'tools\Analyze-IntergradeR3DSSGIInjection.ps1'
$samplingVerifier = Join-Path $root 'tools\Test-IntergradeR3DSSGISamplingSemantics.ps1'

foreach ($required in @($OwnerIni, $FxcPath, $traceSource, $denoiseSource, $compositeSource, $analyzer, $samplingVerifier)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required pack input is missing: $required" }
}

$ownerFull = [IO.Path]::GetFullPath($OwnerIni)
$ownerHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ownerFull).Hash
if ($ownerHash -ne $expectedOwnerSha256) {
    throw "Shared runtime owner drifted. Expected $expectedOwnerSha256, found $ownerHash. Refusing to merge F2."
}
$owner = Get-Content -Raw -LiteralPath $ownerFull
if ($owner -match '(?im)^\s*key\s*=\s*(?:no_modifiers\s+)?F2\s*$') { throw 'F2 is already owned; refusing to emit a conflicting pack.' }
if ($owner -notmatch '(?m)^\[ShaderOverrideRebirthABShared\]\r?$' -or $owner -notmatch '(?m)^hash = e2aa1c8cb39e0a55\r?$') {
    throw 'Expected e2aa shared owner block is absent.'
}

& $analyzer -OutputPath $analysisPath | Out-Null
$analysis = Get-Content -Raw -LiteralPath $analysisPath | ConvertFrom-Json
if ($analysis.result -ne 'pass' -or $analysis.gates.runtimeEligible) { throw 'Injection evidence did not remain fail-closed.' }

$outputFull = [IO.Path]::GetFullPath($OutputDirectory)
$mods = Join-Path $outputFull 'Mods'
$compiled = Join-Path $outputFull 'compiled'
[IO.Directory]::CreateDirectory($mods) | Out-Null
[IO.Directory]::CreateDirectory($compiled) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)

$runtimeSources = [ordered]@{
    'Agent2R3DSSGITraceE2AA_ps.hlsl' = Get-Content -Raw -LiteralPath $traceSource
    'Agent2R3DSSGICompositeE2AA_ps.hlsl' = Get-Content -Raw -LiteralPath $compositeSource
}
foreach ($step in @(16, 8, 4, 2)) {
    $runtimeSources["Agent2R3DSSGIDenoise${step}_ps.hlsl"] = "#define AGENT2_ATROUS_STEP $step`r`n" + (Get-Content -Raw -LiteralPath $denoiseSource)
}
foreach ($item in $runtimeSources.GetEnumerator()) {
    [IO.File]::WriteAllText((Join-Path $mods $item.Key), $item.Value, $utf8)
}

$compileRecords = [Collections.Generic.List[object]]::new()
function Compile-Shader([string]$Name, [string]$Source, [string[]]$Defines) {
    $objectPath = Join-Path $compiled ($Name + '.obj')
    $assemblyPath = Join-Path $compiled ($Name + '.asm')
    $arguments = @('/nologo', '/T', 'ps_5_0', '/E', 'main', '/Ges', '/WX', '/O3')
    foreach ($define in $Defines) { $arguments += @('/D', $define) }
    $arguments += @('/Fo', $objectPath, '/Fc', $assemblyPath, $Source)
    $messages = & $FxcPath @arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "FXC failed for $Name`: $($messages -join ' ')" }
    $bytes = [IO.File]::ReadAllBytes($objectPath)
    if ($bytes.Length -lt 4 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'DXBC') { throw "$Name is not DXBC." }
    $compileRecords.Add([ordered]@{
        name = $Name
        profile = 'ps_5_0'
        objectSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectPath).Hash
        assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assemblyPath).Hash
    })
}

Compile-Shader 'Agent2R3DSSGITraceE2AA_ps' $traceSource @()
foreach ($step in @(16, 8, 4, 2)) { Compile-Shader "Agent2R3DSSGIDenoise${step}_ps" $denoiseSource @("AGENT2_ATROUS_STEP=$step") }
Compile-Shader 'Agent2R3DSSGICompositeE2AA_ps' $compositeSource @()
$samplingEvidencePath = Join-Path $outputFull 'evidence\sampling-semantics.json'
& $samplingVerifier -CompiledDirectory $compiled -OutputPath $samplingEvidencePath | Out-Null
$samplingEvidence = Get-Content -Raw -LiteralPath $samplingEvidencePath | ConvertFrom-Json
if ($samplingEvidence.result -ne 'pass' -or $samplingEvidence.gates.runtimeEligible) { throw 'Sampling evidence did not remain fail-closed.' }

$injectedConstants = "global `$agent2_ssgi_test = 0`r`n"
$owner = $owner -replace '(?m)^(\[Constants\]\r?\n)', ('$1' + $injectedConstants)

$keyBlock = @'

; AGENT 2 R3D SSGI F2 TEST BEGIN
; F2 toggles only this offline strong indirect-bounce candidate.
; F1 remains reserved for the future global switch. F3 remains rolling A/B.
[KeyAgent2R3DSSGITest]
key = no_modifiers F2
type = cycle
smart = true
$agent2_ssgi_test = 0, 1

[ResourceAgent2SSGITarget]
[ResourceAgent2SSGIScene]
[ResourceAgent2SSGINormal]
[ResourceAgent2SSGIDepth]
[ResourceAgent2SSGIMaterial]
[ResourceAgent2SSGIAlbedo]
[ResourceAgent2SSGIOriginalT110]
[ResourceAgent2SSGIOriginalT111]
[ResourceAgent2SSGIOriginalT112]
[ResourceAgent2SSGIOriginalT113]
[ResourceAgent2SSGIOriginalT114]
[ResourceAgent2SSGIPing]
width_multiply = 0.5
height_multiply = 0.5
[ResourceAgent2SSGIPong]
width_multiply = 0.5
height_multiply = 0.5

[CustomShaderAgent2R3DSSGITrace]
ps = Agent2R3DSSGITraceE2AA_ps.hlsl
sampler = linear_filter
blend = disable
run = BuiltInCommandListUnbindAllRenderTargets
ResourceAgent2SSGIPing = copy_desc ResourceAgent2SSGITarget
o0 = set_viewport ResourceAgent2SSGIPing
ps-t110 = ResourceAgent2SSGIScene
ps-t111 = ResourceAgent2SSGINormal
ps-t112 = ResourceAgent2SSGIDepth
draw = from_caller
post ps-t110 = null
post ps-t111 = null
post ps-t112 = null

[CustomShaderAgent2R3DSSGIDenoise16]
ps = Agent2R3DSSGIDenoise16_ps.hlsl
sampler = linear_filter
blend = disable
run = BuiltInCommandListUnbindAllRenderTargets
ResourceAgent2SSGIPong = copy_desc ResourceAgent2SSGIPing
o0 = set_viewport ResourceAgent2SSGIPong
ps-t110 = ResourceAgent2SSGIPing
ps-t111 = ResourceAgent2SSGINormal
ps-t112 = ResourceAgent2SSGIDepth
draw = from_caller
post ps-t110 = null
post ps-t111 = null
post ps-t112 = null

[CustomShaderAgent2R3DSSGIDenoise8]
ps = Agent2R3DSSGIDenoise8_ps.hlsl
sampler = linear_filter
blend = disable
run = BuiltInCommandListUnbindAllRenderTargets
o0 = set_viewport ResourceAgent2SSGIPing
ps-t110 = ResourceAgent2SSGIPong
ps-t111 = ResourceAgent2SSGINormal
ps-t112 = ResourceAgent2SSGIDepth
draw = from_caller
post ps-t110 = null
post ps-t111 = null
post ps-t112 = null

[CustomShaderAgent2R3DSSGIDenoise4]
ps = Agent2R3DSSGIDenoise4_ps.hlsl
sampler = linear_filter
blend = disable
run = BuiltInCommandListUnbindAllRenderTargets
o0 = set_viewport ResourceAgent2SSGIPong
ps-t110 = ResourceAgent2SSGIPing
ps-t111 = ResourceAgent2SSGINormal
ps-t112 = ResourceAgent2SSGIDepth
draw = from_caller
post ps-t110 = null
post ps-t111 = null
post ps-t112 = null

[CustomShaderAgent2R3DSSGIDenoise2]
ps = Agent2R3DSSGIDenoise2_ps.hlsl
sampler = linear_filter
blend = disable
run = BuiltInCommandListUnbindAllRenderTargets
o0 = set_viewport ResourceAgent2SSGIPing
ps-t110 = ResourceAgent2SSGIPong
ps-t111 = ResourceAgent2SSGINormal
ps-t112 = ResourceAgent2SSGIDepth
draw = from_caller
post ps-t110 = null
post ps-t111 = null
post ps-t112 = null

[CustomShaderAgent2R3DSSGIComposite]
ps = Agent2R3DSSGICompositeE2AA_ps.hlsl
sampler = linear_filter
blend = ADD ONE ONE
run = BuiltInCommandListUnbindAllRenderTargets
o0 = set_viewport ResourceAgent2SSGITarget
ps-t110 = ResourceAgent2SSGIPing
ps-t111 = ResourceAgent2SSGINormal
ps-t112 = ResourceAgent2SSGIDepth
ps-t113 = ResourceAgent2SSGIMaterial
ps-t114 = ResourceAgent2SSGIAlbedo
draw = from_caller
post ps-t110 = null
post ps-t111 = null
post ps-t112 = null
post ps-t113 = null
post ps-t114 = null
; AGENT 2 R3D SSGI F2 TEST END

'@
$owner = $owner -replace '(?m)^; REDX11 ROLLING AB BEGIN\r?$', ($keyBlock + '; REDX11 ROLLING AB BEGIN')

$overrideInjection = @'
if $agent2_ssgi_test == 1
    ResourceAgent2SSGIOriginalT110 = reference ps-t110
    ResourceAgent2SSGIOriginalT111 = reference ps-t111
    ResourceAgent2SSGIOriginalT112 = reference ps-t112
    ResourceAgent2SSGIOriginalT113 = reference ps-t113
    ResourceAgent2SSGIOriginalT114 = reference ps-t114
    ResourceAgent2SSGITarget = reference o0
    ResourceAgent2SSGINormal = reference ps-t0
    ResourceAgent2SSGIDepth = reference ps-t5
    ResourceAgent2SSGIMaterial = reference ps-t1
    ResourceAgent2SSGIAlbedo = reference ps-t2
    ResourceAgent2SSGIScene = copy o0
    run = CustomShaderAgent2R3DSSGITrace
    run = CustomShaderAgent2R3DSSGIDenoise16
    run = CustomShaderAgent2R3DSSGIDenoise8
    run = CustomShaderAgent2R3DSSGIDenoise4
    run = CustomShaderAgent2R3DSSGIDenoise2
    run = CustomShaderAgent2R3DSSGIComposite
    ps-t110 = reference ResourceAgent2SSGIOriginalT110
    ps-t111 = reference ResourceAgent2SSGIOriginalT111
    ps-t112 = reference ResourceAgent2SSGIOriginalT112
    ps-t113 = reference ResourceAgent2SSGIOriginalT113
    ps-t114 = reference ResourceAgent2SSGIOriginalT114
endif
'@
$owner = $owner -replace '(?m)^(\[ShaderOverrideRebirthABShared\]\r?\nhash = e2aa1c8cb39e0a55\r?\nallow_duplicate_hash = true\r?\n)', ('$1' + $overrideInjection + [Environment]::NewLine)
$mergedIniPath = Join-Path $mods 'RebirthEffectsDX11.ini'
[IO.File]::WriteAllText($mergedIniPath, $owner, $utf8)

$manifest = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    classification = 'offline-f2-owner-integration-candidate'
    target = [ordered]@{ shader = 'e2aa1c8cb39e0a55'; event = 1096; ownerIniSha256 = $ownerHash }
    effect = [ordered]@{ algorithm = 'altered R3D horizon SSGI'; resolution = 'half'; unrealUnitsToMeters = 0.01; depthClear = 0.0; depthConvention = 'captured reversed-Z'; sampling = 'point receiver depth; linear trace neighbors/radiance; point A-trous taps'; denoiseSteps = @(16, 8, 4, 2); upsample = 'four-tap reconstructed-depth bilateral, 0.05 meter tolerance'; receiverDiffuse = 'e2aa t2.rgb * (1 - e2aa t1.x metallic) / pi'; composite = 'HDR additive'; diagnosticStrength = 1.25; highSrvSlotsRestored = @(110, 111, 112, 113, 114) }
    controls = [ordered]@{ F1 = 'reserved future global switch'; F2 = 'this SSGI candidate off/on'; F3 = 'preserved rolling A/B' }
    compile = @($compileRecords)
    files = @((Get-ChildItem -LiteralPath $mods -File | Sort-Object Name | ForEach-Object { [ordered]@{ path = 'Mods\' + $_.Name; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash } }))
    evidence = [ordered]@{ architecture = [IO.Path]::GetRelativePath($root, $analysisPath); sampling = [IO.Path]::GetRelativePath($outputFull, $samplingEvidencePath) }
    policy = [ordered]@{ exactOwnerRequired = $true; runtimeEligible = $false; installed = $false; gameFilesTouched = $false; liveCaptureRequired = $true }
}
$manifestPath = Join-Path $outputFull 'manifest.json'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 10) + [Environment]::NewLine, $utf8)

[pscustomobject]@{
    result = 'pass'
    output = $outputFull
    shadersCompiled = $compileRecords.Count
    ownerIniSha256 = $ownerHash
    runtimeEligible = $false
    installed = $false
}
