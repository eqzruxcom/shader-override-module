[CmdletBinding()]
param(
    [string]$PrivatePackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-private-target-zero-pack'),
    [string]$RealPackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-real-pack'),
    [string]$OriginalAssemblyPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\assembly\e2aa1c8cb39e0a55-ps.asm'),
    [string]$OriginalBinaryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\dxbc\e2aa1c8cb39e0a55-ps.bin'),
    [string]$AssemblerPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\shader-assembler-build\bin\cmd_Decompiler.exe'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-native-composite-pack')
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
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label is missing: $Path"
    }
    (Resolve-Path -LiteralPath $Path).Path
}

function Resolve-Container([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label is missing: $Path"
    }
    (Resolve-Path -LiteralPath $Path).Path
}

function Assert-One([string]$Text, [string]$Literal, [string]$Label) {
    $count = [regex]::Matches($Text, [regex]::Escape($Literal)).Count
    if ($count -ne 1) {
        throw "$Label must occur exactly once; found $count."
    }
}

function Invoke-Assembler([string[]]$Arguments, [string]$LogPath) {
    $messages = @(& $script:assembler @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    [IO.File]::WriteAllText($LogPath, ($messages | Out-String), [Text.UTF8Encoding]::new($false))
    if ($exitCode -ne 0) {
        throw "Shader assembler failed with exit code $exitCode; see $LogPath"
    }
}

$privateRoot = Resolve-Container $PrivatePackRoot 'Private-target diagnostic pack'
$realRoot = Resolve-Container $RealPackRoot 'Reviewed real-composite pack'
$originalAssembly = Resolve-Leaf $OriginalAssemblyPath 'Original e2aa assembly'
$originalBinary = Resolve-Leaf $OriginalBinaryPath 'Original e2aa binary'
$script:assembler = Resolve-Leaf $AssemblerPath '3Dmigoto shader assembler'
$privateManifestPath = Resolve-Leaf (Join-Path $privateRoot 'manifest.json') 'Private-target manifest'
$realManifestPath = Resolve-Leaf (Join-Path $realRoot 'manifest.json') 'Real-composite manifest'
$privateManifest = Get-Content -Raw -LiteralPath $privateManifestPath | ConvertFrom-Json
$realManifest = Get-Content -Raw -LiteralPath $realManifestPath | ConvertFrom-Json

if ($privateManifest.result -ne 'pass' -or
    $privateManifest.variant -ne 'owned-fullscreen-private-target-zero-output' -or
    $privateManifest.ownedPass.target -ne 'private copy_desc of captured target' -or
    $privateManifest.ownedPass.writeback -ne 'none') {
    throw 'Private-target source pack contract is invalid.'
}
if ($realManifest.result -ne 'pass' -or $realManifest.expectedVisual -notmatch 'reviewed indirect lighting') {
    throw 'Reviewed real-composite source pack contract is invalid.'
}

$privateMods = Resolve-Container (Join-Path $privateRoot 'Mods') 'Private-target Mods payload'
$realComposite = Resolve-Leaf (Join-Path $realRoot 'Mods\Agent2R3DSSGICompositeE2AA_ps.hlsl') 'Reviewed real composite'
$sourceFiles = @(Get-ChildItem -LiteralPath $privateMods -File | Sort-Object Name)
if ($sourceFiles.Count -ne 8) {
    throw "Private-target source pack must contain exactly eight files; found $($sourceFiles.Count)."
}
foreach ($file in @($privateManifest.files)) {
    $sourcePath = Resolve-Leaf (Join-Path $privateMods $file.name) "Private payload $($file.name)"
    if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne $file.sha256) {
        throw "Private-target source payload drifted: $($file.name)"
    }
}

$modsOutput = Join-Path $output 'Mods'
$shaderFixesOutput = Join-Path $output 'ShaderFixes'
$validationOutput = Join-Path $output 'validation'
[void][IO.Directory]::CreateDirectory($modsOutput)
[void][IO.Directory]::CreateDirectory($shaderFixesOutput)
[void][IO.Directory]::CreateDirectory($validationOutput)
Copy-Item -Path (Join-Path $privateMods '*') -Destination $modsOutput
Copy-Item -LiteralPath $realComposite -Destination (Join-Path $modsOutput 'Agent2R3DSSGICompositeE2AA_ps.hlsl') -Force

