[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-rebirth-fallback-consumer-f2-test-pack-test'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$generator = Join-Path $repoRoot 'tools\New-IntergradeRebirthFallbackAOF2TestPack.ps1'
$runtimeRoot = Join-Path $repoRoot 'runtime\Intergrade\Mods'
$runRoot = Join-Path $OutputDirectory ([Guid]::NewGuid().ToString('N'))
$firstRoot = Join-Path $runRoot 'first'
$secondRoot = Join-Path $runRoot 'second'
$negativeRoot = Join-Path $runRoot 'negative'
$emptyRuntime = Join-Path $runRoot 'empty-runtime'
New-Item -ItemType Directory -Path $runRoot,$negativeRoot,$emptyRuntime -Force | Out-Null

function Get-TreeHashes([string]$Root) {
    $result = [ordered]@{}
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName) {
        $relative = $file.FullName.Substring($Root.Length + 1)
        $result[$relative] = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
    }
    $result
}

function Compare-HashMaps([Collections.IDictionary]$Before, [Collections.IDictionary]$After, [string]$Context) {
    if (($Before.Keys -join "`n") -cne ($After.Keys -join "`n")) { throw "$Context file inventory changed." }
    foreach ($key in $Before.Keys) {
        if ($Before[$key] -ne $After[$key]) { throw "$Context changed: $key" }
    }
}

function Assert-Pack([object]$Pack) {
    $manifest = Get-Content -Raw -LiteralPath $Pack.Manifest | ConvertFrom-Json
    $ini = Get-Content -Raw -LiteralPath $Pack.Ini
    if ($manifest.status -ne 'offline-staging-pack-not-installed' -or $manifest.runtimeEligible -ne $false -or
        $manifest.installationPerformed -ne $false -or $manifest.liveGameDirectoryTouched -ne $false -or $Pack.Installed -ne $false) {
        throw 'Corrected F2 pack escaped its offline no-install boundary.'
    }
    if ($manifest.shaderHash -ne 'e2aa1c8cb39e0a55' -or $manifest.effect -ne 'rebirth-native-ssao-fallback-consumer-f2-test') {
        throw 'Corrected F2 pack identity is invalid.'
    }
    if ($manifest.keyContract.F1 -ne 'not claimed; future global mod on/off' -or
        $manifest.keyContract.F2 -ne 'binary native/candidate test toggle' -or
        $manifest.keyContract.F3 -ne 'not claimed; unassigned') {
        throw 'Corrected F2 pack key ownership is invalid.'
    }
    if ($manifest.keyContract.defaultState -ne 0 -or $manifest.overrideContract.offBranchHasReplacementRun -ne $false) {
        throw 'Corrected F2 pack does not fail closed to native.'
    }
    if ($manifest.overrideContract.directLightAOConsumersChanged -ne $false -or $manifest.overrideContract.temporalAOProducerChanged -ne $false) {
        throw 'Corrected F2 pack claims the wrong AO scope.'
    }
    if ([regex]::Matches($ini, '(?im)^\s*key\s*=\s*no_modifiers\s+F2\s*$').Count -ne 1) { throw 'Corrected pack does not have exactly one F2 binding.' }
    if ($ini -match '(?im)^\s*key\s*=.*(?:F1|F3|PAGEUP|PAGEDOWN)\s*$') { throw 'Corrected pack claimed a forbidden key.' }
    if ([regex]::Matches($ini, '(?im)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$').Count -ne 1) { throw 'Corrected pack consumer override count is invalid.' }
    if ($ini -match '(?im)^\s*hash\s*=\s*a77b589dce5822d6\s*$') { throw 'Superseded producer override leaked into corrected pack.' }
    if ([regex]::Matches($ini, '(?im)^\s*run\s*=\s*CustomShaderIntergradeRebirthFallbackAOCandidate\s*$').Count -ne 1) { throw 'Corrected pack candidate run count is invalid.' }
    if ($ini -notmatch '(?ms)^if \$intergrade_rebirth_fallback_ao_f2_test == 1\r?\n\s+run = CustomShaderIntergradeRebirthFallbackAOCandidate\r?\nendif\s*$') {
        throw 'Corrected pack does not gate its only replacement run on F2 ON.'
    }
    foreach ($pair in @(@($Pack.Ini,$manifest.iniSha256),@($Pack.Shader,$manifest.shaderSha256))) {
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $pair[0]).Hash -ne $pair[1]) { throw 'Corrected pack artifact hash mismatch.' }
    }
}

