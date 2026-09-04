[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CandidateDirectory,
    [Parameter(Mandatory)][string]$TestBuildDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory
)
# Interface diagnostics only. This is NOT the quality-gated deployment validator.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if(-not $output.StartsWith((Join-Path $repo 'artifacts')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)) {throw 'Use a new workspace artifacts directory.'}
$candidate=(Resolve-Path -LiteralPath $CandidateDirectory).Path
$build=(Resolve-Path -LiteralPath $TestBuildDirectory).Path
$report=Get-Content -LiteralPath (Join-Path $candidate 'candidate.json') -Raw | ConvertFrom-Json
if($report.PSObject.Properties.Name -contains 'reconstruction' -and $report.reconstruction -eq 'SharedQuad'){throw 'SharedQuad needs a full 256-thread fixture runner; the single-thread interface test is not valid.'}
$tests=Get-Content -LiteralPath (Join-Path $build 'manifest.json') -Raw | ConvertFrom-Json
$runner=Join-Path $build 'ContactShadowWarpTest.exe'
if($report.implementation -ne 'Rebirth' -or $tests.implementation -ne 'Rebirth' -or $tests.result -ne 'passed') {throw 'Require tested Rebirth sources.'}
if($tests.runnerSha256 -ne (Get-FileHash -LiteralPath $runner).Hash -or $tests.assemblyFixtureInputRows -ne 3 -or $tests.assemblyFixtureCases -ne 37 -or $tests.donorInputCasesPassed -ne 34) {throw 'Runner contract mismatch.'}
foreach($source in @($tests.sources)+@($report.sources)) {
    if($source.sha256 -ne (Get-FileHash -LiteralPath (Join-Path $repo $source.path)).Hash) {throw "Source changed: $($source.path)"}
}
if($report.variants.Count -ne 5) {throw 'Expected five native variants.'}
$quad=$report.PSObject.Properties.Name -contains 'reconstruction' -and $report.reconstruction -eq 'RecomputeQuad'
if($quad -and ($tests.reconstructionCasesPassed -ne 34 -or $tests.reconstructionAdapterCasesPassed -ne 448)) {throw 'Reconstruction reference checks are incomplete.'}
$profileCaseCount=if($quad){296}else{37}
$profiles=@(@{frame=0;material=1},@{frame=61;material=231},@{frame=12345;material=248})
$null=New-Item -ItemType Directory -Path $output
$utf8=[Text.UTF8Encoding]::new($false)
function Run-Logged([string[]]$Arguments,[string]$Name) {
    $messages=& $runner @Arguments 2>&1
    $code=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $output $Name),($messages|Out-String),$utf8)
    if($code -ne 0) {throw "Interface diagnostic failed: $Name"}
    return ,@($messages)
}
$records=@(foreach($variant in $report.variants) {
    $binary=Join-Path $candidate $variant.binary
    $original=Join-Path $candidate ('validation/'+$variant.shaderHash+'-original.bin')
    $fixture=Join-Path $candidate $variant.injectionFixture
    if($variant.fixtureInputRows -ne 3 -or -not $variant.zeroNativeContributionGate -or (Get-FileHash -LiteralPath $original).Hash -ne $variant.originalSha256 -or (Get-FileHash -LiteralPath $binary).Hash -ne $variant.candidateSha256) {throw 'Candidate bytes/fixture contract changed.'}
    $null=Run-Logged @('--validate-cs',$original,$binary,$fixture) ($variant.shaderHash+'-creation.log')
    foreach($profile in $profiles) {
        $log=$variant.shaderHash+'-frame'+$profile.frame+'-material'+$profile.material+'.log'
        $fixtureArgs=@('--adapter-assembly',$fixture,[string]$variant.depthSlot,$variant.diffuse.Split('.')[1],$variant.specular.Split('.')[1],[string]$profile.frame,[string]$profile.material)
        if($quad) {$fixtureArgs[0]='--adapter-assembly-reconstruction';$fixtureArgs+=Join-Path $repo 'src/Tests/RebirthContactReconstructedAdapter_cs.hlsl'}
        $result=Run-Logged $fixtureArgs $log
        if(@($result | Where-Object {$_ -match '^PASS t[45] '}).Count -ne $profileCaseCount) {throw "Incomplete fixture cases: $log"}
    }
    Write-Host "PASS $($variant.shaderHash): 3 creation checks; $($profileCaseCount*$profiles.Count) isolated injection cases."
    @{shaderHash=$variant.shaderHash;candidateSha256=$variant.candidateSha256;fixtureSha256=(Get-FileHash -LiteralPath $fixture).Hash;creationChecks=3;injectionCases=($profileCaseCount*$profiles.Count)}
})
$manifest=[ordered]@{
    schemaVersion=1;generatedAtUtc=[DateTime]::UtcNow.ToString('o')
    result='passed-interface-only';implementation='Rebirth'
    candidateDirectory=$candidate;candidateManifestSha256=(Get-FileHash -LiteralPath (Join-Path $candidate 'candidate.json')).Hash
    testBuildDirectory=$build;testManifestSha256=(Get-FileHash -LiteralPath (Join-Path $build 'manifest.json')).Hash
    runnerSha256=(Get-FileHash -LiteralPath $runner).Hash;scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    profiles=$profiles;variants=$records;creationChecks=15;injectedBlockResourceCases=($profileCaseCount*$profiles.Count*$records.Count)
    reconstruction=$quad;quadPhases=$(if($quad){2}else{0});quadLanes=$(if($quad){4}else{0})
    installed=$false;runtimeEligible=$false;liveGameTested=$false;performanceTested=$false;qualityGatePassed=$false
    limitations=@('Synthetic textures and constant buffers; isolated block, not complete tiled native dispatch','No proof of native frame progression or visual material coverage','RecomputeQuad phase/helper coverage differs provisionally; no final game temporal AA','Does not satisfy or replace production quality gates')
}
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),($manifest|ConvertTo-Json -Depth 8)+"`n",$utf8)
