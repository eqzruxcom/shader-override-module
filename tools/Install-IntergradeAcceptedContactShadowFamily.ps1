[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$FamilyIniPath,
    [Parameter(Mandatory)][string]$TransformSummaryPath,
    [Parameter(Mandatory)][string]$CorpusReportPath,
    [string]$GameRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64',
    [string]$BackupRoot = 'F:\Shader3Dmigoto\FF7Remake\ContactShadowFamily'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$artifactRoot = Join-Path $repositoryRoot 'artifacts'
$resolvedGameRoot = [IO.Path]::GetFullPath($GameRoot).TrimEnd('\')
$resolvedBackupRoot = [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')
if (-not $resolvedGameRoot.EndsWith('\End\Binaries\Win64',[StringComparison]::OrdinalIgnoreCase)) {
    throw 'GameRoot must end in \End\Binaries\Win64.'
}
if (-not $resolvedBackupRoot.StartsWith('F:\Shader3Dmigoto\',[StringComparison]::OrdinalIgnoreCase)) {
    throw 'BackupRoot must remain beneath F:\Shader3Dmigoto.'
}

$familyIni = [IO.Path]::GetFullPath($FamilyIniPath)
$transformSummaryFile = [IO.Path]::GetFullPath($TransformSummaryPath)
$corpusReportFile = [IO.Path]::GetFullPath($CorpusReportPath)
$baseRoot = Join-Path $repositoryRoot 'artifacts\checkpoints\rebirth-contact-first-working-20260831-v1\payload\ShaderFixes'
$frustumRoot = Join-Path $repositoryRoot 'working-code\Frustum Fix\20260831-v1\accepted-runtime\ShaderFixes'
$liveIni = Join-Path $resolvedGameRoot 'Mods\ContactShadows.ini'
$liveD3dx = Join-Path $resolvedGameRoot 'd3dx.ini'
$liveShaderRoot = Join-Path $resolvedGameRoot 'ShaderFixes'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$backupDirectory = Join-Path $resolvedBackupRoot ($timestamp + '-pre-automatic-family')
$disabledDirectory = Join-Path $resolvedGameRoot ('DISABLED-ExplicitContactShadows-' + $timestamp)
$reportDirectory = Join-Path $artifactRoot ('accepted-contact-family-live-install-' + $timestamp)
$reportPath = Join-Path $reportDirectory 'install-report.json'
$utf8 = [Text.UTF8Encoding]::new($false)
$hashes = @('08bb8764f1840179','0e97888f9a8767da','5a9fbefe0ab6f815','62b33a2d1e505241','c30cdc8365df9840')

function Assert-ExactSet([object[]]$Expected,[object[]]$Actual,[string]$Name) {
    if (@(Compare-Object @($Expected|Sort-Object) @($Actual|Sort-Object)).Count) { throw "$Name does not contain the expected exact set." }
}

function Get-CodeLines([string]$Path) {
    return @(Get-Content -LiteralPath $Path | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('//') })
}

function Assert-CodeEqual([string]$ActualPath,[string]$ExpectedPath,[string]$Name) {
    $actual = @(Get-CodeLines $ActualPath)
    $expected = @(Get-CodeLines $ExpectedPath)
    if ($actual.Count -ne $expected.Count) { throw "$Name instruction/declaration count differs from its accepted checkpoint." }
    for ($index=0;$index -lt $actual.Count;$index++) {
        if ($actual[$index] -cne $expected[$index]) { throw "$Name differs from its accepted checkpoint at code line $index." }
    }
}

function Get-FileEvidence([string]$Path,[string]$RelativePath) {
    return [ordered]@{path=$RelativePath.Replace('\','/');length=(Get-Item -LiteralPath $Path).Length;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash}
}

foreach ($requiredPath in @($familyIni,$transformSummaryFile,$corpusReportFile,$baseRoot,$frustumRoot,$liveIni,$liveD3dx,$liveShaderRoot)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) { throw "Required path is missing: $requiredPath" }
}
if (Test-Path -LiteralPath $backupDirectory) { throw "Backup destination already exists: $backupDirectory" }
if (Test-Path -LiteralPath $disabledDirectory) { throw "Disabled-file destination already exists: $disabledDirectory" }

$familySha = (Get-FileHash -Algorithm SHA256 -LiteralPath $familyIni).Hash
$familyText = [IO.File]::ReadAllText($familyIni)
foreach ($requiredText in @(
    '[ShaderRegexUE4FXRemakeContactBaseT5]','[ShaderRegexUE4FXRemakeContactBaseT4]','[ShaderRegexUE4FXRemakeContactFrustumT4]',
    'family_mode = automatic','[KeyUE4FXMasterPageDown]','key = no_modifiers VK_NEXT',
    '[KeyUE4FXContactBaseT5Number1]','key = no_modifiers 1',
    '[KeyUE4FXContactBaseT4Number2]','key = no_modifiers 2',
    '[KeyUE4FXContactFrustumT4Number3]','key = no_modifiers 3')) {
    if (-not $familyText.Contains($requiredText)) { throw "Generated family is missing required contract text: $requiredText" }
}
foreach ($forbiddenText in @('key = no_modifiers F10','key = no_modifiers VK_PRIOR','key = no_modifiers F2','key = F2','key = VK_F2')) {
    if ($familyText.Contains($forbiddenText)) { throw "Generated family attempts to bind a reserved key: $forbiddenText" }
}

$transformSummary = Get-Content -Raw -LiteralPath $transformSummaryFile | ConvertFrom-Json
if (-not $transformSummary.passed -or $transformSummary.hostExit -ne 0 -or $transformSummary.generatedFamilyIniSha256 -ne $familySha) {
    throw 'Exact-transform runtime summary is not a passing result for the selected family INI.'
}
Assert-ExactSet $hashes @($transformSummary.positives) 'Runtime positive set'
if (@($transformSummary.negatives).Count -ne 3 -or @($transformSummary.variants).Count -ne 5 -or
    @($transformSummary.variants | Where-Object {-not $_.bodyExactlyEqual}).Count) {
    throw 'Runtime transform summary does not prove five exact bodies plus three rejected controls.'
}

$corpusReport = Get-Content -Raw -LiteralPath $corpusReportFile | ConvertFrom-Json
if (-not $corpusReport.passed -or -not $corpusReport.exactExpectedSet -or $corpusReport.shaderCount -ne 184 -or
    $corpusReport.matchCount -ne 5 -or @($corpusReport.timeouts).Count -or $corpusReport.patternIniSha256 -ne $familySha) {
    throw 'Full-corpus contract report does not prove an exact five-of-184 match for the selected family INI.'
}

$d3dxText = [IO.File]::ReadAllText($liveD3dx)
foreach ($requiredText in @('include_recursive = Mods','reload_fixes = no_modifiers VK_F10','reload_config = no_modifiers VK_F10')) {
    if (-not $d3dxText.Contains($requiredText)) { throw "Live d3dx.ini contract changed: $requiredText" }
}
$liveIniText = [IO.File]::ReadAllText($liveIni)
foreach ($hash in $hashes) {
    if (-not $liveIniText.Contains('hash = ' + $hash)) { throw "Live explicit contact INI lacks expected hash: $hash" }
}

$liveShaderPaths = [Collections.Generic.List[string]]::new()
$beforeFiles = [Collections.Generic.List[object]]::new()
foreach ($hash in $hashes) {
    $livePath = Join-Path $liveShaderRoot ($hash + '-cs.txt')
    $targetRoot = if ($hash -eq '62b33a2d1e505241') {$frustumRoot} else {$baseRoot}
    $targetPath = Join-Path $targetRoot ($hash + '-cs.txt')
    foreach ($requiredPath in @($livePath,$targetPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Required shader is missing: $requiredPath" }
    }
    Assert-CodeEqual $livePath $targetPath $hash
    $liveShaderPaths.Add($livePath)
    $beforeFiles.Add((Get-FileEvidence $livePath ('ShaderFixes\'+$hash+'-cs.txt')))
}
$beforeFiles.Add((Get-FileEvidence $liveIni 'Mods\ContactShadows.ini'))
$beforeFiles.Add((Get-FileEvidence $liveD3dx 'd3dx.ini'))

$backupWin64 = Join-Path $backupDirectory 'Win64'
$backupMods = Join-Path $backupWin64 'Mods'
$backupShaders = Join-Path $backupWin64 'ShaderFixes'
[IO.Directory]::CreateDirectory($backupMods)|Out-Null
[IO.Directory]::CreateDirectory($backupShaders)|Out-Null
[IO.Directory]::CreateDirectory($reportDirectory)|Out-Null
Copy-Item -LiteralPath $liveD3dx -Destination (Join-Path $backupWin64 'd3dx.ini')
Copy-Item -LiteralPath $liveIni -Destination (Join-Path $backupMods 'ContactShadows.ini')
foreach ($livePath in $liveShaderPaths) { Copy-Item -LiteralPath $livePath -Destination $backupShaders }
Copy-Item -LiteralPath $familyIni -Destination (Join-Path $backupDirectory 'generated-ContactShadowFamily.ini')
Copy-Item -LiteralPath $transformSummaryFile -Destination (Join-Path $backupDirectory 'accepted-exact-transform-summary.json')
Copy-Item -LiteralPath $corpusReportFile -Destination (Join-Path $backupDirectory 'full-corpus-contract.json')

$backupEvidence = [Collections.Generic.List[object]]::new()
foreach ($entry in $beforeFiles) {
    $backupPath = Join-Path $backupWin64 ($entry.path.Replace('/','\'))
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf) -or (Get-FileHash -Algorithm SHA256 -LiteralPath $backupPath).Hash -ne $entry.sha256) {
        throw "Backup verification failed: $($entry.path)"
    }
    $backupEvidence.Add([ordered]@{path=$entry.path;sha256=$entry.sha256})
}

$installed = $false
try {
    [IO.Directory]::CreateDirectory($disabledDirectory)|Out-Null
    foreach ($livePath in $liveShaderPaths) {
        $source = [IO.Path]::GetFullPath($livePath)
        $destination = [IO.Path]::GetFullPath((Join-Path $disabledDirectory (Split-Path -Leaf $livePath)))
        if (-not $source.StartsWith($resolvedGameRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or
            -not $destination.StartsWith($resolvedGameRoot+'\',[StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to move a shader outside the named game directory.'
        }
        Move-Item -LiteralPath $source -Destination $destination
    }
    Copy-Item -LiteralPath $familyIni -Destination $liveIni -Force
    $installed = $true
}
catch {
    Copy-Item -LiteralPath (Join-Path $backupMods 'ContactShadows.ini') -Destination $liveIni -Force
    foreach ($hash in $hashes) {
        $livePath = Join-Path $liveShaderRoot ($hash+'-cs.txt')
        $disabledPath = Join-Path $disabledDirectory ($hash+'-cs.txt')
        if (-not (Test-Path -LiteralPath $livePath) -and (Test-Path -LiteralPath $disabledPath)) { Move-Item -LiteralPath $disabledPath -Destination $livePath }
    }
    throw
}

$failures = [Collections.Generic.List[string]]::new()
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $liveIni).Hash -ne $familySha) { $failures.Add('live ContactShadows.ini differs from validated family') }
$beforeD3dxSha = ($beforeFiles | Where-Object path -eq 'd3dx.ini').sha256
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $liveD3dx).Hash -ne $beforeD3dxSha) { $failures.Add('d3dx.ini changed') }
foreach ($hash in $hashes) {
    if (Test-Path -LiteralPath (Join-Path $liveShaderRoot ($hash+'-cs.txt'))) { $failures.Add("legacy hash replacement remains live: $hash") }
    if (-not (Test-Path -LiteralPath (Join-Path $disabledDirectory ($hash+'-cs.txt')) -PathType Leaf)) { $failures.Add("disabled checkpoint is missing: $hash") }
}

$report = [ordered]@{
    schemaVersion=2;kind='ff7-remake-accepted-contact-family-live-install';installed=$installed-and$failures.Count-eq0
    installedAt=(Get-Date).ToString('o');gameRoot=$resolvedGameRoot;liveIni=$liveIni
    liveIniSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $liveIni).Hash;generatedFamilyIni=$familyIni
    generatedFamilyIniSha256=$familySha;exactTransformSummary=$transformSummaryFile;fullCorpusReport=$corpusReportFile
    backupDirectory=$backupDirectory;backupFiles=@($backupEvidence);disabledLegacyDirectory=$disabledDirectory
    keyContract=[ordered]@{F10='native reload unchanged';PageDown='master';Number1='BaseT5';Number2='BaseT4';Number3='FrustumT4';PageUp='untouched';F2='untouched'}
    failures=@($failures)
}
$json=($report|ConvertTo-Json -Depth 8)+[Environment]::NewLine
[IO.File]::WriteAllText($reportPath,$json,$utf8)
[IO.File]::WriteAllText((Join-Path $backupDirectory 'install-manifest.json'),$json,$utf8)
if ($failures.Count) { throw "Live verification failed: $($failures -join '; ')" }
Write-Host "BACKUP=$backupDirectory"
Write-Host "DISABLED_LEGACY=$disabledDirectory"
Write-Host "REPORT=$reportPath"
Write-Host 'PASS: accepted 3+1+1 automatic families installed with independent 1/2/3 gates; explicit hash replacements preserved but disabled; d3dx.ini unchanged.'
