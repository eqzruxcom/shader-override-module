[CmdletBinding()]
param([switch]$SkipProxyBuild)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$generator = Join-Path $repositoryRoot 'tools\New-IntergradeAcceptedContactShadowFamilyIni.ps1'
$auditScript = Join-Path $PSScriptRoot 'Test-ContactShadowFamilyRuntimeAudit.ps1'
$baseRoot = Join-Path $repositoryRoot 'artifacts\checkpoints\rebirth-contact-first-working-20260831-v1\payload\ShaderFixes'
$frustumRoot = Join-Path $repositoryRoot 'working-code\Frustum Fix\20260831-v1\accepted-runtime\ShaderFixes'
$originalRoot = Join-Path $repositoryRoot 'working-code\Contact shadows - Rebirth Mod - Code worked\original-remake'
$generatedRoot = Join-Path $repositoryRoot ('artifacts\accepted-contact-family-transform-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))

$positiveHashes = @('08bb8764f1840179','0e97888f9a8767da','5a9fbefe0ab6f815','62b33a2d1e505241','c30cdc8365df9840')
$negativeHashes = @('b9e2305a994308f2','c814bac1ac75b35e','f97a821dddaa328a')
$familyNames = @(
    '[ShaderRegexUE4FXRemakeContactBaseT5]',
    '[ShaderRegexUE4FXRemakeContactBaseT4]',
    '[ShaderRegexUE4FXRemakeContactFrustumT4]'
)
$expectedFamily = @{
    '08bb8764f1840179'='[ShaderRegexUE4FXRemakeContactBaseT5]'
    '0e97888f9a8767da'='[ShaderRegexUE4FXRemakeContactBaseT5]'
    '5a9fbefe0ab6f815'='[ShaderRegexUE4FXRemakeContactBaseT4]'
    '62b33a2d1e505241'='[ShaderRegexUE4FXRemakeContactFrustumT4]'
    'c30cdc8365df9840'='[ShaderRegexUE4FXRemakeContactBaseT5]'
}
$expectedTemps = @{
    '08bb8764f1840179'=46; '0e97888f9a8767da'=45; '5a9fbefe0ab6f815'=44
    '62b33a2d1e505241'=40; 'c30cdc8365df9840'=54
}

function Get-BodyInstructions([string]$Path) {
    return @(Get-Content -LiteralPath $Path | ForEach-Object { $_.Trim() } | Where-Object {
        $_ -and -not $_.StartsWith('//') -and $_ -ne 'cs_5_0' -and $_ -notmatch '^dcl_'
    })
}

foreach ($requiredPath in @($generator,$auditScript,$baseRoot,$frustumRoot,$originalRoot)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) { throw "Required path is missing: $requiredPath" }
}

$generatorOutput = (& $generator -OutputDirectory $generatedRoot 2>&1 | Out-String).Trim()
$familyIniPath = Join-Path $generatedRoot 'ContactShadowFamily.ini'
$generationReportPath = Join-Path $generatedRoot 'family-generation.json'
foreach ($generatedPath in @($familyIniPath,$generationReportPath)) {
    if (-not (Test-Path -LiteralPath $generatedPath -PathType Leaf)) {
        throw "Generator did not create required evidence: $generatedPath`n$generatorOutput"
    }
}
$familyIni = [IO.File]::ReadAllText($familyIniPath)
foreach ($needle in @(
    '[KeyUE4FXContactBaseT5Number1]', 'key = no_modifiers 1',
    '[KeyUE4FXContactBaseT4Number2]', 'key = no_modifiers 2',
    '[KeyUE4FXContactFrustumT4Number3]', 'key = no_modifiers 3')) {
    if (-not $familyIni.Contains($needle)) { throw "Generated family INI lacks diagnostic binding: $needle" }
}
foreach ($reserved in @('key = no_modifiers F10','key = no_modifiers VK_PRIOR','key = no_modifiers F2')) {
    if ($familyIni.Contains($reserved)) { throw "Generated family INI captured a reserved key: $reserved" }
}

