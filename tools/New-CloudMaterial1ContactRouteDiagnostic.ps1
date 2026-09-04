[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\clothing-material1-contact-route-diagnostic-20260901-v1'),
    [string]$BaselineAssembly = (Join-Path (Split-Path -Parent $PSScriptRoot) 'working-code\Frustum Fix\20260831-v1\accepted-runtime\ShaderFixes\62b33a2d1e505241-cs.txt'),
    [string]$OriginalBinary = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\dxbc\62b33a2d1e505241-cs.bin'),
    [string]$AssemblerPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\shader-assembler-build\bin\cmd_Decompiler.exe')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)

$baseline = (Resolve-Path -LiteralPath $BaselineAssembly -ErrorAction Stop).Path
$original = (Resolve-Path -LiteralPath $OriginalBinary -ErrorAction Stop).Path
$assembler = (Resolve-Path -LiteralPath $AssemblerPath -ErrorAction Stop).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)

$expectedBaselineSha256 = 'A381CB443608CA44528B20C8BE6657B74FC2A7AB340C4C0E23282780A17A8D3D'
$expectedOriginalSha256 = '1E290F68B5A07E8987A674384B955C0D6A8246A96B47506CD2E4CC6E6EED9551'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $baseline).Hash -ne $expectedBaselineSha256) {
    throw 'Accepted //Frustum Fix 62b baseline fingerprint changed.'
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $original).Hash -ne $expectedOriginalSha256) {
    throw 'Captured original 62b DXBC fingerprint changed.'
}
if (Test-Path -LiteralPath $output) {
    throw "Output already exists; refusing to merge diagnostic state: $output"
}

function Invoke-Assembler {
    param([string[]]$Arguments, [string]$LogPath)
    $messages = & $assembler @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    [IO.File]::WriteAllText($LogPath, ($messages | Out-String), $utf8)
    if ($exitCode -ne 0) {
        throw "Shader assembly failed; see $LogPath"
    }
}

$validation = Join-Path $output 'validation'
$payloadMods = Join-Path $output 'payload\Mods'
$payloadShaders = Join-Path $output 'payload\ShaderFixes'
foreach ($directory in @($validation, $payloadMods, $payloadShaders)) {
    [IO.Directory]::CreateDirectory($directory) | Out-Null
}

$source = [IO.File]::ReadAllText($baseline).Replace("`r`n", "`n")
$tempAnchor = 'dcl_temps 40'
$materialAnchor = 'and r6.xy, r3.wwww, l(15, 16, 0, 0)'
$visibilityAnchor = 'mov r25.x, r27.y'
foreach ($anchor in @($tempAnchor, $materialAnchor, $visibilityAnchor)) {
    if ([regex]::Matches($source, [regex]::Escape($anchor)).Count -ne 1) {
        throw "Expected one unique 62b insertion anchor: $anchor"
    }
}
if ($source -match 'l\(28, 0, 0, 0\), t120') {
    throw 'Accepted 62b baseline already consumes reserved diagnostic row 28.'
}

$modified = $source.Replace($tempAnchor, 'dcl_temps 41')
$modified = $modified.Replace(
    $materialAnchor,
    $materialAnchor + "`n" +
    '// Preserve whether this deferred pixel has GBuffer material/shading-model ID 1.' + "`n" +
    'ieq r40.x, r6.x, l(1)')
$modified = $modified.Replace(
    $visibilityAnchor,
    $visibilityAnchor + "`n" +
    '// Page Up diagnostic: make only material-ID 1 unoccluded; never force light visibility to zero.' + "`n" +
    'ld_indexable(texture1d)(float,float,float,float) r26.x, l(28, 0, 0, 0), t120.xyzw' + "`n" +
    'eq r26.x, r26.x, l(1.000000)' + "`n" +
    'and r26.x, r26.x, r40.x' + "`n" +
    'movc r25.x, r26.x, l(1.000000), r25.x')

$runtimeAssembly = Join-Path $payloadShaders '62b33a2d1e505241-cs.txt'
[IO.File]::WriteAllText($runtimeAssembly, $modified, $utf8)

$authoredAssembly = Join-Path $validation '62b-material1-contact-route.asm'
[IO.File]::WriteAllText($authoredAssembly, $modified, $utf8)
Invoke-Assembler @('-a', '--copy-reflection', $original, $authoredAssembly) (Join-Path $validation 'assemble.log')
$candidateBinary = Join-Path $validation '62b-material1-contact-route.shdr'
if (-not (Test-Path -LiteralPath $candidateBinary -PathType Leaf)) {
    throw 'Assembler produced no material-ID diagnostic shader.'
}
$verifyBinary = Join-Path $validation '62b-material1-contact-route-verified.bin'
Copy-Item -LiteralPath $candidateBinary -Destination $verifyBinary
Invoke-Assembler @('-d', '-V', $verifyBinary) (Join-Path $validation 'verify.log')
$verifiedAssembly = Join-Path $validation '62b-material1-contact-route-verified.asm'
$verified = [IO.File]::ReadAllText($verifiedAssembly)
foreach ($required in @(
    'dcl_temps 41',
    'ieq r40.x, r6.x, l(1)',
    'ld_indexable(texture1d)(float,float,float,float) r26.x, l(28, 0, 0, 0), t120.xyzw',
    'and r26.x, r26.x, r40.x',
    'movc r25.x, r26.x, l(1.000000), r25.x',
    'mul r18.xyz, r18.xyzw, r25.xxxx',
    'mul r17.yzw, r17.xyzw, r25.xxxx'
)) {
    if ($verified -notmatch [regex]::Escape($required)) {
        throw "Verified material-ID diagnostic is missing: $required"
    }
}

