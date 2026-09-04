[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(-not $output.StartsWith((Join-Path $repo 'artifacts')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)) {throw 'Use a new workspace artifact directory.'}
$null=New-Item -ItemType Directory -Path $output
$audit=Join-Path $repo 'artifacts/contact-plane-audit-20260831-v13'
$replay=Join-Path $repo 'artifacts/contact-capture-replay-20260831-v4'
$validation=Join-Path $repo 'artifacts/contact-candidate-validation-20260831-v6'
$gate=Join-Path $PSScriptRoot 'Assert-IntergradeContactSoftwareGate.ps1'
$results=[Collections.Generic.List[object]]::new()
$positive=& $gate -PlaneAuditDirectory $audit -CaptureReplayDirectory $replay -CandidateValidationDirectory $validation
if($positive.result -ne 'passed') {throw 'Positive gate check failed.'}
$results.Add(@{case='matching-current-evidence';result='passed'})
$utf8=[Text.UTF8Encoding]::new($false)
foreach($case in @('failed-audit','stale-source','lost-visible-blocker','missing-replay-case','nonneutral-off','invalid-on')) {
    $root=Join-Path $output $case
    $testAudit=Join-Path $root 'audit';$testReplay=Join-Path $root 'replay'
    $null=New-Item -ItemType Directory -Path $testAudit,$testReplay
    foreach($file in @('manifest.json','results.csv','Audit-ContactShadowPlanes.exe')) {Copy-Item -LiteralPath (Join-Path $audit $file) -Destination $testAudit}
    foreach($file in @('manifest.json','results.csv','ReplayContact.exe')) {Copy-Item -LiteralPath (Join-Path $replay $file) -Destination $testReplay}
    foreach($file in @(Get-ChildItem -LiteralPath $replay -Filter '*.f32' -File)) {Copy-Item -LiteralPath $file.FullName -Destination $testReplay}
    switch($case) {
        'failed-audit' {
            $path=Join-Path $testAudit 'manifest.json';$doc=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            $doc.regressionDetected=$true
            [IO.File]::WriteAllText($path,($doc|ConvertTo-Json -Depth 10),$utf8)
            $expected='missing or failed expanded plane audit'
        }
        'stale-source' {
            $path=Join-Path $testReplay 'manifest.json';$doc=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            $doc.sources[0].sha256=('0'*64)
            [IO.File]::WriteAllText($path,($doc|ConvertTo-Json -Depth 10),$utf8)
            $expected='tested source changed'
        }
        'lost-visible-blocker' {
            $path=Join-Path $testAudit 'results.csv';$rows=@(Import-Csv -LiteralPath $path)
            ($rows | Where-Object expectedShadow -eq '1' | Select-Object -First 1).visibility='1'
            $rows | Export-Csv -LiteralPath $path -NoTypeInformation
            $expected='visible blocker was lost'
        }
        'missing-replay-case' {
            $path=Join-Path $testReplay 'results.csv';$rows=@(Import-Csv -LiteralPath $path)
            $rows[0..8] | Export-Csv -LiteralPath $path -NoTypeInformation
            $expected='incomplete replay results'
        }
        'nonneutral-off' {
            $path=Join-Path $testReplay 'light-50-0.f32';$bytes=[IO.File]::ReadAllBytes($path)
            [BitConverter]::GetBytes([single]0.5).CopyTo($bytes,0);[IO.File]::WriteAllBytes($path,$bytes)
            $expected='invalid/modified replay readback'
        }
        'invalid-on' {
            $path=Join-Path $testReplay 'light-50-1.f32';$bytes=[IO.File]::ReadAllBytes($path)
            [BitConverter]::GetBytes([single]::NaN).CopyTo($bytes,0);[IO.File]::WriteAllBytes($path,$bytes)
            $expected='invalid/modified replay readback'
        }
    }
    $caught=$null
    try {$null=& $gate -PlaneAuditDirectory $testAudit -CaptureReplayDirectory $testReplay -CandidateValidationDirectory $validation}
    catch {$caught=$_.Exception.Message}
    if(-not $caught -or -not $caught.Contains($expected)) {throw "Gate did not reject $case correctly: $caught"}
    $results.Add(@{case=$case;result='rejected-as-expected';message=$caught})
}
$report=@{result='passed';tests=$results.ToArray();positiveEvidence=$positive;gameFilesModified=$false;createdAtUtc=[DateTime]::UtcNow.ToString('o')}
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),($report|ConvertTo-Json -Depth 10),$utf8)
[pscustomobject]@{result='passed';checks=$results.Count;output=$output;gameFilesModified=$false}
