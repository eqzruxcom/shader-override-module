[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\agent2-r3d-ssgi-standalone-stage-rollback.json'),
    [string]$LiveModsDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\Mods'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$stager = Join-Path $root 'tools\Stage-IntergradeR3DSSGIF2Standalone.ps1'
$pack = Join-Path $root 'artifacts\agent2-r3d-ssgi-f2-standalone-pack'
$manifest = Join-Path $pack 'manifest.json'
$owner = Join-Path $root 'runtime\Intergrade\Mods\RebirthEffectsDX11.ini'
$testBase = Join-Path $root 'artifacts\agent2-r3d-ssgi-f2-standalone-stage-test'
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
    if ([string]::Join([Environment]::NewLine,$Expected.Keys) -cne [string]::Join([Environment]::NewLine,$Actual.Keys)) {
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
    [IO.File]::Copy($owner, (Join-Path $mods 'RebirthEffectsDX11.ini.disabled'), $false)
    $lf = [char]10
    $generated = '; Obsolete final-scene/fog comparison removed.' + $lf +
        '; Page Down is reserved for the generated per-shader injected-code master A/B.' + $lf +
        '; No runtime binding is intentionally declared here.' + $lf
    [IO.File]::WriteAllText((Join-Path $mods 'UE4EffectsGenerated.ini'), $generated, [Text.UTF8Encoding]::new($false))
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $mods 'UE4EffectsGenerated.ini')).Hash -ne 'D198023FB70F9F02CC8588D3E022AA7AC43AC2BC04AA460B70353285DD065B08') {
        throw 'Generated-INI fixture does not reproduce the exact live fingerprint.'
    }
    [ordered]@{Root=$fixtureRoot; Mods=$mods; Backups=(Join-Path $fixtureRoot 'backups')}
}