$ini = @'
; Corrected Cloud clothing contact-route diagnostic. Offline only; not automatically installed.
; Page Down is the master injected-code switch. Page Up is the active experiment.
; Page Up ON sets contact visibility to neutral 1.0 only for GBuffer material ID 1.
; It does NOT set visibility to zero and therefore must not extinguish the complete local light.
; Material ID 1 is broader than Cloud clothing; this proves the deferred route, not object identity.
[Constants]
global $ue4fx_master_injected_v1 = 1
global $ue4fx_material1_contact_route_v1 = 0
global $ue4fx_contact_edge_width_v2 = 0.06
global $ue4fx_contact_edge_cutoff_v2 = 0

[KeyUE4FXMasterPageDown]
key = no_modifiers VK_NEXT
type = cycle
smart = true
$ue4fx_master_injected_v1 = 0, 1

[KeyUE4FXMaterial1RoutePageUp]
key = no_modifiers VK_PRIOR
type = cycle
smart = true
$ue4fx_material1_contact_route_v1 = 0, 1

[ShaderOverrideUE4FXContactc30cdc8365df9840]
hash = c30cdc8365df9840
x29 = $ue4fx_contact_edge_width_v2
y29 = $ue4fx_contact_edge_cutoff_v2
x31 = $ue4fx_master_injected_v1
y31 = -1
z31 = 1
w31 = 100

[ShaderOverrideUE4FXContact62b33a2d1e505241]
hash = 62b33a2d1e505241
x28 = $ue4fx_material1_contact_route_v1
x29 = $ue4fx_contact_edge_width_v2
y29 = $ue4fx_contact_edge_cutoff_v2
x31 = $ue4fx_master_injected_v1
y31 = -1
z31 = 1
w31 = 100

[ShaderOverrideUE4FXContact5a9fbefe0ab6f815]
hash = 5a9fbefe0ab6f815
x29 = $ue4fx_contact_edge_width_v2
y29 = $ue4fx_contact_edge_cutoff_v2
x31 = $ue4fx_master_injected_v1
y31 = -1
z31 = 1
w31 = 100

[ShaderOverrideUE4FXContact0e97888f9a8767da]
hash = 0e97888f9a8767da
x29 = $ue4fx_contact_edge_width_v2
y29 = $ue4fx_contact_edge_cutoff_v2
x31 = $ue4fx_master_injected_v1
y31 = -1
z31 = 1
w31 = 100

[ShaderOverrideUE4FXContact08bb8764f1840179]
hash = 08bb8764f1840179
x29 = $ue4fx_contact_edge_width_v2
y29 = $ue4fx_contact_edge_cutoff_v2
x31 = $ue4fx_master_injected_v1
y31 = -1
z31 = 1
w31 = 100
'@
$iniPath = Join-Path $payloadMods 'ContactShadows.ini'
[IO.File]::WriteAllText($iniPath, $ini.TrimStart() + [Environment]::NewLine, $utf8)

$manifest = [ordered]@{
    schemaVersion = 1
    diagnosticId = 'ff7r-material1-contact-route-v1'
    status = 'offline-assembled-awaiting-focused-runtime-test'
    runtimeEligible = $false
    installed = $false
    baseline = [ordered]@{
        label = '//Frustum Fix'
        shader = '62b33a2d1e505241-cs'
        sha256 = $expectedBaselineSha256
    }
    correction = 'The rejected test forced contact visibility to 0, which multiplied the complete light contribution to black. This test uses neutral visibility 1 and gates it to material ID 1.'
    scope = [ordered]@{
        confirmed = 'all pixels processed by 62b whose low four-bit GBuffer material/shading-model ID equals 1'
        notClaimed = 'Cloud clothing object identity; other material-ID 1 pixels may change'
    }
    controls = [ordered]@{
        master = 'Page Down'
        experiment = 'Page Up'
        experimentDefault = 'off'
        iniRow = 28
    }
    interpretation = [ordered]@{
        positive = 'Page Up removes added contact darkening from Cloud clothing while preserving local-light brightness; the material-ID 1 deferred route is confirmed.'
        negative = 'Cloud clothing does not change; another specialization/permutation or the ray inputs must be investigated.'
        invalid = 'Complete local lights go out; the diagnostic is not executing as authored and must be rolled back.'
    }
    files = @(
        [ordered]@{ path = 'payload/Mods/ContactShadows.ini'; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $iniPath).Hash },
        [ordered]@{ path = 'payload/ShaderFixes/62b33a2d1e505241-cs.txt'; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $runtimeAssembly).Hash },
        [ordered]@{ path = 'validation/62b-material1-contact-route.shdr'; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidateBinary).Hash }
    )
}
[IO.File]::WriteAllText(
    (Join-Path $output 'diagnostic-manifest.json'),
    ($manifest | ConvertTo-Json -Depth 10) + [Environment]::NewLine,
    $utf8)

[pscustomobject]@{
    Output = $output
    Shader = '62b33a2d1e505241-cs'
    MaterialId = 1
    NeutralVisibility = 1.0
    RuntimeEligible = $false
    Installed = $false
}
