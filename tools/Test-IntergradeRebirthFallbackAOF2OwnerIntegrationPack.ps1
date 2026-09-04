[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-rebirth-fallback-consumer-f2-owner-integration-pack-test'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$generator = Join-Path $repoRoot 'tools\New-IntergradeRebirthFallbackAOF2OwnerIntegrationPack.ps1'
$runtimeRoot = Join-Path $repoRoot 'runtime\Intergrade\Mods'
$owner = Join-Path $runtimeRoot 'RebirthEffectsDX11.ini'
$runRoot = Join-Path $OutputDirectory ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

function Get-TreeHashes([string]$Root) {
    $result = [ordered]@{}
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName) {
        $relative = $file.FullName.Substring($Root.Length + 1)
        $result[$relative] = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
    }
    $result
}
function Compare-HashMaps([Collections.IDictionary]$Before, [Collections.IDictionary]$After) {
    if (($Before.Keys -join "`n") -cne ($After.Keys -join "`n")) { throw 'Project runtime inventory changed.' }
    foreach ($key in $Before.Keys) { if ($Before[$key] -ne $After[$key]) { throw "Project runtime changed: $key" } }
}
function Assert-IntegratedPack([object]$Pack) {
    $manifest = Get-Content -Raw -LiteralPath $Pack.Manifest | ConvertFrom-Json
    $ini = Get-Content -Raw -LiteralPath $Pack.PatchedIni
    if ($manifest.status -ne 'offline-owner-integration-preview-not-installed' -or $manifest.runtimeEligible -ne $false -or
        $manifest.installationPerformed -ne $false -or $manifest.liveGameDirectoryTouched -ne $false -or $Pack.Installed -ne $false) {
        throw 'Owner-integration pack escaped its offline boundary.'
    }
    if ($manifest.existingOwner.exactSha256 -ne $Pack.OwnerSha256) { throw 'Owner SHA contract mismatch.' }
    if ($manifest.keyContract.F1 -ne 'not claimed; future global mod on/off' -or
        $manifest.keyContract.F2 -ne 'binary native-existing-owner/candidate test toggle' -or
        $manifest.keyContract.F3 -ne 'existing rolling A/B ownership preserved; not claimed by AO') {
        throw 'Owner-integration key contract is invalid.'
    }
    if ([regex]::Matches($ini, '(?im)^\s*key\s*=\s*no_modifiers\s+F2\s*$').Count -ne 1) { throw 'Integrated preview does not have exactly one F2 binding.' }
    if ($ini -match '(?im)^\s*key\s*=.*(?:F1|PAGEUP|PAGEDOWN)\s*$') { throw 'Integrated preview claimed a forbidden key.' }
    if ([regex]::Matches($ini, '(?im)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$').Count -ne 1) { throw 'Integrated preview has multiple e2aa owners.' }
    if ([regex]::Matches($ini, '(?im)^\s*run\s*=\s*CustomShaderIntergradeRebirthFallbackAOCandidate\s*$').Count -ne 1) { throw 'Integrated preview AO branch count is invalid.' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Pack.PatchedIni).Hash -ne $manifest.patchedIniSha256) { throw 'Patched INI hash mismatch.' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Pack.Shader).Hash -ne $manifest.shaderSha256) { throw 'Pack shader hash mismatch.' }
}

$before = Get-TreeHashes $runtimeRoot
$first = & $generator -OwnerIniPath $owner -OutputDirectory (Join-Path $runRoot 'first')
$second = & $generator -OwnerIniPath $owner -OutputDirectory (Join-Path $runRoot 'second')
Assert-IntegratedPack $first
Assert-IntegratedPack $second
if ($first.OwnerSha256 -ne $second.OwnerSha256 -or $first.PatchedIniSha256 -ne $second.PatchedIniSha256 -or
    $first.ShaderSha256 -ne $second.ShaderSha256 -or $first.ObjectSha256 -ne $second.ObjectSha256) {
    throw 'Owner-integration generation is not deterministic.'
}

$negativeRoot = Join-Path $runRoot 'negative'
New-Item -ItemType Directory -Path $negativeRoot -Force | Out-Null
$ownerText = [IO.File]::ReadAllText($owner)
$negativeCases = [ordered]@{
    existingF2 = $ownerText + "`r`n[KeyConflict]`r`nkey = no_modifiers F2`r`n"
    missingHash = $ownerText.Replace('hash = e2aa1c8cb39e0a55','hash = 0000000000000000')
    changedBody = $ownerText.Replace('if $rebirth_ab_current == 0','if $rebirth_ab_current != 0')
}
foreach ($case in $negativeCases.GetEnumerator()) {
    $casePath = Join-Path $negativeRoot "$($case.Key).ini"
    [IO.File]::WriteAllText($casePath, $case.Value, [Text.UTF8Encoding]::new($false))
    $caseOutput = Join-Path $negativeRoot "$($case.Key)-output"
    $rejected = $false
    try { & $generator -OwnerIniPath $casePath -OutputDirectory $caseOutput | Out-Null } catch { $rejected = $_.Exception.Message -match 'Refusing owner integration' }
    if (-not $rejected) { throw "Owner integration accepted negative case $($case.Key)." }
    if (Test-Path -LiteralPath $caseOutput) { throw "Rejected owner case emitted artifacts: $($case.Key)" }
}

$after = Get-TreeHashes $runtimeRoot
Compare-HashMaps $before $after
$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    effect = 'rebirth-native-ssao-fallback-consumer-f2-owner-integration'
    deterministicBuild = $true
    exactOwnerShaRequired = $true
    singleE2aaOwner = $true
    F1Claimed = $false
    F2ClaimedOnce = $true
    existingF3Preserved = $true
    negativeOwnerCases = @($negativeCases.Keys)
    projectRuntimeUnchanged = $true
    liveGameDirectoryTouched = $false
}
$reportPath = Join-Path $runRoot 'report.json'
[IO.File]::WriteAllText($reportPath, (($report | ConvertTo-Json -Depth 10) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Output 'Intergrade Rebirth fallback-AO F2 existing-owner integration tests passed.'
Write-Output "Report: $reportPath"
