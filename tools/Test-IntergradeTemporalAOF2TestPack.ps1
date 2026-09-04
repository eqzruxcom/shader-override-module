[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-temporal-power-f2-test-pack-test')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$generator = Join-Path $repoRoot 'tools\New-IntergradeTemporalAOF2TestPack.ps1'
$runtimeRoot = Join-Path $repoRoot 'runtime\Intergrade\Mods'
$runRoot = Join-Path $OutputDirectory ([Guid]::NewGuid().ToString('N'))
$firstRoot = Join-Path $runRoot 'first'
$secondRoot = Join-Path $runRoot 'second'
$strongRoot = Join-Path $runRoot 'strong'
$negativeRoot = Join-Path $runRoot 'negative'
New-Item -ItemType Directory -Path $runRoot,$negativeRoot -Force | Out-Null

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

function Assert-Pack([object]$Pack, [string]$ExpectedPreset, [double]$ExpectedPower) {
    $manifest = Get-Content -Raw -LiteralPath $Pack.Manifest | ConvertFrom-Json
    $ini = Get-Content -Raw -LiteralPath $Pack.Ini
    if ($manifest.status -ne 'offline-staging-pack-not-installed' -or $manifest.runtimeEligible -ne $false -or
        $manifest.installationPerformed -ne $false -or $manifest.liveGameDirectoryTouched -ne $false -or $Pack.Installed -ne $false) {
        throw "$ExpectedPreset pack escaped its offline no-install boundary."
    }
    if ($manifest.preset -ne $ExpectedPreset -or [Math]::Abs([double]$manifest.power - $ExpectedPower) -gt 0.000001) {
        throw "$ExpectedPreset pack identity is invalid."
    }
    if ($manifest.keyContract.F1 -ne 'not claimed; future global mod on/off' -or
        $manifest.keyContract.F2 -ne 'binary native/candidate test toggle' -or
        $manifest.keyContract.F3 -ne 'not claimed; unassigned') {
        throw "$ExpectedPreset pack key ownership is invalid."
    }
    if ($manifest.keyContract.defaultState -ne 0 -or $manifest.keyContract.off -ne 'native game shader fallthrough' -or $manifest.overrideContract.offBranchHasReplacementRun -ne $false) {
        throw "$ExpectedPreset pack does not fail closed to native."
    }
    if ([regex]::Matches($ini, '(?im)^\s*key\s*=\s*no_modifiers\s+F2\s*$').Count -ne 1) { throw "$ExpectedPreset pack does not have exactly one F2 binding." }
    if ($ini -match '(?im)^\s*key\s*=.*(?:F1|F3|PAGEUP|PAGEDOWN)\s*$') { throw "$ExpectedPreset pack claimed a forbidden key." }
    if ([regex]::Matches($ini, '(?im)^\s*hash\s*=\s*a77b589dce5822d6\s*$').Count -ne 1) { throw "$ExpectedPreset pack AO override count is invalid." }
    if ([regex]::Matches($ini, '(?im)^\s*run\s*=\s*CustomShaderIntergradeTemporalAOF2Candidate\s*$').Count -ne 1) { throw "$ExpectedPreset pack candidate run count is invalid." }
    if ($ini -notmatch '(?ms)^if \$intergrade_temporal_ao_f2_test == 1\r?\n\s+run = CustomShaderIntergradeTemporalAOF2Candidate\r?\nendif\s*$') {
        throw "$ExpectedPreset pack does not gate its only replacement run on F2 ON."
    }
    foreach ($pair in @(@($Pack.Ini,$manifest.iniSha256),@($Pack.Shader,$manifest.shaderSha256))) {
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $pair[0]).Hash -ne $pair[1]) { throw "$ExpectedPreset pack artifact hash mismatch." }
    }
}

$runtimeBefore = Get-TreeHashes $runtimeRoot
$balancedA = & $generator -Preset Balanced -OutputDirectory $firstRoot
$balancedB = & $generator -Preset Balanced -OutputDirectory $secondRoot
$strong = & $generator -Preset Strong -OutputDirectory $strongRoot
Assert-Pack $balancedA 'Balanced' 1.25
Assert-Pack $balancedB 'Balanced' 1.25
Assert-Pack $strong 'Strong' 1.50
if ($balancedA.IniSha256 -ne $balancedB.IniSha256 -or $balancedA.ShaderSha256 -ne $balancedB.ShaderSha256 -or $balancedA.ObjectSha256 -ne $balancedB.ObjectSha256) {
    throw 'Balanced F2 test-pack generation is not deterministic.'
}
if ($balancedA.ShaderSha256 -eq $strong.ShaderSha256 -or $balancedA.ObjectSha256 -eq $strong.ObjectSha256) {
    throw 'Balanced and Strong F2 packs unexpectedly contain identical shaders.'
}

foreach ($negativeName in @('f2-conflict','ao-hash-conflict')) {
    $fakeRuntime = Join-Path $negativeRoot $negativeName
    New-Item -ItemType Directory -Path $fakeRuntime -Force | Out-Null
    $fakeIni = if ($negativeName -eq 'f2-conflict') {
        "[KeyConflict]`r`nkey = no_modifiers F2`r`n"
    } else {
        "[ShaderOverrideConflict]`r`nhash = a77b589dce5822d6`r`n"
    }
    [IO.File]::WriteAllText((Join-Path $fakeRuntime 'Conflict.ini'), $fakeIni, [Text.UTF8Encoding]::new($false))
    $rejectedOutput = Join-Path $negativeRoot "$negativeName-output"
    $rejected = $false
    try {
        & $generator -Preset Balanced -OutputDirectory $rejectedOutput -ConflictScanRoots @($fakeRuntime) | Out-Null
    } catch {
        if ($_.Exception.Message -notmatch 'Refusing F2 AO pack') { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw "Generator accepted $negativeName." }
    if (Test-Path -LiteralPath $rejectedOutput) { throw "Rejected $negativeName emitted pack artifacts." }
}

$runtimeAfter = Get-TreeHashes $runtimeRoot
Compare-HashMaps $runtimeBefore $runtimeAfter 'Project runtime'

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    shaderHash = 'a77b589dce5822d6'
    presets = @(
        [ordered]@{name='Balanced';power=1.25;iniSha256=$balancedA.IniSha256;shaderSha256=$balancedA.ShaderSha256;objectSha256=$balancedA.ObjectSha256},
        [ordered]@{name='Strong';power=1.50;iniSha256=$strong.IniSha256;shaderSha256=$strong.ShaderSha256;objectSha256=$strong.ObjectSha256}
    )
    deterministicBalancedBuild = $true
    F1Claimed = $false
    F2BinaryNativeCandidateToggle = $true
    F3Claimed = $false
    defaultAndOffPath = 'native game shader fallthrough'
    conflictRejection = @('active F2 binding','active a77b589dce5822d6 override')
    projectRuntimeUnchanged = $true
    liveGameDirectoryTouched = $false
}
$reportPath = Join-Path $runRoot 'report.json'
[IO.File]::WriteAllText($reportPath, (($report | ConvertTo-Json -Depth 10) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

Write-Output 'Intergrade temporal-AO F2 offline test-pack validation passed.'
Write-Output "Report: $reportPath"
