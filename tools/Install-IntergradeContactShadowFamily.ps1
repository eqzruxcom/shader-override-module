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
$expectedGameSuffix = '\End\Binaries\Win64'
if (-not $resolvedGameRoot.EndsWith($expectedGameSuffix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "GameRoot must end in $expectedGameSuffix"
}
if (-not $resolvedBackupRoot.StartsWith('F:\Shader3Dmigoto\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'BackupRoot must remain beneath F:\Shader3Dmigoto.'
}

$familyIni = [IO.Path]::GetFullPath($FamilyIniPath)
$transformSummaryFile = [IO.Path]::GetFullPath($TransformSummaryPath)
$corpusReportFile = [IO.Path]::GetFullPath($CorpusReportPath)
$acceptedRoot = Join-Path $repositoryRoot 'working-code\Frustum Fix\20260831-v1\accepted-runtime\ShaderFixes'
$liveIni = Join-Path $resolvedGameRoot 'Mods\ContactShadows.ini'
$liveD3dx = Join-Path $resolvedGameRoot 'd3dx.ini'
$liveShaderRoot = Join-Path $resolvedGameRoot 'ShaderFixes'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$backupDirectory = Join-Path $resolvedBackupRoot ($timestamp + '-pre-automatic-family')
$disabledDirectory = Join-Path $resolvedGameRoot ('DISABLED-ExplicitContactShadows-' + $timestamp)
$reportDirectory = Join-Path $artifactRoot ('contact-family-live-install-' + $timestamp)
$reportPath = Join-Path $reportDirectory 'install-report.json'
$utf8 = [Text.UTF8Encoding]::new($false)

$hashes = @(
    '08bb8764f1840179',
    '0e97888f9a8767da',
    '5a9fbefe0ab6f815',
    '62b33a2d1e505241',
    'c30cdc8365df9840'
)

function Assert-ExactSet([object[]]$Expected, [object[]]$Actual, [string]$Name) {
    $difference = @(Compare-Object @($Expected | Sort-Object) @($Actual | Sort-Object))
    if ($difference.Count) {
        throw "$Name does not contain the expected exact set."
    }
}

function Get-FileEvidence([string]$Path, [string]$RelativePath) {
    return [ordered]@{
        path = $RelativePath.Replace('\','/')
        length = (Get-Item -LiteralPath $Path).Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
    }
}

foreach ($requiredPath in @(
        $familyIni,
        $transformSummaryFile,
        $corpusReportFile,
        $liveIni,
        $liveD3dx,
        $liveShaderRoot,
        $acceptedRoot)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required path is missing: $requiredPath"
    }
}
if (Test-Path -LiteralPath $backupDirectory) {
    throw "Backup destination already exists: $backupDirectory"
}
if (Test-Path -LiteralPath $disabledDirectory) {
    throw "Disabled-file destination already exists: $disabledDirectory"
}

$familySha = (Get-FileHash -Algorithm SHA256 -LiteralPath $familyIni).Hash
$familyText = [IO.File]::ReadAllText($familyIni)
foreach ($requiredText in @(
        '[ShaderRegexUE4FXRemakeTiledSurfaceLightContactT4]',
        '[ShaderRegexUE4FXRemakeTiledSurfaceLightContactT5]',
        'family_mode = automatic',
        '[KeyUE4FXMasterPageDown]',
        'key = no_modifiers VK_NEXT')) {
    if (-not $familyText.Contains($requiredText)) {
        throw "Generated family is missing required contract text: $requiredText"
    }
}
foreach ($forbiddenText in @('VK_F10','VK_PRIOR','key = F2','key = VK_F2')) {
    if ($familyText.Contains($forbiddenText)) {
        throw "Generated family attempts to bind a reserved key: $forbiddenText"
    }
}

$transformSummary = Get-Content -Raw -LiteralPath $transformSummaryFile | ConvertFrom-Json
if (-not $transformSummary.passed -or $transformSummary.hostExit -ne 0) {
    throw 'Exact-transform runtime summary is not a passing result.'
}
if ($transformSummary.generatedFamilyIniSha256 -ne $familySha) {
    throw 'Exact-transform summary does not describe the selected family INI.'
}
Assert-ExactSet -Expected $hashes -Actual @($transformSummary.positives) -Name 'Runtime positive set'
if (@($transformSummary.negatives).Count -ne 3) {
    throw 'Runtime transform summary does not contain all three negative controls.'
}
if (@($transformSummary.variants).Count -ne 5 -or
    @($transformSummary.variants | Where-Object { -not $_.bodyExactlyEqual }).Count) {
    throw 'Runtime transform summary does not prove exact body equivalence for all five shaders.'
}

$corpusReport = Get-Content -Raw -LiteralPath $corpusReportFile | ConvertFrom-Json
if (-not $corpusReport.passed -or
    -not $corpusReport.exactExpectedSet -or
    -not $corpusReport.exactFamilyMembership -or
    $corpusReport.shaderCount -ne 184 -or
    $corpusReport.matchCount -ne 5 -or
    @($corpusReport.timeouts).Count) {
    throw 'Full-corpus report does not prove an exact five-of-184 fail-closed match.'
}
if ($corpusReport.patternIniSha256 -ne $familySha) {
    throw 'Full-corpus report does not describe the selected family INI.'
}

$d3dxText = [IO.File]::ReadAllText($liveD3dx)
foreach ($requiredText in @(
        'include_recursive = Mods',
        'reload_fixes = no_modifiers VK_F10',
        'reload_config = no_modifiers VK_F10')) {
    if (-not $d3dxText.Contains($requiredText)) {
        throw "Live d3dx.ini key/include contract changed: $requiredText"
    }
}
$liveIniText = [IO.File]::ReadAllText($liveIni)
foreach ($hash in $hashes) {
    if (-not $liveIniText.Contains('hash = ' + $hash)) {
        throw "Live explicit contact INI does not contain expected hash: $hash"
    }
}

$liveShaderPaths = [Collections.Generic.List[string]]::new()
$beforeFiles = [Collections.Generic.List[object]]::new()
foreach ($hash in $hashes) {
    $livePath = Join-Path $liveShaderRoot ($hash + '-cs.txt')
    $acceptedPath = Join-Path $acceptedRoot ($hash + '-cs.txt')
    foreach ($requiredPath in @($livePath, $acceptedPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Required shader is missing: $requiredPath"
        }
    }
    $liveSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $livePath).Hash
    $acceptedSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $acceptedPath).Hash
    if ($liveSha -ne $acceptedSha) {
        throw "Live shader is not the accepted checkpoint; refusing transition: $hash"
    }
    $liveShaderPaths.Add($livePath)
    $beforeFiles.Add((Get-FileEvidence -Path $livePath -RelativePath ('ShaderFixes\' + $hash + '-cs.txt')))
}
$beforeFiles.Add((Get-FileEvidence -Path $liveIni -RelativePath 'Mods\ContactShadows.ini'))
$beforeFiles.Add((Get-FileEvidence -Path $liveD3dx -RelativePath 'd3dx.ini'))

$backupWin64 = Join-Path $backupDirectory 'Win64'
$backupMods = Join-Path $backupWin64 'Mods'
$backupShaders = Join-Path $backupWin64 'ShaderFixes'
[IO.Directory]::CreateDirectory($backupMods) | Out-Null
[IO.Directory]::CreateDirectory($backupShaders) | Out-Null
[IO.Directory]::CreateDirectory($reportDirectory) | Out-Null
Copy-Item -LiteralPath $liveD3dx -Destination (Join-Path $backupWin64 'd3dx.ini')
Copy-Item -LiteralPath $liveIni -Destination (Join-Path $backupMods 'ContactShadows.ini')
foreach ($livePath in $liveShaderPaths) {
    Copy-Item -LiteralPath $livePath -Destination $backupShaders
}
Copy-Item -LiteralPath $familyIni -Destination (Join-Path $backupDirectory 'generated-ContactShadowFamily.ini')
Copy-Item -LiteralPath $transformSummaryFile -Destination (Join-Path $backupDirectory 'exact-transform-summary.json')
Copy-Item -LiteralPath $corpusReportFile -Destination (Join-Path $backupDirectory 'full-corpus-regex.json')

$backupEvidence = [Collections.Generic.List[object]]::new()
foreach ($entry in $beforeFiles) {
    $backupPath = Join-Path $backupWin64 ($entry.path.Replace('/','\'))
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        throw "Backup verification failed; file is missing: $backupPath"
    }
    $backupSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $backupPath).Hash
    if ($backupSha -ne $entry.sha256) {
        throw "Backup verification failed; checksum changed: $($entry.path)"
    }
    $backupEvidence.Add([ordered]@{ path=$entry.path; sha256=$backupSha })
}

$installed = $false
try {
    [IO.Directory]::CreateDirectory($disabledDirectory) | Out-Null
    foreach ($livePath in $liveShaderPaths) {
        $resolvedSource = [IO.Path]::GetFullPath($livePath)
        $destination = Join-Path $disabledDirectory (Split-Path -Leaf $livePath)
        $resolvedDestination = [IO.Path]::GetFullPath($destination)
        if (-not $resolvedSource.StartsWith($resolvedGameRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
            -not $resolvedDestination.StartsWith($resolvedGameRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to move a shader outside the explicitly named live game directory.'
        }
        Move-Item -LiteralPath $resolvedSource -Destination $resolvedDestination
    }
    Copy-Item -LiteralPath $familyIni -Destination $liveIni -Force
    $installed = $true
}
catch {
    Copy-Item -LiteralPath (Join-Path $backupMods 'ContactShadows.ini') -Destination $liveIni -Force
    foreach ($hash in $hashes) {
        $livePath = Join-Path $liveShaderRoot ($hash + '-cs.txt')
        $disabledPath = Join-Path $disabledDirectory ($hash + '-cs.txt')
        if (-not (Test-Path -LiteralPath $livePath) -and (Test-Path -LiteralPath $disabledPath)) {
            Move-Item -LiteralPath $disabledPath -Destination $livePath
        }
    }
    throw
}

$failures = [Collections.Generic.List[string]]::new()
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $liveIni).Hash -ne $familySha) {
    $failures.Add('live ContactShadows.ini checksum does not match the validated family')
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $liveD3dx).Hash -ne
    ($beforeFiles | Where-Object path -eq 'd3dx.ini').sha256) {
    $failures.Add('d3dx.ini changed even though the installer must not touch it')
}
foreach ($hash in $hashes) {
    $livePath = Join-Path $liveShaderRoot ($hash + '-cs.txt')
    $disabledPath = Join-Path $disabledDirectory ($hash + '-cs.txt')
    if (Test-Path -LiteralPath $livePath) {
        $failures.Add("legacy automatic replacement remains live: $hash")
    }
    if (-not (Test-Path -LiteralPath $disabledPath -PathType Leaf)) {
        $failures.Add("disabled legacy checkpoint copy is missing: $hash")
    }
}

$report = [ordered]@{
    schemaVersion = 1
    kind = 'ff7-remake-contact-shadow-family-live-install'
    installed = $installed -and $failures.Count -eq 0
    installedAt = (Get-Date).ToString('o')
    gameRoot = $resolvedGameRoot
    liveIni = $liveIni
    liveIniSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $liveIni).Hash
    generatedFamilyIni = $familyIni
    generatedFamilyIniSha256 = $familySha
    exactTransformSummary = $transformSummaryFile
    fullCorpusReport = $corpusReportFile
    backupDirectory = $backupDirectory
    backupFiles = @($backupEvidence)
    disabledLegacyDirectory = $disabledDirectory
    preservedKeyContract = [ordered]@{
        F10 = 'native reload_fixes + reload_config; unchanged'
        PageDown = 'accepted injected contact-shadow master on/off'
        PageUp = 'unbound by contact family; reserved for current test'
        F2 = 'unbound by contact family; separate AO/SSGI lane'
    }
    failures = @($failures)
}
$json = ($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine
[IO.File]::WriteAllText($reportPath, $json, $utf8)
[IO.File]::WriteAllText((Join-Path $backupDirectory 'install-manifest.json'), $json, $utf8)

if ($failures.Count) {
    throw "Live contact-family verification failed: $($failures -join '; ')"
}
Write-Host "BACKUP=$backupDirectory"
Write-Host "DISABLED_LEGACY=$disabledDirectory"
Write-Host "REPORT=$reportPath"
Write-Host 'PASS: validated automatic contact-shadow family installed; five legacy hash replacements preserved but disabled; d3dx.ini and reserved keys unchanged.'