$iniPath = Join-Path $modsOutput 'Agent2R3DSSGITest.ini'
$ini = [IO.File]::ReadAllText($iniPath).Replace("`r`n", "`n")
Assert-One $ini 'blend = ADD ONE ONE' 'Private composite blend anchor'
$ini = $ini.Replace('blend = ADD ONE ONE', 'blend = disable')

$oldHeader = '; Agent 2 standalone R3D SSGI test for the current live topology.'
Assert-One $ini $oldHeader 'INI header'
$ini = $ini.Replace($oldHeader, '; Agent 2 native-draw R3D SSGI integration candidate. Offline only.')
$allowAnchor = "allow_duplicate_hash = true`n"
Assert-One $ini $allowAnchor 'e2aa override allow_duplicate_hash anchor'
$ini = $ini.Replace($allowAnchor, $allowAnchor + 'x30 = $agent2_ssgi_test' + "`n")
$captureInside = "if `$agent2_ssgi_test == 1`n    ResourceAgent2SSGIOriginalT110 = reference ps-t110"
Assert-One $ini $captureInside 'F2 t110 capture anchor'
$ini = $ini.Replace($captureInside, "ResourceAgent2SSGIOriginalT110 = reference ps-t110`nif `$agent2_ssgi_test == 1")
$restoreAnchor = "    run = CustomShaderAgent2R3DSSGIComposite`n    ps-t110 = reference ResourceAgent2SSGIOriginalT110"
Assert-One $ini $restoreAnchor 'Composite-to-native binding anchor'
$ini = $ini.Replace($restoreAnchor, "    run = CustomShaderAgent2R3DSSGIComposite`n    ps-t110 = ResourceAgent2SSGICompositeScratch")
$endifAnchor = "    ps-t114 = reference ResourceAgent2SSGIOriginalT114`nendif"
Assert-One $ini $endifAnchor 'F2 post-restore anchor'
$ini = $ini.Replace($endifAnchor, $endifAnchor + "`npost ps-t110 = reference ResourceAgent2SSGIOriginalT110")
if ($ini -notmatch '(?ms)^\[ShaderOverrideAgent2R3DSSGIF2Test\].*?^x30 = \$agent2_ssgi_test$.*?^ResourceAgent2SSGIOriginalT110 = reference ps-t110$.*?^if \$agent2_ssgi_test == 1$.*?^    run = CustomShaderAgent2R3DSSGIComposite$.*?^    ps-t110 = ResourceAgent2SSGICompositeScratch$.*?^endif$.*?^post ps-t110 = reference ResourceAgent2SSGIOriginalT110$') {
    throw 'Generated native-draw INI contract is incomplete.'
}
[IO.File]::WriteAllText($iniPath, $ini.Replace("`n", "`r`n"), [Text.UTF8Encoding]::new($false))

$assembly = [IO.File]::ReadAllText($originalAssembly).Replace("`r`n", "`n")
if ($assembly -match '(?m)^dcl_resource_.* t110$' -or $assembly -match '(?m)^dcl_resource_.* t120$') {
    throw 'Original e2aa assembly already declares t110 or t120.'
}
Assert-One $assembly 'dcl_resource_texture2d (float,float,float,float) t11' 'Last original resource declaration'
Assert-One $assembly 'dcl_temps 21' 'Original temporary-register declaration'
$nativeWrite = '  mul o0.xyzw, r0.xyzw, cb0[128].xxxx'
Assert-One $assembly $nativeWrite 'Native e2aa output write'

$assembly = $assembly.Replace(
    'dcl_resource_texture2d (float,float,float,float) t11',
    "dcl_resource_texture2d (float,float,float,float) t11`n" +
    "dcl_resource_texture2d (float,float,float,float) t110`n" +
    'dcl_resource_texture1d (float,float,float,float) t120')
