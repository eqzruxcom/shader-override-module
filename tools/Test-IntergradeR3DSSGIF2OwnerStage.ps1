[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\agent2-r3d-ssgi-stage-rollback.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$stager = Join-Path $root 'tools\Stage-IntergradeR3DSSGIF2OwnerIntegration.ps1'
$packRoot = Join-Path $root 'artifacts\agent2-r3d-ssgi-f2-owner-integration-pack'
$packManifest = Join-Path $packRoot 'manifest.json'
$projectRuntime = Join-Path $root 'runtime\Intergrade\Mods'
$testBase = Join-Path $root 'artifacts\agent2-r3d-ssgi-f2-stage-test'
$runRoot = Join-Path $testBase ([Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($runRoot) | Out-Null

function Get-TreeHashes([string]$Path) {
    $map = [ordered]@{}
    foreach ($file in Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName) {
        $map[[IO.Path]::GetRelativePath($Path, $file.FullName)] = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
    }
    $map
}

function Assert-MapsEqual([Collections.IDictionary]$Expected, [Collections.IDictionary]$Actual, [string]$Label) {
    if ([string]::Join([Environment]::NewLine, $Expected.Keys) -cne [string]::Join([Environment]::NewLine, $Actual.Keys)) {
        throw "$Label inventory changed."
    }
    foreach ($key in $Expected.Keys) {
        if ($Expected[$key] -ne $Actual[$key]) { throw "$Label hash changed: $key" }
    }
}

function New-Fixture([string]$Name) {
    $fixtureRoot = Join-Path $runRoot $Name
    $mods = Join-Path $fixtureRoot 'Mods'
    [IO.Directory]::CreateDirectory($mods) | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $projectRuntime -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $mods -Recurse -Force
    }
    [ordered]@{Root=$fixtureRoot; Mods=$mods; Backups=(Join-Path $fixtureRoot 'backups')}
}

function Assert-KeyClaims([string]$Ini, [int]$F1, [int]$F2, [int]$F3) {
    $text = Get-Content -Raw -LiteralPath $Ini
    foreach ($key in @('F1','F2','F3')) {
        $expected = Get-Variable -Name $key -ValueOnly
        $actual = [regex]::Matches($text, "(?im)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?$key(?![A-Z0-9_]).*$").Count
        if ($actual -ne $expected) { throw "$key claim count is $actual, expected $expected." }
    }
}

$projectBefore = Get-TreeHashes $projectRuntime
$negativeResults = [Collections.Generic.List[string]]::new()
try {
    $fixture = New-Fixture 'clean'
    $fixtureBefore = Get-TreeHashes $fixture.Mods
    $owner = Join-Path $fixture.Mods 'RebirthEffectsDX11.ini'

    $pre = & $stager -Action Status -PackManifest $packManifest -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups
    if ($pre.Status -ne 'not-staged' -or $pre.Installed -ne $false) { throw 'Pre-stage status did not fail closed.' }

    $ackRejected = $false
    try {
        & $stager -Action Stage -PackManifest $packManifest -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups -Confirm:$false | Out-Null
    } catch {
        $ackRejected = $_.Exception.Message -match 'AcknowledgeOfflineCandidate'
    }
    if (-not $ackRejected -or (Test-Path -LiteralPath $fixture.Backups)) {
        throw 'Stage did not refuse missing candidate acknowledgement before writing.'
    }

    $stage = & $stager -Action Stage -PackManifest $packManifest -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups -AcknowledgeOfflineCandidate -Confirm:$false
    if ($stage.Status -ne 'staged' -or $stage.Installed -ne $true -or $stage.Files -ne 7 -or $stage.RuntimeEligible -ne $false) {
        throw 'Clean fixture did not stage the exact fail-closed seven-file package.'
    }
    $status = & $stager -Action Status -PackManifest $packManifest -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups
    if ($status.Status -ne 'staged' -or $status.Installed -ne $true -or $status.Files -ne 7) { throw 'Staged status verification failed.' }
    Assert-KeyClaims $owner 0 1 1
    $ownerText = Get-Content -Raw -LiteralPath $owner
    if ($ownerText -match 'endifif' -or $ownerText -notmatch '(?s)ResourceAgent2SSGIOriginalT110 = reference ps-t110.*?run = CustomShaderAgent2R3DSSGIComposite.*?ps-t114 = reference ResourceAgent2SSGIOriginalT114.*?endif\r?\nif \$rebirth_ab_current == 0') {
        throw 'Staged owner lost SRV restoration or clean F2/F3 branch ordering.'
    }
    foreach ($name in @(
        'Agent2R3DSSGICompositeE2AA_ps.hlsl',
        'Agent2R3DSSGIDenoise16_ps.hlsl',
        'Agent2R3DSSGIDenoise2_ps.hlsl',
        'Agent2R3DSSGIDenoise4_ps.hlsl',
        'Agent2R3DSSGIDenoise8_ps.hlsl',
        'Agent2R3DSSGITraceE2AA_ps.hlsl'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $fixture.Mods $name) -PathType Leaf)) { throw "Staged shader is missing: $name" }
    }

    $trace = Join-Path $fixture.Mods 'Agent2R3DSSGITraceE2AA_ps.hlsl'
    [IO.File]::AppendAllText($trace, ([Environment]::NewLine + '// drift test'), [Text.UTF8Encoding]::new($false))
    $drift = & $stager -Action Status -PackManifest $packManifest -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups
    if ($drift.Status -ne 'drifted') { throw 'Status did not detect staged shader drift.' }
    $restoreRejected = $false
    try {
        & $stager -Action Restore -PackManifest $packManifest -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups -Confirm:$false | Out-Null
    } catch {
        $restoreRejected = $_.Exception.Message -match 'drifted'
    }
    if (-not $restoreRejected) { throw 'Restore did not reject post-stage drift.' }
    Copy-Item -LiteralPath (Join-Path $packRoot 'Mods\Agent2R3DSSGITraceE2AA_ps.hlsl') -Destination $trace -Force

    $restore = & $stager -Action Restore -PackManifest $packManifest -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups -Confirm:$false
    if ($restore.Status -ne 'restored' -or $restore.Installed -ne $false -or $restore.Files -ne 7) { throw 'Exact restore failed.' }
    $restoredStatus = & $stager -Action Status -PackManifest $packManifest -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups
    if ($restoredStatus.Status -ne 'restored' -or $restoredStatus.Installed -ne $false) { throw 'Restored status verification failed.' }
    Assert-MapsEqual $fixtureBefore (Get-TreeHashes $fixture.Mods) 'Restored fixture'

    $whatIf = New-Fixture 'what-if'
    $whatIfBefore = Get-TreeHashes $whatIf.Mods
    & $stager -Action Stage -PackManifest $packManifest -TargetModsDirectory $whatIf.Mods -BackupRoot $whatIf.Backups -AcknowledgeOfflineCandidate -WhatIf | Out-Null
    Assert-MapsEqual $whatIfBefore (Get-TreeHashes $whatIf.Mods) 'WhatIf fixture'
    if (Test-Path -LiteralPath $whatIf.Backups) { throw 'WhatIf created backup or state data.' }

    foreach ($caseName in @('f1-conflict','f2-conflict','duplicate-owner','owner-drift')) {
        $negative = New-Fixture $caseName
        $negativeOwner = Join-Path $negative.Mods 'RebirthEffectsDX11.ini'
        if ($caseName -eq 'f1-conflict') {
            $content = '[KeyConflict]' + [Environment]::NewLine + 'key = no_modifiers F1' + [Environment]::NewLine
            [IO.File]::WriteAllText((Join-Path $negative.Mods 'Conflict.ini'), $content, [Text.UTF8Encoding]::new($false))
        } elseif ($caseName -eq 'f2-conflict') {
            $content = '[KeyConflict]' + [Environment]::NewLine + 'key = no_modifiers F2' + [Environment]::NewLine
            [IO.File]::WriteAllText((Join-Path $negative.Mods 'Conflict.ini'), $content, [Text.UTF8Encoding]::new($false))
        } elseif ($caseName -eq 'duplicate-owner') {
            $content = '[ShaderOverrideConflict]' + [Environment]::NewLine + 'hash = e2aa1c8cb39e0a55' + [Environment]::NewLine
            [IO.File]::WriteAllText((Join-Path $negative.Mods 'Conflict.ini'), $content, [Text.UTF8Encoding]::new($false))
        } else {
            [IO.File]::AppendAllText($negativeOwner, ([Environment]::NewLine + '; owner drift'), [Text.UTF8Encoding]::new($false))
        }
        $before = Get-TreeHashes $negative.Mods
        $rejected = $false
        try {
            & $stager -Action Stage -PackManifest $packManifest -TargetModsDirectory $negative.Mods -BackupRoot $negative.Backups -AcknowledgeOfflineCandidate -Confirm:$false | Out-Null
        } catch {
            $rejected = $_.Exception.Message -match 'F1|F2|exactly one e2aa|owner SHA changed'
        }
        if (-not $rejected) { throw "Stage accepted negative case: $caseName" }
        if (Test-Path -LiteralPath $negative.Backups) { throw "Rejected stage wrote backup/state data: $caseName" }
        Assert-MapsEqual $before (Get-TreeHashes $negative.Mods) "Rejected $caseName fixture"
        $negativeResults.Add($caseName)
    }

    $externalRejected = $false
    try {
        & $stager -Action Status -PackManifest $packManifest -TargetModsDirectory 'C:\Windows' -BackupRoot (Join-Path $runRoot 'external-guard') | Out-Null
    } catch {
        $externalRejected = $_.Exception.Message -match 'External target requires'
    }
    if (-not $externalRejected) { throw 'External target guard did not fail closed.' }

    Assert-MapsEqual $projectBefore (Get-TreeHashes $projectRuntime) 'Project runtime'
    $report = [ordered]@{
        schemaVersion = 1
        result = 'pass'
        packageId = 'agent2-r3d-ssgi-f2-owner-integration'
        payloadFiles = 7
        fixtureActions = @('Status not-staged','acknowledgement refusal','Stage','Status staged','Status drifted','Restore drift refusal','Restore','Status restored','WhatIf')
        negativeStageCases = @($negativeResults)
        controls = [ordered]@{F1='reserved and unbound'; F2='exactly one candidate toggle'; F3='exactly one preserved rolling A/B'}
        exactBackupAndRestore = $true
        externalTargetRequiresOptIn = $true
        stageAcknowledgementRequired = $true
        restoreAcknowledgementRequired = $false
        projectRuntimeUnchanged = $true
        liveGameDirectoryTouched = $false
        runtimeEligible = $false
    }
    $outputFull = [IO.Path]::GetFullPath($OutputPath)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull)) | Out-Null
    [IO.File]::WriteAllText($outputFull, (($report | ConvertTo-Json -Depth 10) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    [pscustomobject]@{Result='pass'; PayloadFiles=7; NegativeCases=$negativeResults.Count; ExactRestore=$true; ProjectRuntimeUnchanged=$true; LiveGameDirectoryTouched=$false; RuntimeEligible=$false; Output=$outputFull}
}
finally {
    if (Test-Path -LiteralPath $runRoot -PathType Container) {
        [IO.Directory]::Delete([IO.Path]::GetFullPath($runRoot), $true)
    }
}
