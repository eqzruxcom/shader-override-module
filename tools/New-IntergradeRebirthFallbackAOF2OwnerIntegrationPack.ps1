[CmdletBinding()]
param(
    [string]$OwnerIniPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime\Intergrade\Mods\RebirthEffectsDX11.ini'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-rebirth-fallback-consumer-f2-owner-integration-pack'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$candidateGenerator = Join-Path $repoRoot 'tools\New-IntergradeRebirthFallbackAOConsumer.ps1'

function Resolve-WorkspacePath([string]$Path, [switch]$AllowMissing) {
    $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $repoRoot $Path)) }
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Path must remain inside the project workspace: $full" }
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Required file does not exist: $full" }
    $full
}

$ownerFull = Resolve-WorkspacePath $OwnerIniPath
$packRoot = Resolve-WorkspacePath $OutputDirectory -AllowMissing
$candidateRoot = Join-Path $packRoot 'evidence\candidate'
$modsRoot = Join-Path $packRoot 'Mods'
$owner = [IO.File]::ReadAllText($ownerFull)
$ownerSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $ownerFull).Hash

$activeF2 = [regex]::Matches($owner, '(?im)^(?!\s*;)\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F2(?![A-Z0-9_]).*$')
if ($activeF2.Count -ne 0) { throw 'Refusing owner integration because the existing INI already claims F2.' }
if ([regex]::Matches($owner, '(?im)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$').Count -ne 1) {
    throw 'Refusing owner integration because the existing INI must own e2aa exactly once.'
}
if ([regex]::Matches($owner, '(?m)^global \$rebirth_ab_current = 1\s*$').Count -ne 1) {
    throw 'Refusing owner integration because the rolling A/B state anchor changed.'
}

$ownerPattern = '(?ms)(\[ShaderOverrideRebirthABShared\]\r?\n\s*hash\s*=\s*e2aa1c8cb39e0a55\r?\n\s*allow_duplicate_hash\s*=\s*true\r?\n)(if \$rebirth_ab_current == 0\r?\n\s+run = (?<previous>[A-Za-z0-9_]+)\r?\nelse\r?\n\s+run = (?<current>[A-Za-z0-9_]+)\r?\nendif)'
$ownerMatches = [regex]::Matches($owner, $ownerPattern)
if ($ownerMatches.Count -ne 1) { throw 'Refusing owner integration because the e2aa rolling A/B override body changed or is ambiguous.' }
$previousCustom = $ownerMatches[0].Groups['previous'].Value
$currentCustom = $ownerMatches[0].Groups['current'].Value

New-Item -ItemType Directory -Path $candidateRoot,$modsRoot -Force | Out-Null
$candidate = & $candidateGenerator -OutputDirectory $candidateRoot -FxcPath $FxcPath
$candidateManifest = Get-Content -Raw -LiteralPath $candidate.Manifest | ConvertFrom-Json
if ($candidateManifest.shaderHash -ne 'e2aa1c8cb39e0a55' -or $candidateManifest.runtimeAdapterEligible -ne $false -or $candidateManifest.liveStatus -ne 'not-staged') {
    throw 'Candidate contract changed.'
}

$shaderName = [IO.Path]::GetFileName($candidate.Source)
$packShaderPath = Join-Path $modsRoot $shaderName
$patchedIniPath = Join-Path $modsRoot 'RebirthEffectsDX11.ini'
$manifestPath = Join-Path $packRoot 'manifest.json'
Copy-Item -LiteralPath $candidate.Source -Destination $packShaderPath -Force

$withState = [regex]::Replace(
    $owner,
    '(?m)^global \$rebirth_ab_current = 1\s*$',
    "global `$rebirth_ab_current = 1`r`nglobal `$intergrade_rebirth_fallback_ao_f2_test = 0",
    1
)
$integrationBlock = @"
; AGENT2 REBIRTH FALLBACK AO F2 BEGIN
; Offline integration preview. F2 OFF preserves the existing rolling A/B owner.
; F2 ON runs the literal Rebirth native-SSAO fallback consumer candidate.
[KeyIntergradeRebirthFallbackAOF2Test]
key = no_modifiers F2
type = cycle
smart = true
`$intergrade_rebirth_fallback_ao_f2_test = 0, 1

[CustomShaderIntergradeRebirthFallbackAOCandidate]
ps = $shaderName
handling = skip
draw = from_caller
; AGENT2 REBIRTH FALLBACK AO F2 END

"@
if ([regex]::Matches($withState, '(?m)^\[ShaderOverrideRebirthABShared\]\s*$').Count -ne 1) {
    throw 'Existing owner section anchor changed.'
}
$withBlock = [regex]::Replace($withState, '(?m)^\[ShaderOverrideRebirthABShared\]\s*$', [Text.RegularExpressions.MatchEvaluator]{ param($match) $integrationBlock + $match.Value }, 1)

$replacementBody = @"
if `$intergrade_rebirth_fallback_ao_f2_test == 1
    run = CustomShaderIntergradeRebirthFallbackAOCandidate