$assembly = $assembly.Replace('dcl_temps 21', 'dcl_temps 23')
$nativeComposite = @'
  mul o0.xyzw, r0.xyzw, cb0[128].xxxx
  ld_indexable(texture1d)(float,float,float,float) r21.x, l(30, 0, 0, 0), t120.xyzw
  if_nz r21.x
    ftoi r21.xy, v1.xyxx
    mov r21.zw, l(0, 0, 0, 0)
    ld_indexable(texture2d)(float,float,float,float) r22.xyz, r21.xyzw, t110.xyzw
    add o0.xyz, o0.xyzx, r22.xyzx
  endif
'@.TrimEnd("`r", "`n")
$assembly = $assembly.Replace($nativeWrite, $nativeComposite)
$assembly = "// Remake native-draw SSGI composite: private GI t110, F2 gate IniParams[30].x`n" + $assembly

$authoredAssembly = Join-Path $shaderFixesOutput 'e2aa1c8cb39e0a55-ps.txt'
[IO.File]::WriteAllText($authoredAssembly, $assembly, [Text.UTF8Encoding]::new($false))
$validationAssembly = Join-Path $validationOutput 'e2aa1c8cb39e0a55-ps.asm'
Copy-Item -LiteralPath $authoredAssembly -Destination $validationAssembly
Invoke-Assembler @('-a', '--copy-reflection', $originalBinary, $validationAssembly) (Join-Path $validationOutput 'assemble.log')
$assembledBinary = [IO.Path]::ChangeExtension($validationAssembly, '.shdr')
if (-not (Test-Path -LiteralPath $assembledBinary -PathType Leaf)) {
    throw 'Assembler succeeded without producing the native-composite DXBC binary.'
}
Copy-Item -LiteralPath $assembledBinary -Destination (Join-Path $validationOutput 'native-composite.bin')
Invoke-Assembler @('-d', '-V', (Join-Path $validationOutput 'native-composite.bin')) (Join-Path $validationOutput 'validate.log')
$verifiedAssemblyPath = Join-Path $validationOutput 'native-composite.asm'
$verifiedAssembly = [IO.File]::ReadAllText($verifiedAssemblyPath).Replace("`r`n", "`n")
foreach ($required in @(
    'dcl_resource_texture2d (float,float,float,float) t110',
    'dcl_resource_texture1d (float,float,float,float) t120',
    'dcl_temps 23',
    'ld_indexable(texture1d)(float,float,float,float) r21.x, l(30, 0, 0, 0), t120.xyzw',
    'ld_indexable(texture2d)(float,float,float,float) r22.xyz, r21.xyzw, t110.xyzw',
    'add o0.xyz, o0.xyzx, r22.xyzx'
)) {
    if ($verifiedAssembly -notmatch [regex]::Escape($required)) {
        throw "Verified assembly is missing: $required"
    }
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
    variant = 'private-target-native-e2aa-writeback'
    purpose = 'Generate SSGI into injector-owned resources and add it during the existing native e2aa draw.'
    hook = 'e2aa1c8cb39e0a55-ps'
    controls = [ordered]@{
        F2 = 'off/on for SSGI only'
        F10 = 'native reload, unchanged'
        PageUp = 'unchanged'
        PageDown = 'unchanged'
        iniParam = 'x30 / IniParams[30].x'
    }
    architecture = [ordered]@{
        traceAndDenoise = 'injector-owned private resources'
        compositeTarget = 'private full-resolution ResourceAgent2SSGICompositeScratch'
        nativeWriteback = 'e2aa replacement loads private GI from t110 and adds RGB before returning'
        nativeAlpha = 'preserved'
        originalT110 = 'captured before prepasses and restored post-draw'
        offPath = 'IniParams[30].x is zero, so no t110 load or RGB add executes'
    }
    validation = [ordered]@{
        originalAssemblySha256 = (Get-FileHash -LiteralPath $originalAssembly -Algorithm SHA256).Hash
        originalBinarySha256 = (Get-FileHash -LiteralPath $originalBinary -Algorithm SHA256).Hash
        assemblerSha256 = (Get-FileHash -LiteralPath $script:assembler -Algorithm SHA256).Hash
        assembledBinarySha256 = (Get-FileHash -LiteralPath $assembledBinary -Algorithm SHA256).Hash
        dxbcValidationPassed = $true
        reservedSlots = @('t110', 't120')
        addedTemps = @('r21', 'r22')
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
    RuntimeEligible = $false
}
