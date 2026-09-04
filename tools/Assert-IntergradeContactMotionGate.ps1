[CmdletBinding()]
param([Parameter(Mandatory)][string]$MotionAuditDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$manifestPath=Join-Path $MotionAuditDirectory 'manifest.json'
$manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if($manifest.execution -ne 'completed-offline-WARP-synthetic-motion' -or $manifest.samples -ne 16 -or
   $manifest.framesPerScene -ne 96 -or $manifest.receiversPerFrame -ne 512 -or $manifest.scenes -ne 4 -or
   ($manifest.depthDimensions -join ',') -ne '1280,720') {throw 'Motion gate: incomplete or wrong-configuration evidence.'}
foreach($source in $manifest.sources) {
    if((Get-FileHash -LiteralPath (Join-Path $repo $source.path)).Hash -ne $source.sha256) {throw "Motion gate: tested source changed: $($source.path)"}
}
if((Get-FileHash -LiteralPath (Join-Path $MotionAuditDirectory 'Audit-ContactShadowMotion.exe')).Hash -ne $manifest.runnerSha256) {throw 'Motion gate: runner changed.'}
if($manifest.regressionDetected -isnot [bool] -or $manifest.regressionDetected) {
    throw 'Motion gate: audit reports unresolved shadow misses/false hits or large changes; do not deploy.'
}
$frames=@(Import-Csv -LiteralPath (Join-Path $MotionAuditDirectory 'frames.csv'))
if($frames.Count -ne 384) {throw 'Motion gate: incomplete frame results.'}
foreach($scene in 0..3) {
    $rows=@($frames | Where-Object scene -eq ([string]$scene))
    if($rows.Count -ne 96 -or @($rows.frame | Sort-Object -Unique).Count -ne 96) {throw 'Motion gate: missing or duplicate frames.'}
    foreach($row in $rows) {
        if([int]$row.active -le 0 -or [int]$row.falseHits -ne 0 -or [int]$row.missedVisibleBlockers -ne 0 -or
           [int]$row.stableTruthLargeChanges -ne 0 -or [double]$row.repeatMaxDifference -ne 0) {throw 'Motion gate: failing frame result.'}
    }
}
if((Get-Item -LiteralPath (Join-Path $MotionAuditDirectory 'visibility.f32')).Length -ne 384*512*4) {throw 'Motion gate: incomplete readback.'}
[pscustomobject]@{result='passed';manifestSha256=(Get-FileHash -LiteralPath $manifestPath).Hash;gateSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;engineMotionVerified=$false}