$runtimeBefore = Get-TreeHashes $runtimeRoot
$first = & $generator -OutputDirectory $firstRoot -ConflictScanRoots @($emptyRuntime)
$second = & $generator -OutputDirectory $secondRoot -ConflictScanRoots @($emptyRuntime)
Assert-Pack $first
Assert-Pack $second
if ($first.IniSha256 -ne $second.IniSha256 -or $first.ShaderSha256 -ne $second.ShaderSha256 -or $first.ObjectSha256 -ne $second.ObjectSha256) {
    throw 'Corrected F2 test-pack generation is not deterministic.'
}

foreach ($negativeName in @('f2-conflict','consumer-hash-conflict')) {
    $fakeRuntime = Join-Path $negativeRoot $negativeName
    New-Item -ItemType Directory -Path $fakeRuntime -Force | Out-Null
    $fakeIni = if ($negativeName -eq 'f2-conflict') {
        "[KeyConflict]`r`nkey = no_modifiers F2`r`n"
    } else {
        "[ShaderOverrideConflict]`r`nhash = e2aa1c8cb39e0a55`r`n"
    }
    [IO.File]::WriteAllText((Join-Path $fakeRuntime 'Conflict.ini'), $fakeIni, [Text.UTF8Encoding]::new($false))
    $rejectedOutput = Join-Path $negativeRoot "$negativeName-output"
    $rejected = $false
    try {
        & $generator -OutputDirectory $rejectedOutput -ConflictScanRoots @($fakeRuntime) | Out-Null
    } catch {
        if ($_.Exception.Message -notmatch 'Refusing corrected F2 AO pack') { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw "Generator accepted $negativeName." }
    if (Test-Path -LiteralPath $rejectedOutput) { throw "Rejected $negativeName emitted pack artifacts." }
}

$currentOwnerRejected = $false
$currentOwnerOutput = Join-Path $negativeRoot 'current-runtime-owner-output'
try {
    & $generator -OutputDirectory $currentOwnerOutput | Out-Null
} catch {
    if ($_.Exception.Message -notmatch 'Refusing corrected F2 AO pack') { throw }
    $currentOwnerRejected = $true
}
if (-not $currentOwnerRejected) { throw 'Standalone pack did not reject the current runtime e2aa owner.' }
if (Test-Path -LiteralPath $currentOwnerOutput) { throw 'Current-owner rejection emitted pack artifacts.' }

$runtimeAfter = Get-TreeHashes $runtimeRoot
Compare-HashMaps $runtimeBefore $runtimeAfter 'Project runtime'

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    shaderHash = 'e2aa1c8cb39e0a55'
    effect = 'rebirth-native-ssao-fallback-consumer-f2-test'
    deterministicBuild = $true
    F1Claimed = $false
    F2BinaryNativeCandidateToggle = $true
    F3Claimed = $false
    defaultAndOffPath = 'native e2aa game shader fallthrough'
    conflictRejection = @('active F2 binding','active e2aa1c8cb39e0a55 override')
    currentRuntimeOwnerRejected = $true
    supersededProducerAbsent = $true
    projectRuntimeUnchanged = $true
    liveGameDirectoryTouched = $false
}
$reportPath = Join-Path $runRoot 'report.json'
[IO.File]::WriteAllText($reportPath, (($report | ConvertTo-Json -Depth 10) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Output 'Intergrade corrected Rebirth fallback-AO F2 offline test-pack validation passed.'
Write-Output "Report: $reportPath"
