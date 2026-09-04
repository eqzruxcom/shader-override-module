[CmdletBinding()]
param(
    [string]$SourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\captured-shaders\e2aa1c8cb39e0a55-ps\e2aa1c8cb39e0a55-ps_decompiled.txt'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-rebirth-fallback-consumer-candidate'),
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
if (-not (Test-Path -LiteralPath $FxcPath -PathType Leaf)) { throw "FXC was not found: $FxcPath" }
New-Item -ItemType Directory -Path $outputFull -Force | Out-Null

$baseName = 'RebirthFallbackAOConsumer_ps'
$hlslPath = Join-Path $outputFull "$baseName.hlsl"
$objectPath = Join-Path $outputFull "$baseName.cso"
$assemblyPath = Join-Path $outputFull "$baseName.asm"
$manifestPath = Join-Path $outputFull "$baseName.json"
$source = [IO.File]::ReadAllText($sourceFull)

$samplePattern = '(?m)^    r0\.x = t6\.SampleLevel\(s6_s, v0\.xy, 0\)\.x;$'
if ([regex]::Matches($source, $samplePattern).Count -ne 1) { throw 'Expected exactly one verified screen-AO t6 sample anchor.' }
$sampleReplacement = @'
    r0.x = t6.SampleLevel(s6_s, v0.xy, 0).x;
    // Rebirth native-SSAO fallback, preserved literally. The donor uses
    // (model != eye || model != hair), which is always true, so every model
    // receives the square before the donor's eye protection.
    r0.x = saturate(r0.x * r0.x);
    if ((int)r1.x == 9) {
      r0.x = lerp(r0.x, 1.0, 0.5);
    }
'@.TrimEnd()
$generated = [regex]::Replace($source, $samplePattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $sampleReplacement }, 1)

$materialPattern = @'
(?ms)^    r1\.y = r3\.w \* r0\.x;\r?\n    r1\.w = min\(r3\.w, r0\.x\);\r?\n    r2\.w = r3\.w \* r0\.x \+ 1;\r?\n    r2\.w = r2\.w \+ -r1\.w;\r?\n    r2\.w = r2\.w \* r2\.w;\r?\n    r0\.x = -r3\.w \* r0\.x \+ r1\.w;\r?\n    r0\.x = r2\.w \* r0\.x \+ r1\.y;$
'@.Trim()
if ([regex]::Matches($generated, $materialPattern).Count -ne 1) { throw 'Expected exactly one verified native screen-AO/material-AO combination anchor.' }
$materialMatch = [regex]::Match($generated, $materialPattern).Value
$materialReplacement = @"
$materialMatch
    // Rebirth fallback strengthens the combined ambient/material visibility
    // for preintegrated skin (3), hair (7), and eye (9) materials.
    if (r8.z != 0 || r8.w != 0 || (int)r1.x == 9) {
      r0.x = pow(saturate(r0.x), 1.75);
    }
"@.TrimEnd()
$generated = [regex]::Replace($generated, $materialPattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $materialReplacement }, 1)

foreach ($required in @('r11.w = 1 + -r11.w;','r2.xyz = r2.xyz * r11.www;','r2.xyz = r2.xyz * r0.www + r11.xyz;','r3.xyz = r3.xyz * r0.xxx;')) {
    if ([regex]::Matches($generated, [regex]::Escape($required)).Count -ne 1) { throw "Generated source does not preserve the verified reflection/AO contract: $required" }
}
[IO.File]::WriteAllText($hlslPath, $generated, [Text.UTF8Encoding]::new($false))

$compilerOutput = & $FxcPath /nologo /T ps_5_0 /E main /Ges /WX /O3 /Fo $objectPath /Fc $assemblyPath $hlslPath 2>&1
if ($LASTEXITCODE -ne 0) { throw "FXC failed for $baseName`n$($compilerOutput -join [Environment]::NewLine)" }