$auditStarted = Get-Date
$auditArguments = @{}
if ($SkipProxyBuild) { $auditArguments.SkipProxyBuild = $true }
$auditOutput = (& $auditScript @auditArguments 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw "Prerequisite runtime audit failed.`n$auditOutput" }
$auditSummaryFile = Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'artifacts\shader-family-tests') -Filter 'summary.json' -File -Recurse |
    Where-Object { $_.Directory.Name -like 'contact-runtime-*' -and $_.LastWriteTime -ge $auditStarted.AddSeconds(-2) } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($null -eq $auditSummaryFile) { throw "Prerequisite runtime audit did not create a new summary.`n$auditOutput" }
$auditSummary = Get-Content -Raw -LiteralPath $auditSummaryFile.FullName | ConvertFrom-Json
if (-not $auditSummary.passed) { throw "Prerequisite runtime audit reported failure: $($auditSummaryFile.FullName)" }

$runRoot = $auditSummary.runDirectory
$configurationPath = Join-Path $runRoot 'd3dx.ini'
$hostPath = Join-Path $runRoot 'ShaderFamilyComputeHost.exe'
$shaderRoot = Join-Path $runRoot 'Shaders'
$auditLogPath = Join-Path $runRoot 'd3d11_log.txt'
foreach ($requiredPath in @($configurationPath,$hostPath,$shaderRoot,$auditLogPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) { throw "Prerequisite runtime artifact is missing: $requiredPath" }
}
Move-Item -LiteralPath $auditLogPath -Destination (Join-Path $runRoot 'audit-d3d11_log.txt')
$configuration = [IO.File]::ReadAllText($configurationPath)
$auditMarker = '[ShaderRegexUE4FXRemakeTiledSurfaceLightContactAudit]'
$auditMarkerIndex = $configuration.IndexOf($auditMarker,[StringComparison]::Ordinal)
if ($auditMarkerIndex -lt 0) { throw 'Could not find the audit family section in the case-local configuration.' }
$configuration = $configuration.Substring(0,$auditMarkerIndex).Replace('export_fixed = 0','export_fixed = 1')
$configuration += [Environment]::NewLine + $familyIni
[IO.File]::WriteAllText($configurationPath,$configuration,[Text.UTF8Encoding]::new($false))

$caseShaders = @(Get-ChildItem -LiteralPath $shaderRoot -Filter '*.bin' -File | Sort-Object Name | Select-Object -ExpandProperty FullName)
if ($caseShaders.Count -ne 8) { throw "Expected eight staged compute shaders, found $($caseShaders.Count)." }
Push-Location $runRoot
try {
    $hostOutput = (& '.\ShaderFamilyComputeHost.exe' @($caseShaders) 2>&1 | Out-String).Trim()
    $hostExit = $LASTEXITCODE
}
finally { Pop-Location }

$logPath = Join-Path $runRoot 'd3d11_log.txt'
$log = if (Test-Path -LiteralPath $logPath) { [IO.File]::ReadAllText($logPath) } else { '' }
$failures = [Collections.Generic.List[string]]::new()
$variantResults = [Collections.Generic.List[object]]::new()
if ($hostExit -ne 0) { $failures.Add("host exit code $hostExit") }
if ($hostOutput -notlike '*PASS: 8 compute shaders created*') { $failures.Add('host did not create all eight compute shaders') }
if (-not $log) { $failures.Add('transform d3d11_log.txt was not created') }
foreach ($needle in @('*** Assembling patched shader failed','*** Creating replacement shader failed','Error assembling ShaderRegex patched','WARNING: Unrecognised')) {
    if ($log.Contains($needle)) { $failures.Add("replacement/configuration error present: $needle") }
}

