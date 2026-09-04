[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\contact-62b-route-diagnostic-20260901-v1'),
    [string]$BaselineAssembly = (Join-Path (Split-Path -Parent $PSScriptRoot) 'working-code\Frustum Fix\20260831-v1\accepted-runtime\ShaderFixes\62b33a2d1e505241-cs.txt'),
    [string]$OriginalBinary = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\dxbc\62b33a2d1e505241-cs.bin'),
    [string]$AssemblerPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\shader-assembler-build\bin\cmd_Decompiler.exe')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
$newline = [Environment]::NewLine

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
    if ($exitCode -ne 0) { throw "Shader assembly failed; see $LogPath" }
}

$validation = Join-Path $output 'validation'
$payloadMods = Join-Path $output 'payload\Mods'
$payloadShaders = Join-Path $output 'payload\ShaderFixes'
foreach ($directory in @($validation, $payloadMods, $payloadShaders)) {
    [IO.Directory]::CreateDirectory($directory) | Out-Null
}

$source = [IO.File]::ReadAllText($baseline)
$anchor = 'mov r25.x, r27.y'
if ([regex]::Matches($source, [regex]::Escape($anchor)).Count -ne 1) {
    throw 'Expected one unique final-contact-visibility anchor in accepted 62b.'
}
if ($source -match 'l\(28, 0, 0, 0\), t120') {
    throw 'Accepted 62b baseline already consumes reserved diagnostic row 28.'
}

$modified = $source.Replace(
    $anchor,
    $anchor + $newline +
    '// Page Up route proof: neutralize only 62b contact visibility, preserving complete light output.' + $newline +
    'ld_indexable(texture1d)(float,float,float,float) r26.x, l(28, 0, 0, 0), t120.xyzw' + $newline +
    'eq r26.x, r26.x, l(1.000000)' + $newline +
    'movc r25.x, r26.x, l(1.000000), r25.x')

$runtimeAssembly = Join-Path $payloadShaders '62b33a2d1e505241-cs.txt'
[IO.File]::WriteAllText($runtimeAssembly, $modified, $utf8)
$authoredAssembly = Join-Path $validation '62b-route.asm'
[IO.File]::WriteAllText($authoredAssembly, $modified, $utf8)
Invoke-Assembler @('-a', '--copy-reflection', $original, $authoredAssembly) (Join-Path $validation 'assemble.log')

$candidateBinary = Join-Path $validation '62b-route.shdr'
if (-not (Test-Path -LiteralPath $candidateBinary -PathType Leaf)) {
    throw 'Assembler produced no 62b route diagnostic shader.'
}
$verifyBinary = Join-Path $validation '62b-route-verified.bin'
Copy-Item -LiteralPath $candidateBinary -Destination $verifyBinary
Invoke-Assembler @('-d', '-V', $verifyBinary) (Join-Path $validation 'verify.log')
$verifiedAssembly = Join-Path $validation '62b-route-verified.asm'
$verified = [IO.File]::ReadAllText($verifiedAssembly)
foreach ($required in @(
    'ld_indexable(texture1d)(float,float,float,float) r26.x, l(28, 0, 0, 0), t120.xyzw',
    'eq r26.x, r26.x, l(1.000000)',
    'movc r25.x, r26.x, l(1.000000), r25.x',
    'mul r18.xyz, r18.xyzw, r25.xxxx',
    'mul r17.yzw, r17.xyzw, r25.xxxx'
)) {
    if ($verified -notmatch [regex]::Escape($required)) {
        throw "Verified 62b route diagnostic is missing: $required"
    }
}

$ini = @'
; 62b contact-route diagnostic. Page Down remains the master; Page Up is the test key.
[Constants]
global $ue4fx_master_injected_v1 = 1
global $ue4fx_contact62b_route_test_v1 = 0
global $ue4fx_contact_edge_width_v2 = 0.06
global $ue4fx_contact_edge_cutoff_v2 = 0

[KeyUE4FXContact62bRoutePageUp]
key = no_modifiers VK_PRIOR
type = cycle
smart = true
$ue4fx_contact62b_route_test_v1 = 0, 1

[KeyUE4FXMasterPageDown]
key = no_modifiers VK_NEXT
type = cycle
smart = true
$ue4fx_master_injected_v1 = 0, 1

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
x28 = $ue4fx_contact62b_route_test_v1
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
[IO.File]::WriteAllText($iniPath, $ini.TrimStart() + $newline, $utf8)

$manifest = [ordered]@{
    schemaVersion = 1
    diagnosticId = 'ff7r-contact-62b-route-v1'
    status = 'offline-assembled-awaiting-focused-runtime-test'
    runtimeEligible = $false
    installed = $false
    baselineSha256 = $expectedBaselineSha256
    candidateSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidateBinary).Hash
    controls = [ordered]@{ master = 'Page Down'; experiment = 'Page Up'; experimentDefault = 'accepted baseline' }
    pageUpOn = 'Force 62b final contact visibility to neutral 1.0; do not zero complete light output.'
    interpretation = [ordered]@{
        positive = 'The watched hard contact shadow disappears or weakens: 62b owns that receiver route.'
        negative = 'The watched shadow is unchanged: another contact evaluator specialization owns it.'
        invalid = 'Complete local lights go out: roll back immediately because the diagnostic did not execute as authored.'
    }
}
$manifestPath = Join-Path $output 'diagnostic-manifest.json'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8) + $newline, $utf8)

[pscustomobject]@{
    Output = $output
    Shader = '62b33a2d1e505241-cs'
    CandidateSha256 = $manifest.candidateSha256
    RuntimeEligible = $false
    Installed = $false
}
