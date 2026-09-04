[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CandidateDirectory,
    [Parameter(Mandatory)][string]$TestBuildDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [switch]$Repeated
)
# Full 16x16 group execution, still NOT a native full-renderer/quality gate.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if(-not $output.StartsWith((Join-Path $repo 'artifacts')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Use a fresh workspace artifacts directory.'}
$candidate=(Resolve-Path -LiteralPath $CandidateDirectory).Path
$build=(Resolve-Path -LiteralPath $TestBuildDirectory).Path
$report=Get-Content -LiteralPath (Join-Path $candidate 'candidate.json') -Raw | ConvertFrom-Json
$tests=Get-Content -LiteralPath (Join-Path $build 'manifest.json') -Raw | ConvertFrom-Json
$runner=Join-Path $build 'ContactShadowWarpTest.exe'
if($report.implementation -ne 'Rebirth' -or $report.reconstruction -ne 'SharedQuad' -or $report.variants.Count -ne 5 -or $tests.result -ne 'passed' -or $tests.implementation -ne 'Rebirth'){throw 'Require the tested donor and five shared candidates.'}
if((Get-FileHash -LiteralPath $runner).Hash -ne $tests.runnerSha256 -or (Get-FileHash -LiteralPath (Join-Path $repo 'tools/New-IntergradeContactShadowCandidate.ps1')).Hash -ne $report.generatorSha256){throw 'Runner or generator changed.'}
$sources=@($tests.sources)+@($report.sources)+@(@{path='src/Tests/RebirthContactGroupOracle_cs.hlsl';sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'src/Tests/RebirthContactGroupOracle_cs.hlsl')).Hash})
foreach($source in $sources){if((Get-FileHash -LiteralPath (Join-Path $repo $source.path)).Hash -ne $source.sha256){throw "Source changed: $($source.path)"}}
$null=New-Item -ItemType Directory -Path $output
$utf8=[Text.UTF8Encoding]::new($false)
function Invoke-SharedTest([string[]]$Arguments,[string]$Name) {
    $messages=& $runner @Arguments 2>&1;$code=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $output $Name),($messages|Out-String),$utf8)
    if($code -ne 0){throw "Shared execution failed: $Name"}
    return ,@($messages)
}
$profiles=@(@{frame=0;material=1},@{frame=61;material=231},@{frame=12345;material=248})
$iterations=if($Repeated){8}else{1}
$caseLanes=256*$iterations
$laneCases=61440*$iterations
$mode=if($Repeated){'--adapter-assembly-shared-repeat'}else{'--adapter-assembly-shared'}
$passPattern=if($Repeated){'^PASS shared-repeat t[45] phase=[01] \d\d .*lanes=2048/2048$'}else{'^PASS shared t[45] phase=[01] \d\d .*lanes=256/256$'}
$records=@(foreach($variant in $report.variants) {
    if(-not $variant.sharedGroup -or $variant.fixtureThreads -ne 256 -or $variant.fixtureOutputFloats -ne 2304 -or $variant.sharedMemoryBytes -ne 1024){throw 'Shared fixture contract mismatch.'}
    $binary=Join-Path $candidate $variant.binary
    if($Repeated -and ($variant.repeatedLightIterations -ne 8 -or $variant.repeatedOutputFloats -ne 18432)){throw 'Repeated fixture contract mismatch.'}
    $fixture=Join-Path $candidate $(if($Repeated){$variant.repeatedFixture}else{$variant.injectionFixture})
    $original=Join-Path $candidate ('validation/'+$variant.shaderHash+'-original.bin')
    if((Get-FileHash -LiteralPath $binary).Hash -ne $variant.candidateSha256 -or (Get-FileHash -LiteralPath $original).Hash -ne $variant.originalSha256){throw 'Candidate bytes changed.'}
    $fixtureHash=(Get-FileHash -LiteralPath $fixture).Hash
    $null=Invoke-SharedTest @('--validate-cs',$original,$binary,$fixture) ($variant.shaderHash+'-creation.log')
    foreach($profile in $profiles) {
        $messages=Invoke-SharedTest @($mode,$fixture,[string]$variant.depthSlot,$variant.diffuse.Split('.')[1],$variant.specular.Split('.')[1],[string]$profile.frame,[string]$profile.material,(Join-Path $repo 'src/Tests/RebirthContactGroupOracle_cs.hlsl')) ($variant.shaderHash+'-frame'+$profile.frame+'.log')
        if(@($messages | Where-Object {$_ -match $passPattern}).Count -ne 80){throw 'Incomplete group execution.'}
        if($Repeated -and @($messages | Where-Object {$_ -match '^Repeated coverage: alternatingDifferences=[1-9]\d* zeroContributionShadowLanes=[1-9]\d*$'}).Count -ne 1){throw 'Missing non-vacuous alternating-light/mixed-contribution evidence.'}
    }
    if((Get-FileHash -LiteralPath $fixture).Hash -ne $fixtureHash){throw 'Fixture changed during execution.'}
    Write-Host "PASS $($variant.shaderHash): 240 full-group cases / $laneCases lane results / $iterations iterations."
    @{shaderHash=$variant.shaderHash;candidateSha256=$variant.candidateSha256;fixtureSha256=$fixtureHash;creationChecks=3;groupsPassed=240;laneCases=$laneCases;lightIterations=$iterations}
})
foreach($source in $sources){if((Get-FileHash -LiteralPath (Join-Path $repo $source.path)).Hash -ne $source.sha256){throw 'Source changed during execution.'}}
$manifest=[ordered]@{
    schemaVersion=1;createdAtUtc=[DateTime]::UtcNow.ToString('o');result='passed-shared-interface-only'
    candidateDirectory=$candidate;candidateManifestSha256=(Get-FileHash -LiteralPath (Join-Path $candidate 'candidate.json')).Hash
    testBuildDirectory=$build;testManifestSha256=(Get-FileHash -LiteralPath (Join-Path $build 'manifest.json')).Hash
    runnerSha256=(Get-FileHash -LiteralPath $runner).Hash;scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    sources=$sources;profiles=$profiles;variants=$records;creationChecks=15;groupsPassed=1200;laneCases=(307200*$iterations)
    lightIterationsPerDispatch=$iterations;mixedNativeContributions=[bool]$Repeated
    runtimeEligible=$false;qualityGatePassed=$false;gameFilesModified=$false;liveTested=$false
    limitations=@('Synthetic resources and fixture loop, not captured frame or complete native tiled shading','Odd viewport origins intentionally neutral','WARP execution cannot prove absence of scheduling races on every hardware GPU','No proof of temporal phase progression, raster/helper equivalence, visual improvement or hardware performance')
}
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),($manifest|ConvertTo-Json -Depth 9)+"`n",$utf8)