$assembly = [IO.File]::ReadAllText($assemblyPath)
foreach ($contract in @('(?m)^//\s+t6\s+texture\s+float4\s+2d\s+t6\s+1\s*$','(?m)^//\s+t10\s+texture\s+float4\s+cubearray\s+t10\s+1\s*$','(?m)^//\s+t11\s+texture\s+float4\s+2d\s+t11\s+1\s*$','(?m)^//\s+SV_Target\s+0\s+xyzw')) {
    if ($assembly -notmatch $contract) { throw "Compiled candidate is missing expected contract pattern: $contract" }
}
if ($assembly -notmatch '(?m)^\s*sample_l_indexable\(texture2d\).*t6\.') { throw 'Compiled candidate no longer samples screen AO at t6.' }
if ($assembly -notmatch '(?m)^\s*sample_l_indexable\(texturecubearray\).*t10\.') { throw 'Compiled candidate no longer samples the reflection environment at t10.' }
if ($assembly -notmatch '(?m)^\s*sample_l_indexable\(texture2d\).*t11\.') { throw 'Compiled candidate no longer samples SSR at t11.' }

$relative = { param([string]$Path) $Path.Substring($repoRoot.Length + 1).Replace('\','/') }
$manifest = [ordered]@{
    schemaVersion = 1
    adapter = 'FF7RemakeIntergrade'
    shaderHash = 'e2aa1c8cb39e0a55'
    stage = 'ps'
    effect = 'rebirth-native-ssao-fallback-consumer-adapter'
    donorFamily = 'ReflectionEnvironment'
    donorMode = 'native SSAO fallback only; not GTVB SSGI or bounce light'
    formulas = [ordered]@{
        screenAO = 'saturate(ScreenAO * ScreenAO)'
        eyeProtection = 'lerp(strengthenedScreenAO, 1.0, 0.5)'
        characterAmbientAO = 'pow(combinedScreenAndMaterialAO, 1.75) for shading models 3, 7, and 9'
    }
    literalDonorBehavior = 'The donor condition (model != eye || model != hair) is always true; this adapter intentionally preserves that behavior instead of silently changing it.'
    scope = 'reflection and indirect-light consumer only'
    preservedTerms = @('temporal SSAO producer and history','final screen-AO resource','five tiled direct-light consumers','native material-AO combine','native extra occlusion combine','GTAO multi-bounce coloring','specular-occlusion path','SSR radiance and hit alpha','reflection-environment fallback','output alpha')
    excluded = @('GTVB SSGI ray marching','SSGI bounce light','checkerboard reconstruction','capsule occlusion','contact shadows','direct-light AO')
    source = & $relative $hlslPath
    sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hlslPath).Hash
    object = & $relative $objectPath
    objectSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectPath).Hash
    assembly = & $relative $assemblyPath
    assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assemblyPath).Hash
    donorSource = 'reference/external/shader-injector-v2.2.1/maximum-quality/shader-injector-2-2-1-maximum-dood/ShaderInjector/ModifiedShaders/Includes/ComputeShaderPass_ReflectionEnvironment.hlsl'
    remakeEvidence = @('artifacts/captured-shaders/e2aa1c8cb39e0a55-ps/e2aa1c8cb39e0a55-ps_decompiled.txt','artifacts/captured-shaders/e2aa1c8cb39e0a55-ps/resource-flow-evidence.json')
    controlReservation = [ordered]@{ F1='AO Original/native'; F2='AO Balanced'; F3='AO Strong'; bindingsEmitted=$false }
    verification = 'strict-compiled deterministic offline candidate; live parity and visual validation pending'
    liveStatus = 'not-staged'
    runtimeAdapterEligible = $false
}
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Source=$hlslPath; Object=$objectPath; Assembly=$assemblyPath; Manifest=$manifestPath; SourceSha256=$manifest.sourceSha256; ObjectSha256=$manifest.objectSha256 }
