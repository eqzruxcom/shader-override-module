[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlaneAuditDirectory,
    [Parameter(Mandatory)][string]$CaptureReplayDirectory,
    [Parameter(Mandatory)][string]$CandidateValidationDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$auditPath=Join-Path $PlaneAuditDirectory 'manifest.json'
$replayPath=Join-Path $CaptureReplayDirectory 'manifest.json'
$validationPath=Join-Path $CandidateValidationDirectory 'manifest.json'
$audit=Get-Content -LiteralPath $auditPath -Raw | ConvertFrom-Json
$replay=Get-Content -LiteralPath $replayPath -Raw | ConvertFrom-Json
$validation=Get-Content -LiteralPath $validationPath -Raw | ConvertFrom-Json
if($audit.execution -ne 'completed-offline-WARP' -or $audit.regressionDetected -isnot [bool] -or
   $audit.regressionDetected -or $audit.caseCount -ne 20480) {throw 'Software gate: missing or failed expanded plane audit.'}
if($validation.result -ne 'passed' -or $validation.planeAuditCases -ne 20480 -or
   $validation.planeAuditManifestSha256 -ne (Get-FileHash -LiteralPath $auditPath).Hash) {throw 'Software gate: native validation did not use this plane audit.'}
if($replay.execution -ne 'D3D11 WARP production-kernel replay of captured resources' -or
   $replay.sampleStride -ne 8 -or ($replay.grid -join ',') -ne '480,270') {throw 'Software gate: missing captured-resource replay.'}
foreach($report in @($audit,$replay)) {
    if(@($report.sources).Count -lt 5) {throw 'Software gate: incomplete source fingerprints.'}
    foreach($source in $report.sources) {
        if((Get-FileHash -LiteralPath (Join-Path $repo $source.path)).Hash -ne $source.sha256) {
            throw "Software gate: tested source changed: $($source.path)"
        }
    }
}
if((Get-FileHash -LiteralPath (Join-Path $PlaneAuditDirectory 'Audit-ContactShadowPlanes.exe')).Hash -ne $audit.runnerSha256 -or
   (Get-FileHash -LiteralPath (Join-Path $CaptureReplayDirectory 'ReplayContact.exe')).Hash -ne $replay.runnerSha256) {throw 'Software gate: runner fingerprint mismatch.'}
# Check actual results as well as summary flags. NaN must never evade comparisons.
$planeRows=@(Import-Csv -LiteralPath (Join-Path $PlaneAuditDirectory 'results.csv'))
if($planeRows.Count -ne 20480 -or @($planeRows.case | Sort-Object -Unique).Count -ne 20480) {throw 'Software gate: incomplete plane results.'}
$visibleBlockers=0;$unobstructed=0;$clippedBlockers=0
foreach($row in $planeRows) {
    $visibility=[double]::Parse($row.visibility,[Globalization.CultureInfo]::InvariantCulture)
    if([double]::IsNaN($visibility) -or [double]::IsInfinity($visibility) -or $visibility -lt 0 -or $visibility -gt 1) {throw 'Software gate: invalid plane visibility.'}
    if($row.hasBlocker -notin @('0','1') -or $row.expectedShadow -notin @('0','1')) {throw 'Software gate: invalid plane case classification.'}
    if($row.expectedShadow -eq '1') {
        $visibleBlockers++
        if($row.hasBlocker -ne '1' -or $visibility -ge 0.5) {throw 'Software gate: visible blocker was lost.'}
    } else {
        if($row.hasBlocker -eq '0') {$unobstructed++} else {$clippedBlockers++}
        if([Math]::Abs($visibility-1) -gt 1e-6) {throw 'Software gate: false plane/hidden-box shadow.'}
    }
}
if($visibleBlockers -ne 10112 -or $unobstructed -ne 10240 -or $clippedBlockers -ne 128) {throw 'Software gate: unexpected audit coverage.'}
$rows=@(Import-Csv -LiteralPath (Join-Path $CaptureReplayDirectory 'results.csv'))
if($rows.Count -ne 10 -or @($replay.results).Count -ne 10) {throw 'Software gate: incomplete replay results.'}
foreach($light in @(50,38,54,20,52)) {
    foreach($enabled in @(0,1)) {
        $match=@($rows | Where-Object {$_.light -eq [string]$light -and $_.enabled -eq [string]$enabled})
        if($match.Count -ne 1) {throw 'Software gate: missing/duplicate replay case.'}
        $row=$match[0]
        if([int]$row.count -ne 129600 -or [int]$row.finite -ne 129600 -or [int]$row.rayLength -ne 100) {throw 'Software gate: invalid replay samples.'}
        if($enabled -eq 0 -and ([int]$row.changed -ne 0 -or [double]$row.min -ne 1 -or [double]$row.mean -ne 1)) {throw 'Software gate: OFF is not neutral.'}
        if($enabled -eq 1 -and [int]$row.changed -le 0) {throw 'Software gate: all replay occluders lost.'}
        # Numerical result files are the actual readback, not just console totals.
        $bytes=[IO.File]::ReadAllBytes((Join-Path $CaptureReplayDirectory "light-$light-$enabled.f32"))
        if($bytes.Length -ne 129600*4) {throw 'Software gate: incomplete replay readback.'}
        $readbackChanged=0
        for($i=0;$i -lt $bytes.Length;$i+=4) {
            $value=[BitConverter]::ToSingle($bytes,$i)
            if([single]::IsNaN($value) -or [single]::IsInfinity($value) -or $value -lt 0 -or $value -gt 1 -or ($enabled -eq 0 -and $value -ne 1)) {throw 'Software gate: invalid/modified replay readback.'}
            if($value -lt [single]0.999) {$readbackChanged++}
        }
        if($readbackChanged -ne [int]$row.changed) {throw 'Software gate: replay summary differs from readback.'}
    }
}
[pscustomobject]@{
    result='passed';planeCases=20480;unobstructedCases=$unobstructed;visibleBlockerCases=$visibleBlockers;clippedBlockerCases=$clippedBlockers
    replayCases=10;replaySamples=1296000
    planeAuditManifestSha256=(Get-FileHash -LiteralPath $auditPath).Hash
    captureReplayManifestSha256=(Get-FileHash -LiteralPath $replayPath).Hash
    candidateValidationManifestSha256=(Get-FileHash -LiteralPath $validationPath).Hash
    gateScriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    liveQualityProven=$false;hardwareCostProven=$false
}