function Write-Conflict([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, ($Text + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

$liveAvailable = Test-Path -LiteralPath $LiveModsDirectory -PathType Container
$liveBefore = if ($liveAvailable) { Get-TreeHashes $LiveModsDirectory } else { $null }
$negativeResults = [Collections.Generic.List[string]]::new()
try {
    $fixture = New-Fixture 'clean'
    $fixtureBefore = Get-TreeHashes $fixture.Mods
    $pre = & $stager -Action Status -PackManifest $manifest -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups
    if ($pre.Status -ne 'not-staged' -or $pre.Installed -ne $false -or $pre.Baseline -ne 'exact') {
        throw 'Standalone pre-stage status did not verify the exact baseline.'
    }

    $ackRejected = $false
    try {
        & $stager -Action Stage -PackManifest $manifest -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups -Confirm:$false | Out-Null
    } catch {
        $ackRejected = $_.Exception.Message -match 'AcknowledgeOfflineCandidate'
    }
    if (-not $ackRejected -or (Test-Path -LiteralPath $fixture.Backups)) {
        throw 'Standalone Stage did not refuse missing acknowledgement before writing.'
    }

    $stage = & $stager -Action Stage -PackManifest $manifest -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups -AcknowledgeOfflineCandidate -Confirm:$false
    if ($stage.Status -ne 'staged' -or $stage.Installed -ne $true -or $stage.Files -ne 7 -or $stage.RuntimeEligible -ne $false) {
        throw 'Standalone fixture did not stage exactly seven fail-closed files.'
    }
    $status = & $stager -Action Status -PackManifest $manifest -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups
    if ($status.Status -ne 'staged' -or $status.Installed -ne $true -or $status.Files -ne 7) { throw 'Standalone staged status failed.' }
    $state = Get-Content -Raw -LiteralPath $stage.State | ConvertFrom-Json
    if (@($state.baselineBackups).Count -ne 2) { throw 'Standalone stage did not preserve both topology fingerprints.' }
    foreach ($item in @($state.baselineBackups)) {
        if (-not (Test-Path -LiteralPath $item.path -PathType Leaf) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $item.path).Hash -ne [string]$item.sha256) {
            throw "Standalone topology backup is invalid: $($item.name)"
        }
    }
    $stagedIni = Join-Path $fixture.Mods 'Agent2R3DSSGITest.ini'
    $stagedText = Get-Content -Raw -LiteralPath $stagedIni
    if ([regex]::Matches($stagedText,'(?im)^\s*key\s*=.*F1\s*$').Count -ne 0 -or
        [regex]::Matches($stagedText,'(?im)^\s*key\s*=.*F2\s*$').Count -ne 1 -or
        [regex]::Matches($stagedText,'(?im)^\s*key\s*=.*F3\s*$').Count -ne 0 -or
        [regex]::Matches($stagedText,'(?im)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$').Count -ne 1 -or
        $stagedText -match 'rebirth_ab_current|CustomShaderRebirthAB') {
        throw 'Standalone staged control/owner contract changed.'
    }

    $trace = Join-Path $fixture.Mods 'Agent2R3DSSGITraceE2AA_ps.hlsl'
    [IO.File]::AppendAllText($trace, ([Environment]::NewLine + '// drift'), [Text.UTF8Encoding]::new($false))
    if ((& $stager -Action Status -PackManifest $manifest -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups).Status -ne 'drifted') {
        throw 'Standalone Status did not detect shader drift.'
    }
    $restoreRejected = $false
    try {
        & $stager -Action Restore -PackManifest $manifest -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups -Confirm:$false | Out-Null
    } catch {
        $restoreRejected = $_.Exception.Message -match 'drifted'
    }
    if (-not $restoreRejected) { throw 'Standalone Restore did not reject shader drift.' }
    [IO.File]::Copy((Join-Path $pack 'Mods\Agent2R3DSSGITraceE2AA_ps.hlsl'), $trace, $true)

    $restore = & $stager -Action Restore -PackManifest $manifest -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups -Confirm:$false
    if ($restore.Status -ne 'restored' -or $restore.Installed -ne $false -or $restore.Files -ne 7) { throw 'Standalone exact Restore failed.' }
    $restoredStatus = & $stager -Action Status -PackManifest $manifest -TargetModsDirectory $fixture.Mods -BackupRoot $fixture.Backups
    if ($restoredStatus.Status -ne 'restored' -or $restoredStatus.Installed -ne $false) { throw 'Standalone restored Status failed.' }
    Assert-MapsEqual $fixtureBefore (Get-TreeHashes $fixture.Mods) 'Standalone restored fixture'

    $whatIf = New-Fixture 'what-if'
    $whatIfBefore = Get-TreeHashes $whatIf.Mods
    & $stager -Action Stage -PackManifest $manifest -TargetModsDirectory $whatIf.Mods -BackupRoot $whatIf.Backups -AcknowledgeOfflineCandidate -WhatIf | Out-Null
    Assert-MapsEqual $whatIfBefore (Get-TreeHashes $whatIf.Mods) 'Standalone WhatIf fixture'
    if (Test-Path -LiteralPath $whatIf.Backups) { throw 'Standalone WhatIf created backup/state data.' }

    foreach ($caseName in @('active-owner','disabled-owner-drift','generated-ini-drift','f1-conflict','f2-conflict','f3-conflict','e2aa-conflict','agent2-file-present')) {
        $negative = New-Fixture $caseName
        if ($caseName -eq 'active-owner') {
            [IO.File]::Copy($owner, (Join-Path $negative.Mods 'RebirthEffectsDX11.ini'), $false)
        } elseif ($caseName -eq 'disabled-owner-drift') {
            [IO.File]::AppendAllText((Join-Path $negative.Mods 'RebirthEffectsDX11.ini.disabled'), '; drift', [Text.UTF8Encoding]::new($false))
        } elseif ($caseName -eq 'generated-ini-drift') {
            [IO.File]::AppendAllText((Join-Path $negative.Mods 'UE4EffectsGenerated.ini'), '; drift', [Text.UTF8Encoding]::new($false))
        } elseif ($caseName -eq 'f1-conflict') {
            Write-Conflict (Join-Path $negative.Mods 'Conflict.ini') ('[KeyConflict]' + [Environment]::NewLine + 'key = no_modifiers F1')
        } elseif ($caseName -eq 'f2-conflict') {
            Write-Conflict (Join-Path $negative.Mods 'Conflict.ini') ('[KeyConflict]' + [Environment]::NewLine + 'key = no_modifiers F2')
        } elseif ($caseName -eq 'f3-conflict') {
            Write-Conflict (Join-Path $negative.Mods 'Conflict.ini') ('[KeyConflict]' + [Environment]::NewLine + 'key = no_modifiers F3')
        } elseif ($caseName -eq 'e2aa-conflict') {
            Write-Conflict (Join-Path $negative.Mods 'Conflict.ini') ('[ShaderOverrideConflict]' + [Environment]::NewLine + 'hash = e2aa1c8cb39e0a55')
        } else {
            Write-Conflict (Join-Path $negative.Mods 'Agent2R3DSSGIConflict.txt') 'conflict'
        }
        $before = Get-TreeHashes $negative.Mods
        $rejected = $false
        try {
            & $stager -Action Stage -PackManifest $manifest -TargetModsDirectory $negative.Mods -BackupRoot $negative.Backups -AcknowledgeOfflineCandidate -Confirm:$false | Out-Null
        } catch {
            $rejected = $_.Exception.Message -match 'Active Rebirth owner|fingerprint drifted|zero F1|zero F2|zero F3|zero E2aa|already contains Agent 2'
        }
        if (-not $rejected) { throw "Standalone Stage accepted negative case: $caseName" }
        if (Test-Path -LiteralPath $negative.Backups) { throw "Rejected standalone Stage wrote backup/state data: $caseName" }
        Assert-MapsEqual $before (Get-TreeHashes $negative.Mods) "Rejected standalone $caseName fixture"
        $negativeResults.Add($caseName)
    }

    $externalRejected = $false
    try {
        & $stager -Action Status -PackManifest $manifest -TargetModsDirectory 'C:\Windows' -BackupRoot (Join-Path $runRoot 'external') | Out-Null
    } catch {
        $externalRejected = $_.Exception.Message -match 'External target requires'
    }
    if (-not $externalRejected) { throw 'Standalone external-target guard did not fail closed.' }

    if ($liveAvailable) {
        Assert-MapsEqual $liveBefore (Get-TreeHashes $LiveModsDirectory) 'Live Mods directory'
    }
    $report = [ordered]@{
        schemaVersion = 1
        result = 'pass'
        packageId = 'agent2-r3d-ssgi-f2-standalone'
        payloadFiles = 7
        baselineFingerprintBackups = 2
        fixtureActions = @('Status exact baseline','acknowledgement refusal','Stage','Status staged','Status drifted','Restore drift refusal','Restore without acknowledgement','Status restored','WhatIf')
        negativeStageCases = @($negativeResults)
        controls = [ordered]@{F1='reserved and unbound'; F2='exactly one standalone toggle'; F3='unbound live state preserved'}
        exactRemovalRollback = $true
        externalTargetRequiresOptIn = $true
        stageAcknowledgementRequired = $true
        restoreAcknowledgementRequired = $false
        liveDirectoryHashChecked = $liveAvailable
        liveGameDirectoryTouched = $false
        runtimeEligible = $false
    }
    $outputFull = [IO.Path]::GetFullPath($OutputPath)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull)) | Out-Null
    [IO.File]::WriteAllText($outputFull, (($report | ConvertTo-Json -Depth 10) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    [pscustomobject]@{Result='pass';PayloadFiles=7;NegativeCases=$negativeResults.Count;ExactRemovalRollback=$true;LiveDirectoryHashChecked=$liveAvailable;LiveGameDirectoryTouched=$false;RuntimeEligible=$false;Output=$outputFull}
}
finally {
    if (Test-Path -LiteralPath $runRoot -PathType Container) {
        [IO.Directory]::Delete([IO.Path]::GetFullPath($runRoot), $true)
    }
}
