[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CandidateDirectory,
    [Parameter(Mandatory)][string]$TestBuildDirectory,
    [Parameter(Mandatory)][string]$PlaneAuditDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if(-not $output.StartsWith((Join-Path $repo 'artifacts')+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Output must be below workspace artifacts.'}
if(Test-Path -LiteralPath $output) {throw 'Output already exists; preserve earlier tests.'}
$candidate=(Resolve-Path -LiteralPath $CandidateDirectory).Path
$report=Get-Content -LiteralPath (Join-Path $candidate 'candidate.json') -Raw | ConvertFrom-Json
$testBuild=(Resolve-Path -LiteralPath $TestBuildDirectory).Path
$testManifest=Get-Content -LiteralPath (Join-Path $testBuild 'manifest.json') -Raw | ConvertFrom-Json
$runner=Join-Path $testBuild 'ContactShadowWarpTest.exe'
if($testManifest.result -ne 'passed' -or $testManifest.runnerSha256 -ne (Get-FileHash -LiteralPath $runner).Hash) {throw 'Test runner not verified.'}
if($testManifest.assemblyFixtureInputRows -ne 3 -or $testManifest.assemblyFixtureCases -ne 37) {throw 'Test runner fixture ABI mismatch.'}
$auditPath=Join-Path (Resolve-Path -LiteralPath $PlaneAuditDirectory).Path 'manifest.json'
$audit=Get-Content -LiteralPath $auditPath -Raw | ConvertFrom-Json
if($audit.execution -ne 'completed-offline-WARP' -or $audit.regressionDetected -or $audit.caseCount -ne 20480) {throw 'Mandatory plane/blocker software-renderer audit has not passed.'}
foreach($source in $audit.sources) {
    if($source.sha256 -ne (Get-FileHash -LiteralPath (Join-Path $repo $source.path)).Hash) {throw "Plane audit source changed: $($source.path)"}
}
foreach($source in $testManifest.sources) {
    if($source.sha256 -ne (Get-FileHash -LiteralPath (Join-Path $repo $source.path)).Hash) {throw "Test source changed: $($source.path)"}
}
if($report.sourceKernelSha256 -ne (Get-FileHash -LiteralPath (Join-Path $repo 'src/Adapters/FF7RemakeIntergrade/ContactShadowKernel_ps.hlsl')).Hash -or
   $report.effectSourceSha256 -ne (Get-FileHash -LiteralPath (Join-Path $repo 'src/Effects/Lighting/ContactShadows.hlsl')).Hash) {throw 'Candidate source changed.'}
$null=New-Item -ItemType Directory -Path $output
$utf8=[Text.UTF8Encoding]::new($false)
function Run-CandidateTest([string[]]$Arguments,[string]$Log) {
    $messages=& $runner @Arguments 2>&1
    $code=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $output $Log),($messages|Out-String),$utf8)
    if($code -ne 0) {throw "Candidate test failed: $Log"}
    return ,@($messages)
}
$records=@(foreach($variant in $report.variants) {
    $binary=Join-Path $candidate $variant.binary
    $original=Join-Path $candidate ('validation/'+$variant.shaderHash+'-original.bin')
    $fixture=Join-Path $candidate $variant.injectionFixture
    if($variant.fixtureInputRows -ne 3 -or -not $variant.zeroNativeContributionGate) {throw 'Fixture ABI/gate mismatch.'}
    if((Get-FileHash -LiteralPath $binary).Hash -ne $variant.candidateSha256 -or
       (Get-FileHash -LiteralPath $original).Hash -ne $variant.originalSha256) {throw 'Shader bytes changed.'}
    $null=Run-CandidateTest @('--validate-cs',$original,$binary,$fixture) ($variant.shaderHash+'-creation.log')
    $result=Run-CandidateTest @('--adapter-assembly',$fixture,[string]$variant.depthSlot,$variant.diffuse.Split('.')[1],$variant.specular.Split('.')[1]) ($variant.shaderHash+'-execution.log')
    if(@($result | Where-Object {$_ -match '^PASS t[45] '}).Count -ne 37) {throw 'Incomplete fixture result count.'}
    Write-Output "PASS $($variant.shaderHash): native/candidate/fixture creation; 37 injected-block execution cases."
    [ordered]@{shaderHash=$variant.shaderHash;creationChecks=3;injectionCases=37;result='passed';candidateSha256=$variant.candidateSha256;fixtureSha256=(Get-FileHash -LiteralPath $fixture).Hash}
})
# Do not mix progress strings into the structured report.
$variantRecords=@($records | Where-Object {$_ -is [Collections.IDictionary]})
$records | Where-Object {$_ -is [string]} | Write-Output
if($variantRecords.Count -ne 5) {throw 'Expected five native variants.'}
$manifest=[ordered]@{
    schemaVersion=1;generatedAtUtc=[DateTime]::UtcNow.ToString('o');result='passed'
    candidateDirectory=$candidate;candidateManifestSha256=(Get-FileHash -LiteralPath (Join-Path $candidate 'candidate.json')).Hash
    testBuildDirectory=$testBuild;runnerSha256=(Get-FileHash -LiteralPath $runner).Hash
    creationChecks=15;injectedBlockResourceCases=185;variants=$variantRecords
    planeAuditDirectory=(Split-Path -Parent $auditPath);planeAuditManifestSha256=(Get-FileHash -LiteralPath $auditPath).Hash;planeAuditCases=$audit.caseCount
    installed=$false;runtimeEligible=$false;liveGameTested=$false;performanceTested=$false
    limitations=@('Exact injected block executed with synthetic resources, not full native tiled dispatch','Actual game constant values and visible light selection still require capture','No live visual or GPU-cost evidence')
}
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),(($manifest|ConvertTo-Json -Depth 8)+"`n"),$utf8)
