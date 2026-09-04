[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-temporal-power-candidate-test')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$generator = Join-Path $repoRoot 'tools\New-IntergradeTemporalAOCandidate.ps1'
$first = Join-Path $OutputDirectory 'first'
$second = Join-Path $OutputDirectory 'second'
New-Item -ItemType Directory -Path $first,$second -Force | Out-Null

$runA = @(
    & $generator -Preset Balanced -OutputDirectory $first
    & $generator -Preset Strong -OutputDirectory $first
)
$runB = @(
    & $generator -Preset Balanced -OutputDirectory $second
    & $generator -Preset Strong -OutputDirectory $second
)
if ($runA.Count -ne 2 -or $runB.Count -ne 2) { throw 'Expected two AO candidates in each deterministic build.' }

for ($i = 0; $i -lt 2; $i++) {
    if ($runA[$i].SourceSha256 -ne $runB[$i].SourceSha256 -or $runA[$i].ObjectSha256 -ne $runB[$i].ObjectSha256) {
        throw "AO candidate build is not deterministic for $($runA[$i].Preset)."
    }
    $manifest = Get-Content -Raw -LiteralPath $runA[$i].Manifest | ConvertFrom-Json
    if ($manifest.runtimeEligible -ne $false -or $manifest.installStatus -ne 'offline-not-installed' -or $manifest.hotkeysEmitted -ne $false) {
        throw "Offline fail-closed contract is invalid for $($runA[$i].Preset)."
    }
    if (($manifest.temporalContract.packedMetadataPreserved -join ',') -ne 'z,w' -or -not $manifest.temporalContract.currentVisibilityPoweredOnce -or $manifest.temporalContract.historySampleRepowered) {
        throw "Temporal packing contract is invalid for $($runA[$i].Preset)."
    }
    if (($manifest.reservedFutureControls -join ',') -ne 'F1,F2,F3') { throw 'AO future-control ownership changed.' }
    if ($manifest.futureControlPlan.F1 -ne 'Original/native AO' -or
        $manifest.futureControlPlan.F2 -ne 'Balanced power 1.25' -or
        $manifest.futureControlPlan.F3 -ne 'Strong power 1.50') { throw 'AO future-control mapping changed.' }
    if ($manifest.futureControlOwnership.F1 -ne 'AO Original' -or $manifest.futureControlOwnership.F2 -ne 'AO Balanced' -or $manifest.futureControlOwnership.F3 -ne 'AO Strong') {
        throw 'AO future-control ownership changed.'
    }

    $source = Get-Content -Raw -LiteralPath $runA[$i].Source
    $currentIndex = $source.IndexOf('r2.w = max(0, r2.x);', [StringComparison]::Ordinal)
    $powerIndex = $source.IndexOf('r2.w = RemakeTemporalAOApplyCurrentPower', [StringComparison]::Ordinal)
    $historyIndex = $source.IndexOf('r0.xyw = t3.SampleLevel', [StringComparison]::Ordinal)
    $outputIndex = $source.IndexOf('o0.xyzw = r2.wxyz;', [StringComparison]::Ordinal)
    if (-not (0 -le $currentIndex -and $currentIndex -lt $powerIndex -and $powerIndex -lt $historyIndex -and $historyIndex -lt $outputIndex)) {
        throw "Current-power/history/output ordering is invalid for $($runA[$i].Preset)."
    }
    if ([regex]::Matches($source, 'RemakeTemporalAOApplyCurrentPower\(r2\.w,').Count -ne 1) { throw 'Current visibility must be powered exactly once.' }
}

if ($runA[0].ObjectSha256 -eq $runA[1].ObjectSha256) { throw 'Balanced and Strong candidates unexpectedly compiled identically.' }

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    shaderHash = 'a77b589dce5822d6'
    candidates = @($runA | ForEach-Object { [ordered]@{ preset=$_.Preset; power=$_.Power; sourceSha256=$_.SourceSha256; objectSha256=$_.ObjectSha256 } })
    deterministicSecondBuild = $true
    currentVisibilityPoweredBeforeHistorySelection = $true
    metadataPreserved = @('z','w')
    runtimeEligible = $false
    hotkeysEmitted = $false
}
$reportPath = Join-Path $OutputDirectory 'report.json'
[IO.File]::WriteAllText($reportPath, (($report | ConvertTo-Json -Depth 10) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Output 'Intergrade temporal-AO offline candidate tests passed.'
Write-Output "Report: $reportPath"
