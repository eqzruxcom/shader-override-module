[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [string]$ExpectedCandidateSha256 = 'D7279079727272E07AC93F4367CB48B58EA0B4E1D691F98DAC117207188C4879'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $PackageDirectory).Path.TrimEnd('\')
$iniPath = Join-Path $root 'Mods\ContactShadows.ini'
$shaderPath = Join-Path $root 'ShaderFixes\62b33a2d1e505241-cs.txt'
foreach ($path in @($iniPath,$shaderPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing package file: $path" }
}

$unexpected = @(Get-ChildItem -LiteralPath (Join-Path $root 'ShaderFixes') -File | Where-Object Name -ne '62b33a2d1e505241-cs.txt')
if ($unexpected.Count) { throw 'The isolated package contains shader payloads other than 62b.' }

$ini = Get-Content -LiteralPath $iniPath -Raw
if (([regex]::Matches($ini,'(?m)^\[KeyUE4FXMasterPageDown\]\s*$')).Count -ne 1 -or
    ([regex]::Matches($ini,'(?m)^key\s*=\s*no_modifiers\s+VK_NEXT\s*$')).Count -ne 1) {
    throw 'Page Down master is missing or duplicated.'
}
if (([regex]::Matches($ini,'(?m)^\[KeyUE4FXContactSoftnessPageUp\]\s*$')).Count -ne 1 -or
    ([regex]::Matches($ini,'(?m)^key\s*=\s*no_modifiers\s+VK_PRIOR\s*$')).Count -ne 1) {
    throw 'The isolated Page Up softness key is missing or duplicated.'
}
if (([regex]::Matches($ini,'(?m)^x31\s*=\s*\$ue4fx_master_injected_v1\s*$')).Count -ne 5) {
    throw 'Page Down is not bound to all five retained contact shaders.'
}
if (([regex]::Matches($ini,'(?m)^x28\s*=\s*\$ue4fx_contact_softness_test_v1\s*$')).Count -ne 1 -or
    ([regex]::Matches($ini,'(?m)^y28\s*=\s*\$ue4fx_contact_softness_radius_v1\s*$')).Count -ne 1) {
    throw 'Page Up row 28 must be bound exactly once.'
}
$section = [regex]::Match($ini,'(?ms)^\[ShaderOverrideUE4FXContact62b33a2d1e505241\]\s*\r?\n(.*?)(?=^\[|\z)')
if (-not $section.Success -or
    $section.Groups[1].Value -notmatch '(?m)^x28\s*=\s*\$ue4fx_contact_softness_test_v1\s*$' -or
    $section.Groups[1].Value -notmatch '(?m)^y28\s*=\s*\$ue4fx_contact_softness_radius_v1\s*$' -or
    $section.Groups[1].Value -notmatch '(?m)^x29\s*=\s*\$ue4fx_contact_edge_width_v2\s*$' -or
    $section.Groups[1].Value -notmatch '(?m)^x31\s*=\s*\$ue4fx_master_injected_v1\s*$') {
    throw 'The Page Up test is not isolated to the accepted 62b route.'
}
if ($ini -notmatch '(?m)^global \$ue4fx_contact_softness_test_v1\s*=\s*0\s*$') {
    throw 'Page Up test must default OFF.'
}
if ($ini -notmatch '(?m)^\$ue4fx_contact_softness_test_v1\s*=\s*0,\s*1,\s*1,\s*1,\s*1\s*$' -or
    $ini -notmatch '(?m)^\$ue4fx_contact_softness_radius_v1\s*=\s*5,\s*10,\s*20,\s*40,\s*80\s*$') {
    throw 'Page Up must cycle exactly: default shader, 2x, 4x, 8x, 16x.'
}
if ($ini -match '(?im)^key\s*=\s*no_modifiers\s+VK_F10\s*$') {
    throw 'F10 belongs to shader/config reload and must not be emitted by this experiment package.'
}
if ($ini -notmatch '(?m)^global \$ue4fx_contact_edge_width_v2\s*=\s*0\.06\s*$' -or
    $ini -notmatch '(?m)^global \$ue4fx_contact_edge_cutoff_v2\s*=\s*0\s*$') {
    throw 'The accepted 0-to-6-percent Frustum Fix controls changed.'
}

$shader = Get-Content -LiteralPath $shaderPath -Raw
if ($shader -notmatch '(?m)^//Frustum Fix\s*$' -or
    $shader -notmatch 'l\(28,\s*0,\s*0,\s*0\),\s*t120' -or
    $shader -notmatch 'l\(29,\s*0,\s*0,\s*0\),\s*t120' -or
    $shader -notmatch 'l\(31,\s*0,\s*0,\s*0\),\s*t120') {
    throw 'Combined 62b shader is missing the Page Up, Frustum Fix, or Page Down control path.'
}

$receiptPath = Join-Path $root 'validation\62b-roundtrip.json'
if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { throw 'Missing assembled round-trip receipt.' }
$receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
if ($receipt.candidateSha256 -ne $ExpectedCandidateSha256 -or $receipt.roundTripSha256 -ne $ExpectedCandidateSha256) {
    throw 'Staged 62b does not assemble to the pinned combined candidate.'
}

[pscustomobject]@{
    Result='passed-isolated-62b-softness-package'
    PageDownShaders=5
    PageUpShaders=1
    PageUpStates='default,2x,4x,8x,16x'
    FrustumFix='left 0-to-6 percent preserved'
    CandidateSha256=$ExpectedCandidateSha256
}
