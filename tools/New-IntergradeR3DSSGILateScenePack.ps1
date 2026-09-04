[CmdletBinding()]
param(
    [string]$SourcePackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-native-composite-pack'),
    [string]$OriginalAssemblyPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\assembly\af6cd28a0108a18a-ps.asm'),
    [string]$OriginalBinaryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\dxbc\af6cd28a0108a18a-ps.bin'),
    [string]$AssemblerPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\shader-assembler-build\bin\cmd_Decompiler.exe'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-late-scene-pack')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifactsRoot = Join-Path $workspace 'artifacts'
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if (-not $output.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputRoot must remain below workspace artifacts.'
}
if (Test-Path -LiteralPath $output) {
    throw "OutputRoot already exists; preserve prior evidence: $output"
}

function Resolve-Leaf([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing: $Path" }
    (Resolve-Path -LiteralPath $Path).Path
}

function Resolve-Container([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "$Label is missing: $Path" }
    (Resolve-Path -LiteralPath $Path).Path
}

function Assert-One([string]$Text, [string]$Literal, [string]$Label) {
    $count = [regex]::Matches($Text, [regex]::Escape($Literal)).Count
    if ($count -ne 1) { throw "$Label must occur exactly once; found $count." }
}

function Invoke-Assembler([string[]]$Arguments, [string]$LogPath) {
    $messages = @(& $script:assembler @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    [IO.File]::WriteAllText($LogPath, ($messages | Out-String), [Text.UTF8Encoding]::new($false))
    if ($exitCode -ne 0) { throw "Shader assembler failed with exit code $exitCode; see $LogPath" }
}

$sourceRoot = Resolve-Container $SourcePackRoot 'Native e2aa source pack'
$sourceManifestPath = Resolve-Leaf (Join-Path $sourceRoot 'manifest.json') 'Source manifest'
$sourceManifest = Get-Content -Raw -LiteralPath $sourceManifestPath | ConvertFrom-Json
if ($sourceManifest.result -ne 'pass' -or $sourceManifest.variant -ne 'private-target-native-e2aa-writeback') {
    throw 'Source pack contract is invalid.'
}
$sourceMods = Resolve-Container (Join-Path $sourceRoot 'Mods') 'Source Mods payload'
$originalAssembly = Resolve-Leaf $OriginalAssemblyPath 'Original af6cd assembly'
$originalBinary = Resolve-Leaf $OriginalBinaryPath 'Original af6cd binary'
$script:assembler = Resolve-Leaf $AssemblerPath '3Dmigoto shader assembler'

$modsOutput = Join-Path $output 'Mods'
$shaderFixesOutput = Join-Path $output 'ShaderFixes'
$validationOutput = Join-Path $output 'validation'
[void][IO.Directory]::CreateDirectory($modsOutput)
[void][IO.Directory]::CreateDirectory($shaderFixesOutput)
[void][IO.Directory]::CreateDirectory($validationOutput)
Copy-Item -Path (Join-Path $sourceMods '*') -Destination $modsOutput

# af6cd binds the UE view buffer at b1 rather than e2aa's b0.
$rebasedShaders = 0
foreach ($shader in @(Get-ChildItem -LiteralPath $modsOutput -Filter '*.hlsl' -File)) {
    $text = [IO.File]::ReadAllText($shader.FullName)
    if ($text.Contains('cbuffer RemakeView : register(b0)')) {
        $text = $text.Replace('cbuffer RemakeView : register(b0)', 'cbuffer RemakeView : register(b1)')
        [IO.File]::WriteAllText($shader.FullName, $text, [Text.UTF8Encoding]::new($false))
        $rebasedShaders++
    }
}
if ($rebasedShaders -ne 6) { throw "Expected to rebase six SSGI shaders from b0 to b1; found $rebasedShaders." }

$iniPath = Join-Path $modsOutput 'Agent2R3DSSGITest.ini'
$ini = [IO.File]::ReadAllText($iniPath).Replace("`r`n", "`n")
$overridePattern = '(?ms)^\[ShaderOverrideAgent2R3DSSGIF2Test\]\n.*\z'
if ([regex]::Matches($ini, $overridePattern).Count -ne 1) { throw 'Could not isolate the source e2aa override.' }
$replacementOverrides = @'
[ShaderOverrideAgent2R3DSSGICaptureGBuffer]
hash = e2aa1c8cb39e0a55
allow_duplicate_hash = true
; Capture current-frame geometry only. Never read or write e2aa o0 here.
if $agent2_ssgi_test == 1
    ResourceAgent2SSGINormal = reference ps-t0
    ResourceAgent2SSGIDepth = reference ps-t5
    ResourceAgent2SSGIMaterial = reference ps-t1
    ResourceAgent2SSGIAlbedo = reference ps-t2
endif

[ShaderOverrideAgent2R3DSSGILateScene]
hash = af6cd28a0108a18a
allow_duplicate_hash = true
x30 = $agent2_ssgi_test
; af6cd t0 is the current resolved scene input. The private passes run before
; af6cd and the native af6cd shader performs the only writeback.
ResourceAgent2SSGIOriginalT110 = reference ps-t110
if $agent2_ssgi_test == 1
    ResourceAgent2SSGITarget = reference o0
    ResourceAgent2SSGIScene = reference ps-t0
    run = CustomShaderAgent2R3DSSGITrace
    run = CustomShaderAgent2R3DSSGIDenoise16
    run = CustomShaderAgent2R3DSSGIDenoise8
    run = CustomShaderAgent2R3DSSGIDenoise4
    run = CustomShaderAgent2R3DSSGIDenoise2
    run = CustomShaderAgent2R3DSSGIComposite
    ps-t110 = ResourceAgent2SSGICompositeScratch
endif
post ps-t110 = reference ResourceAgent2SSGIOriginalT110
'@.TrimEnd("`r", "`n")
$ini = [regex]::Replace($ini, $overridePattern, $replacementOverrides)
$ini = $ini.Replace('; Agent 2 native-draw R3D SSGI integration candidate. Offline only.', '; Agent 2 late-scene R3D SSGI integration candidate. Offline only.')
foreach ($forbidden in @('ResourceAgent2SSGIScene = copy o0', 'x30 = $agent2_ssgi_test`n; ISOLATION MATRIX')) {
    if ($ini.Contains($forbidden)) { throw "Feedback-era INI fragment survived: $forbidden" }
}
foreach ($required in @(
    '[ShaderOverrideAgent2R3DSSGICaptureGBuffer]',
    '[ShaderOverrideAgent2R3DSSGILateScene]',
    'hash = af6cd28a0108a18a',
    'ResourceAgent2SSGIScene = reference ps-t0',
    'ps-t110 = ResourceAgent2SSGICompositeScratch',
    'blend = disable'
)) {
    if (-not $ini.Contains($required)) { throw "Generated late-scene INI lacks: $required" }
}
[IO.File]::WriteAllText($iniPath, $ini.Replace("`n", "`r`n") + "`r`n", [Text.UTF8Encoding]::new($false))

$assembly = [IO.File]::ReadAllText($originalAssembly).Replace("`r`n", "`n")
if ($assembly -match '(?m)^dcl_resource_.* t110$' -or $assembly -match '(?m)^dcl_resource_.* t120$') {
    throw 'Original af6cd assembly already declares t110 or t120.'
}
Assert-One $assembly 'dcl_resource_texture2d (float,float,float,float) t2' 'Last original resource declaration'
Assert-One $assembly 'dcl_temps 11' 'Original temporary-register declaration'
$nativeWrite = "mov o0.xyz, r5.xyzx`nmov o0.w, l(0)"
Assert-One $assembly $nativeWrite 'Native af6cd output write'

$assembly = $assembly.Replace(
    'dcl_resource_texture2d (float,float,float,float) t2',
    "dcl_resource_texture2d (float,float,float,float) t2`n" +
    "dcl_resource_texture2d (float,float,float,float) t110`n" +
    'dcl_resource_texture1d (float,float,float,float) t120')
$assembly = $assembly.Replace('dcl_temps 11', 'dcl_temps 13')
$nativeComposite = @'
mov o0.xyz, r5.xyzx
ld_indexable(texture1d)(float,float,float,float) r11.x, l(30, 0, 0, 0), t120.xyzw
if_nz r11.x
  ftoi r11.xy, v1.xyxx
  mov r11.zw, l(0, 0, 0, 0)
  ld_indexable(texture2d)(float,float,float,float) r12.xyz, r11.xyzw, t110.xyzw
  add o0.xyz, o0.xyzx, r12.xyzx
endif
mov o0.w, l(0)
'@.TrimEnd("`r", "`n")
$assembly = $assembly.Replace($nativeWrite, $nativeComposite)
$assembly = "// Remake late-scene SSGI composite: current scene t0, private GI t110, F2 gate IniParams[30].x`n" + $assembly

$authoredAssembly = Join-Path $shaderFixesOutput 'af6cd28a0108a18a-ps.txt'
[IO.File]::WriteAllText($authoredAssembly, $assembly, [Text.UTF8Encoding]::new($false))
$validationAssembly = Join-Path $validationOutput 'af6cd28a0108a18a-ps.asm'
Copy-Item -LiteralPath $authoredAssembly -Destination $validationAssembly
Invoke-Assembler @('-a', '--copy-reflection', $originalBinary, $validationAssembly) (Join-Path $validationOutput 'assemble.log')
$assembledBinary = [IO.Path]::ChangeExtension($validationAssembly, '.shdr')
if (-not (Test-Path -LiteralPath $assembledBinary -PathType Leaf)) { throw 'Assembler produced no af6cd DXBC binary.' }
Copy-Item -LiteralPath $assembledBinary -Destination (Join-Path $validationOutput 'late-scene-composite.bin')
Invoke-Assembler @('-d', '-V', (Join-Path $validationOutput 'late-scene-composite.bin')) (Join-Path $validationOutput 'validate.log')
$verifiedAssemblyPath = Join-Path $validationOutput 'late-scene-composite.asm'
$verifiedAssembly = [IO.File]::ReadAllText($verifiedAssemblyPath).Replace("`r`n", "`n")
foreach ($required in @(
    'dcl_resource_texture2d (float,float,float,float) t110',
    'dcl_resource_texture1d (float,float,float,float) t120',
    'dcl_temps 13',
    'ld_indexable(texture1d)(float,float,float,float) r11.x, l(30, 0, 0, 0), t120.xyzw',
    'ld_indexable(texture2d)(float,float,float,float) r12.xyz, r11.xyzw, t110.xyzw',
    'add o0.xyz, o0.xyzx, r12.xyzx'
)) {
    if ($verifiedAssembly -notmatch [regex]::Escape($required)) { throw "Verified assembly is missing: $required" }
}

$payloadFiles = @(
    Get-ChildItem -LiteralPath $modsOutput -File
    Get-ChildItem -LiteralPath $shaderFixesOutput -File
) | Sort-Object FullName | ForEach-Object {
    [ordered]@{
        relativePath = [IO.Path]::GetRelativePath($output, $_.FullName).Replace('\', '/')
        bytes = $_.Length
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
}
$manifest = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    variant = 'late-scene-native-af6cd-writeback'
    purpose = 'Trace current-frame resolved scene color and add private GI during the existing native af6cd draw without reading any render target.'
    hooks = [ordered]@{
        geometryCapture = 'e2aa1c8cb39e0a55-ps'
        currentSceneAndWriteback = 'af6cd28a0108a18a-ps'
        pairedVertexShader = '1bf99472af1427ba-vs'
    }
    controls = [ordered]@{
        F2 = 'off/on for SSGI only'
        F10 = 'native reload, unchanged'
        PageUp = 'unchanged'
        PageDown = 'unchanged'
        iniParam = 'x30 / IniParams[30].x'
    }
    architecture = [ordered]@{
        currentScene = 'af6cd t0 SRV by reference'
        forbiddenFeedbackSource = 'no copy or reference from o0 as an SSGI input'
        geometry = 'captured by reference from earlier e2aa bindings'
        viewConstants = 'af6cd b1 UE view buffer'
        privatePasses = 'trace, four denoise stages, full-resolution private composite'
        nativeWriteback = 'af6cd replacement loads private GI from t110 and adds RGB'
        offPath = 'F2 zero skips private passes and native t110 load/add'
    }
    validation = [ordered]@{
        originalAssemblySha256 = (Get-FileHash -LiteralPath $originalAssembly -Algorithm SHA256).Hash
        originalBinarySha256 = (Get-FileHash -LiteralPath $originalBinary -Algorithm SHA256).Hash
        assemblerSha256 = (Get-FileHash -LiteralPath $script:assembler -Algorithm SHA256).Hash
        assembledBinarySha256 = (Get-FileHash -LiteralPath $assembledBinary -Algorithm SHA256).Hash
        dxbcValidationPassed = $true
        feedbackSourceAbsent = -not $ini.Contains('ResourceAgent2SSGIScene = copy o0')
        rebasedViewShaders = $rebasedShaders
    }
    payloadFiles = $payloadFiles
    runtimeEligible = $false
    installed = $false
    generatedUtc = [DateTime]::UtcNow.ToString('o')
}
$manifestPath = Join-Path $output 'manifest.json'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 10) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    OutputRoot = $output
    Manifest = $manifestPath
    PayloadFiles = $payloadFiles.Count
    NativeShader = $authoredAssembly
    ValidationPassed = $true
    FeedbackSourceAbsent = $manifest.validation.feedbackSourceAbsent
    RuntimeEligible = $false
}
