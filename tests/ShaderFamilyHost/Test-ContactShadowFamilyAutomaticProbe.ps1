[CmdletBinding()]
param(
    [switch]$SkipProxyBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$auditScript = Join-Path $PSScriptRoot 'Test-ContactShadowFamilyRuntimeAudit.ps1'
$positiveHashes = @(
    '08bb8764f1840179',
    '0e97888f9a8767da',
    '5a9fbefe0ab6f815',
    '62b33a2d1e505241',
    'c30cdc8365df9840'
)
$expectedTempDeclarations = @{
    '08bb8764f1840179' = 32
    '0e97888f9a8767da' = 31
    '5a9fbefe0ab6f815' = 30
    '62b33a2d1e505241' = 25
    'c30cdc8365df9840' = 40
}
$negativeHashes = @(
    'b9e2305a994308f2',
    'c814bac1ac75b35e',
    'f97a821dddaa328a'
)

if (-not (Test-Path -LiteralPath $auditScript -PathType Leaf)) {
    throw "Runtime audit script is missing: $auditScript"
}

$auditStarted = Get-Date
$auditArgs = @{}
if ($SkipProxyBuild) {
    $auditArgs.SkipProxyBuild = $true
}
$auditOutput = (& $auditScript @auditArgs 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Prerequisite contact-family audit failed.`n$auditOutput"
}

$auditSummaryFile = Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'artifacts\shader-family-tests') -Filter 'summary.json' -File -Recurse |
    Where-Object { $_.Directory.Name -like 'contact-runtime-*' -and $_.LastWriteTime -ge $auditStarted.AddSeconds(-2) } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $auditSummaryFile) {
    throw "Prerequisite audit did not create a new summary file.`n$auditOutput"
}
$auditSummaryPath = $auditSummaryFile.FullName
$auditSummary = Get-Content -Raw -LiteralPath $auditSummaryPath | ConvertFrom-Json
if (-not $auditSummary.passed) {
    throw "Prerequisite audit summary reports failure: $auditSummaryPath"
}

$runRoot = $auditSummary.runDirectory
$configurationPath = Join-Path $runRoot 'd3dx.ini'
$hostPath = Join-Path $runRoot 'ShaderFamilyComputeHost.exe'
$shaderRoot = Join-Path $runRoot 'Shaders'
$auditLogPath = Join-Path $runRoot 'd3d11_log.txt'
$preservedAuditLogPath = Join-Path $runRoot 'audit-d3d11_log.txt'

foreach ($requiredPath in @($configurationPath, $hostPath, $shaderRoot, $auditLogPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Prerequisite audit artifact is missing: $requiredPath"
    }
}

Move-Item -LiteralPath $auditLogPath -Destination $preservedAuditLogPath
$configuration = [IO.File]::ReadAllText($configurationPath)
$configuration = $configuration.Replace('export_fixed = 0', 'export_fixed = 1')
$configuration = $configuration.Replace(
    "shader_model = cs_5_0`r`nfamily_mode = audit",
    "shader_model = cs_5_0`r`ntemps = family_probe`r`nfamily_mode = automatic")
if (-not $configuration.Contains('temps = family_probe')) {
    $configuration = $configuration.Replace(
        "shader_model = cs_5_0`nfamily_mode = audit",
        "shader_model = cs_5_0`ntemps = family_probe`nfamily_mode = automatic")
}
if (-not $configuration.Contains('temps = family_probe')) {
    throw 'Could not convert the case-local family section from audit to automatic mode.'
}

$configuration += @'

[ShaderRegexUE4FXRemakeTiledSurfaceLightContactAudit.Pattern.Replace]
mov ${family_probe}.x, l(0)\n
${0}
'@
[IO.File]::WriteAllText(
    $configurationPath,
    $configuration,
    [Text.UTF8Encoding]::new($false))

$caseShaders = @(Get-ChildItem -LiteralPath $shaderRoot -Filter '*.bin' -File |
    Sort-Object Name | Select-Object -ExpandProperty FullName)
if ($caseShaders.Count -ne 8) {
    throw "Expected eight staged compute shaders, found $($caseShaders.Count)."
}

Push-Location $runRoot
try {
    $hostOutput = (& '.\ShaderFamilyComputeHost.exe' @($caseShaders) 2>&1 | Out-String).Trim()
    $hostExit = $LASTEXITCODE
}
finally {
    Pop-Location
}

$logPath = Join-Path $runRoot 'd3d11_log.txt'
$log = if (Test-Path -LiteralPath $logPath) {
    [IO.File]::ReadAllText($logPath)
}
else {
    ''
}

$familyName = '[ShaderRegexUE4FXRemakeTiledSurfaceLightContactAudit]'
$failures = [Collections.Generic.List[string]]::new()
if ($hostExit -ne 0) {
    $failures.Add("host exit code $hostExit")
}
if ($hostOutput -notlike '*PASS: 8 compute shaders created*') {
    $failures.Add('host did not create all eight compute shaders')
}
if (-not $log) {
    $failures.Add('automatic-probe d3d11_log.txt was not created')
}

$forbiddenErrors = @(
    '*** Assembling patched shader failed',
    '*** Creating replacement shader failed',
    'Error assembling ShaderRegex patched'
)
foreach ($needle in $forbiddenErrors) {
    if ($log.Contains($needle)) {
        $failures.Add("automatic replacement error present: $needle")
    }
}

$exportedPaths = [Collections.Generic.List[string]]::new()
foreach ($hash in $positiveHashes) {
    $expected = "ShaderRegex: cs_5_0 $hash matches $familyName"
    if (-not $log.Contains($expected)) {
        $failures.Add("missing automatic match: $hash")
    }
    $exportPath = Join-Path $runRoot "ShaderCache\$hash-cs_replace.txt"
    if (-not (Test-Path -LiteralPath $exportPath -PathType Leaf)) {
        $exportPath = Join-Path $runRoot "ShaderCache\$hash-cs_regex.txt"
    }
    if (-not (Test-Path -LiteralPath $exportPath -PathType Leaf)) {
        $failures.Add("missing exported patched assembly: $hash")
    }
    else {
        $exportedText = [IO.File]::ReadAllText($exportPath)
        if (-not $exportedText.Contains('//[ShaderRegexUE4FXRemakeTiledSurfaceLightContactAudit]')) {
            $failures.Add("exported assembly lacks the family attribution: $hash")
        }
        $tempDeclaration = [regex]::Match($exportedText, '(?m)^dcl_temps (?<count>\d+)\r?$')
        if (-not $tempDeclaration.Success -or
            [int]$tempDeclaration.Groups['count'].Value -ne $expectedTempDeclarations[$hash]) {
            $failures.Add("temporary register allocation was not increased exactly once: $hash")
        }
        $probeRegister = $expectedTempDeclarations[$hash] - 1
        $probePattern = "(?m)^mov r$probeRegister\.x, l\(0\)\r?$"
        $probeInstructions = [regex]::Matches($exportedText, $probePattern)
        if ($probeInstructions.Count -ne 1) {
            $failures.Add("exported assembly does not contain exactly one standalone r$probeRegister probe instruction: $hash")
        }
        if ($exportedText -match 'l\(0\)[ \t]+uge ') {
            $failures.Add("probe instruction was merged with the original instruction: $hash")
        }
        $exportedPaths.Add($exportPath)
    }
}
foreach ($hash in $negativeHashes) {
    $unexpected = "ShaderRegex: cs_5_0 $hash matches $familyName"
    if ($log.Contains($unexpected)) {
        $failures.Add("unrelated compute shader matched automatically: $hash")
    }
    $unexpectedExports = @(Get-ChildItem -LiteralPath (Join-Path $runRoot 'ShaderCache') -Filter "$hash-cs_*" -File -ErrorAction SilentlyContinue)
    if ($unexpectedExports.Count) {
        $failures.Add("unrelated compute shader was exported as patched: $hash")
    }
}

$report = [ordered]@{
    schemaVersion = 1
    kind = 'remake-contact-family-runtime-automatic-probe'
    mode = 'case-local-3dmigoto-automatic-unused-temp'
    prerequisiteAuditSummary = $auditSummaryPath
    runtimeSha256 = $auditSummary.runtimeSha256
    positives = $positiveHashes
    negatives = $negativeHashes
    exportedPatchedAssembly = @($exportedPaths)
    hostExit = $hostExit
    passed = $failures.Count -eq 0
    failures = @($failures)
    runDirectory = $runRoot
}
$summaryPath = Join-Path $runRoot 'automatic-probe-summary.json'
[IO.File]::WriteAllText(
    $summaryPath,
    ($report | ConvertTo-Json -Depth 6) + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))

Write-Host $hostOutput
Write-Host "SUMMARY=$summaryPath"
if ($failures.Count) {
    throw "Contact family automatic probe failed: $($failures -join '; ')"
}

Write-Host 'PASS: 3Dmigoto automatically rewrote all five contact-family shaders, created valid replacements, and rejected three unrelated compute shaders.'