foreach ($hash in $positiveHashes) {
    $familyName = $expectedFamily[$hash]
    if (-not $log.Contains("ShaderRegex: cs_5_0 $hash matches $familyName")) {
        $failures.Add("missing automatic family match: $hash -> $familyName")
    }
    foreach ($otherFamily in $familyNames) {
        if ($otherFamily -ne $familyName -and $log.Contains("ShaderRegex: cs_5_0 $hash matches $otherFamily")) {
            $failures.Add("shader matched multiple accepted families: $hash")
        }
    }
    $exportPath = Join-Path $runRoot "ShaderCache\$hash-cs_regex.txt"
    if (-not (Test-Path -LiteralPath $exportPath -PathType Leaf)) { $exportPath = Join-Path $runRoot "ShaderCache\$hash-cs_replace.txt" }
    if (-not (Test-Path -LiteralPath $exportPath -PathType Leaf)) { $failures.Add("missing transformed assembly: $hash"); continue }
    $exportText = [IO.File]::ReadAllText($exportPath)
    if (-not $exportText.Contains('//' + $familyName)) { $failures.Add("export lacks family attribution: $hash") }
    $tempMatch = [regex]::Match($exportText,'(?m)^dcl_temps (?<count>\d+)\r?$')
    if (-not $tempMatch.Success -or [int]$tempMatch.Groups['count'].Value -ne $expectedTemps[$hash]) {
        $failures.Add("temporary allocation is unexpected: $hash")
    }
    if ([regex]::Matches($exportText,'(?m)^dcl_resource_texture1d \(float,float,float,float\) t120\r?$').Count -ne 1) {
        $failures.Add("t120 declaration count is not exactly one: $hash")
    }
    if ([regex]::Matches($exportText,'(?m)^dcl_tgsm_structured g0, 4, 256\r?$').Count -ne 1) {
        $failures.Add("g0 declaration count is not exactly one: $hash")
    }
    $targetRoot = if ($hash -eq '62b33a2d1e505241') { $frustumRoot } else { $baseRoot }
    $targetPath = Join-Path $targetRoot ($hash + '-cs.txt')
    $originalText = [IO.File]::ReadAllText((Join-Path $originalRoot ($hash + '-cs.asm')))
    if (-not $originalText.Contains('// Generated by Microsoft') -or -not $originalText.Contains('//   using 3Dmigoto')) {
        $failures.Add("preserved original header is missing: $hash")
    }
    $targetBody = @(Get-BodyInstructions $targetPath)
    $exportBody = @(Get-BodyInstructions $exportPath)
    $difference = @(Compare-Object $targetBody $exportBody -SyncWindow 0)
    $equal = $targetBody.Count -eq $exportBody.Count -and $difference.Count -eq 0
    if (-not $equal) { $failures.Add("transformed body differs from accepted target: $hash") }
    $variantResults.Add([ordered]@{
        shaderHash=$hash; family=$familyName; target=$targetPath; exportedAssembly=$exportPath
        targetBodyInstructions=$targetBody.Count; exportedBodyInstructions=$exportBody.Count
        bodyExactlyEqual=$equal; dclTemps=if($tempMatch.Success){[int]$tempMatch.Groups['count'].Value}else{$null}
    })
}

foreach ($hash in $negativeHashes) {
    foreach ($familyName in $familyNames) {
        if ($log.Contains("ShaderRegex: cs_5_0 $hash matches $familyName")) { $failures.Add("negative control matched $familyName`: $hash") }
    }
    if (@(Get-ChildItem -LiteralPath (Join-Path $runRoot 'ShaderCache') -Filter "$hash-cs_*" -File -ErrorAction SilentlyContinue).Count) {
        $failures.Add("negative control was exported as transformed: $hash")
    }
}

$report = [ordered]@{
    schemaVersion=2; kind='remake-accepted-contact-family-exact-transform'
    mode='case-local-3dmigoto-automatic-exact-equivalence-with-diagnostic-gates'
    generatorOutput=$generatorOutput; generationReport=$generationReportPath
    generatedFamilyIni=$familyIniPath; generatedFamilyIniSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $familyIniPath).Hash
    prerequisiteAuditSummary=$auditSummaryFile.FullName; runtimeSha256=$auditSummary.runtimeSha256
    diagnosticKeys=[ordered]@{number1='BaseT5';number2='BaseT4';number3='FrustumT4'}
    positives=$positiveHashes; negatives=$negativeHashes; variants=@($variantResults)
    hostExit=$hostExit; passed=$failures.Count -eq 0; failures=@($failures); runDirectory=$runRoot
}
$summaryPath = Join-Path $runRoot 'accepted-exact-transform-summary.json'
[IO.File]::WriteAllText($summaryPath,($report|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
Write-Host $hostOutput
Write-Host "SUMMARY=$summaryPath"
if ($failures.Count) { throw "Accepted contact family exact-transform test failed: $($failures -join '; ')" }
Write-Host 'PASS: all five shaders matched only their accepted family, assembled, exactly reproduced the four base plus 62b frustum targets, and rejected all three negatives.'