else
    if `$rebirth_ab_current == 0
        run = $previousCustom
    else
        run = $currentCustom
    endif
endif
"@.TrimEnd()
$patched = [regex]::Replace($withBlock, $ownerPattern, [Text.RegularExpressions.MatchEvaluator]{
    param($match)
    $match.Groups[1].Value + $replacementBody
}, 1)
$patched = $patched -replace "`r?`n", "`r`n"

if ([regex]::Matches($patched, '(?im)^\s*key\s*=\s*no_modifiers\s+F2\s*$').Count -ne 1) { throw 'Integrated preview must claim F2 exactly once.' }
if ($patched -match '(?im)^\s*key\s*=.*(?:F1|PAGEUP|PAGEDOWN)\s*$') { throw 'Integrated preview claimed a forbidden control key.' }
if ([regex]::Matches($patched, '(?im)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$').Count -ne 1) { throw 'Integrated preview duplicated or removed e2aa ownership.' }
if ([regex]::Matches($patched, '(?im)^\s*run\s*=\s*CustomShaderIntergradeRebirthFallbackAOCandidate\s*$').Count -ne 1) { throw 'Integrated preview AO run count is invalid.' }
foreach ($existingCustom in @($previousCustom,$currentCustom)) {
    if ($patched -notmatch "(?im)^\s*run\s*=\s*$([regex]::Escape($existingCustom))\s*$") { throw "Integrated preview did not preserve existing owner branch: $existingCustom" }
}
if ($patched -notmatch '(?ms)^if \$intergrade_rebirth_fallback_ao_f2_test == 1\r?\n\s+run = CustomShaderIntergradeRebirthFallbackAOCandidate\r?\nelse\r?\n\s+if \$rebirth_ab_current == 0') {
    throw 'Integrated preview does not prioritize F2 ON and preserve the old owner under F2 OFF.'
}
[IO.File]::WriteAllText($patchedIniPath, $patched.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

$relative = { param([string]$Path) $Path.Substring($repoRoot.Length + 1).Replace('\','/') }
$manifest = [ordered]@{
    schemaVersion = 1
    adapter = 'FF7RemakeIntergrade'
    effect = 'rebirth-native-ssao-fallback-consumer-f2-owner-integration'
    shaderHash = 'e2aa1c8cb39e0a55'
    stage = 'ps'
    status = 'offline-owner-integration-preview-not-installed'
    runtimeEligible = $false
    installationPerformed = $false
    liveGameDirectoryTouched = $false
    existingOwner = [ordered]@{
        ini = & $relative $ownerFull
        exactSha256 = $ownerSha256
        section = 'ShaderOverrideRebirthABShared'
        previousCustom = $previousCustom
        currentCustom = $currentCustom
        preservedWhen = 'F2 OFF'
    }
    keyContract = [ordered]@{
        F1 = 'not claimed; future global mod on/off'
        F2 = 'binary native-existing-owner/candidate test toggle'
        F3 = 'existing rolling A/B ownership preserved; not claimed by AO'
        defaultState = 0
        off = 'existing e2aa rolling A/B owner unchanged'
        on = 'literal Rebirth fallback-AO consumer candidate'
    }
    singleOwnerContract = [ordered]@{
        e2aaOverrideCount = 1
        duplicateOverrideAdded = $false
        AOBranchRunsOnlyWhen = '$intergrade_rebirth_fallback_ao_f2_test == 1'
        oldOwnerNestedUnderOff = $true
    }
    patchedIni = & $relative $patchedIniPath
    patchedIniSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchedIniPath).Hash
    shader = & $relative $packShaderPath
    shaderSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $packShaderPath).Hash
    candidateManifest = & $relative $candidate.Manifest
    candidateObjectSha256 = $candidate.ObjectSha256
    nextGate = 'review owner SHA and current rolling A/B purpose, then explicitly authorize staging; no installation performed'
}
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    PackRoot = $packRoot
    PatchedIni = $patchedIniPath
    Shader = $packShaderPath
    Manifest = $manifestPath
    OwnerSha256 = $ownerSha256
    PatchedIniSha256 = $manifest.patchedIniSha256
    ShaderSha256 = $manifest.shaderSha256
    ObjectSha256 = $candidate.ObjectSha256
    Installed = $false
}
