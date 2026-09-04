[CmdletBinding()]
param(
    [string]$ContractReportPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\accepted-contact-family-contract-regression-20260904.json'),
    [string]$StructuralReportPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\accepted-contact-family-regex-regression-20260904.json'),
    [string]$GenerationReportPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\accepted-contact-family-transform-20260904-004502349\family-generation.json'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-accepted-contact-family-validation-20260904.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "OutputPath must remain under artifacts: $output" }

$inputs = [ordered]@{
    engineContract = [IO.Path]::GetFullPath($ContractReportPath)
    structuralRegex = [IO.Path]::GetFullPath($StructuralReportPath)
    generation = [IO.Path]::GetFullPath($GenerationReportPath)
}
foreach ($path in $inputs.Values) {
    if (-not $path.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "Input must remain under artifacts: $path" }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required report is missing: $path" }
}

$contract = Get-Content -Raw -LiteralPath $inputs.engineContract | ConvertFrom-Json
$structural = Get-Content -Raw -LiteralPath $inputs.structuralRegex | ConvertFrom-Json
$generation = Get-Content -Raw -LiteralPath $inputs.generation | ConvertFrom-Json

if ($contract.kind -ne 'remake-accepted-contact-family-full-contract' -or -not $contract.passed) { throw 'The engine-equivalent family contract is not a passing report' }
if ($contract.matchCount -ne 5 -or -not $contract.exactExpectedSet -or @($contract.timeouts).Count -ne 0) { throw 'The engine-equivalent contract did not match exactly five shaders without timeouts' }
if ($structural.kind -ne 'remake-accepted-contact-family-full-corpus-regex') { throw 'Unexpected structural-regex report' }
if ($structural.matchCount -ne 5 -or -not $structural.exactExpectedSet) { throw 'The structural-regex union no longer resolves to the exact five-shader set' }
if ($structural.exactFamilyMembership -or $structural.passed) { throw 'Expected the structure-only report to expose the known T4 family overlap' }
if ($contract.patternIniSha256 -ne $structural.patternIniSha256 -or $contract.patternIniSha256 -ne $generation.outputIniSha256) { throw 'Reports do not describe the same generated INI' }

$ini = [IO.Path]::GetFullPath($generation.outputIni)
if (-not $ini.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $ini -PathType Leaf)) { throw 'Generated INI is missing or outside artifacts' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $ini).Hash -ne $generation.outputIniSha256) { throw 'Generated INI hash changed' }
$iniText = Get-Content -Raw -LiteralPath $ini

$expectedGuards = [ordered]@{
    ShaderRegexUE4FXRemakeContactBaseT5 = [ordered]@{ min = 645; max = 1008 }
    ShaderRegexUE4FXRemakeContactBaseT4 = [ordered]@{ min = 631; max = 631 }
    ShaderRegexUE4FXRemakeContactFrustumT4 = [ordered]@{ min = 478; max = 478 }
}
$guards = foreach ($family in $expectedGuards.Keys) {
    $sectionPattern = '(?ms)^\[' + [regex]::Escape($family) + '\]\r?\n(?<body>.*?)(?=^\[|\z)'
    $section = [regex]::Match($iniText,$sectionPattern)
    if (-not $section.Success) { throw "Root family section missing: $family" }
    $body = $section.Groups['body'].Value
    $minMatch = [regex]::Match($body,'(?m)^min_instructions\s*=\s*(\d+)\s*$')
    $maxMatch = [regex]::Match($body,'(?m)^max_instructions\s*=\s*(\d+)\s*$')
    $required = [regex]::Match($body,'(?m)^required_bindings\s*=\s*(.+?)\s*$')
    $forbidden = [regex]::Match($body,'(?m)^forbidden_bindings\s*=\s*(.+?)\s*$')
    if (-not $minMatch.Success -or -not $maxMatch.Success -or -not $required.Success -or -not $forbidden.Success) { throw "Incomplete engine guards: $family" }
    $min = [int]$minMatch.Groups[1].Value
    $max = [int]$maxMatch.Groups[1].Value
    if ($min -ne $expectedGuards[$family].min -or $max -ne $expectedGuards[$family].max) { throw "Instruction guard changed: $family" }
    [ordered]@{
        family = $family
        minimumInstructions = $min
        maximumInstructions = $max
        requiredBindings = @($required.Groups[1].Value.Split(',') | ForEach-Object Trim)
        forbiddenBindings = @($forbidden.Groups[1].Value.Split(',') | ForEach-Object Trim)
    }
}

$overlaps = @($structural.matches | Where-Object { @($_.families).Count -gt 1 })
if ($overlaps.Count -ne 2) { throw "Expected exactly two structure-only overlaps, found $($overlaps.Count)" }
$overlapRecords = foreach ($entry in $overlaps | Sort-Object file) {
    $resolved = @($contract.matches | Where-Object file -eq $entry.file)
    if ($resolved.Count -ne 1 -or @($resolved[0].families).Count -ne 1) { throw "Engine contract did not uniquely resolve $($entry.file)" }
    $generated = @($generation.variants | Where-Object { ($_.shaderHash + '-cs.asm') -eq $entry.file })
    if ($generated.Count -ne 1 -or $generated[0].nativeInstructionCount -ne $resolved[0].instructionCount) { throw "Instruction provenance mismatch for $($entry.file)" }
    [ordered]@{
        file = $entry.file
        structureOnlyFamilies = @($entry.families)
        nativeInstructionCount = $resolved[0].instructionCount
        engineResolvedFamily = $resolved[0].families[0]
    }
}

$report = [ordered]@{
    schemaVersion = 1
    detector = 'ff7-remake-accepted-contact-family-validation-v1'
    scope = 'Offline distinction between structure-only regex matching and the complete ShaderRegex runtime acceptance contract.'
    sourceReports = [ordered]@{}
    acceptedShaderSet = @($contract.matches.file | Sort-Object)
    engineEquivalentContract = [ordered]@{
        result = 'passed'
        shaderCorpusCount = $contract.shaderCount
        exactAcceptedCount = $contract.matchCount
        exactExpectedSet = [bool]$contract.exactExpectedSet
        uniqueFamilyMembership = $true
        timeoutCount = @($contract.timeouts).Count
        familyCounts = [ordered]@{
            ShaderRegexUE4FXRemakeContactBaseT5 = @($contract.matches | Where-Object { $_.families -contains 'ShaderRegexUE4FXRemakeContactBaseT5' }).Count
            ShaderRegexUE4FXRemakeContactBaseT4 = @($contract.matches | Where-Object { $_.families -contains 'ShaderRegexUE4FXRemakeContactBaseT4' }).Count
            ShaderRegexUE4FXRemakeContactFrustumT4 = @($contract.matches | Where-Object { $_.families -contains 'ShaderRegexUE4FXRemakeContactFrustumT4' }).Count
        }
    }
    structureOnlyDiagnostic = [ordered]@{
        result = 'expected-overlap-detected'
        exactUnionCount = $structural.matchCount
        exactExpectedSet = [bool]$structural.exactExpectedSet
        uniqueFamilyMembership = $false
        overlaps = @($overlapRecords)
        interpretation = 'The Base-T4 and Frustum-T4 bodies share a structural anchor. Structural regex alone is diagnostic only and must not be used as the runtime acceptance oracle.'
    }
    runtimeGuards = @($guards)
    safetyConclusion = [ordered]@{
        accepted = $true
        condition = 'Use the complete ShaderRegex contract: shader model, required/forbidden bindings, instruction bounds, and structural pattern.'
        rejectionRule = 'Reject or leave native any shader that fails any root guard, even if its structural body pattern matches.'
        transformRule = 'Base-T4 and Frustum-T4 remain separate transforms; their exact 631-versus-478 native instruction guards are mandatory.'
    }
    liveFilesModified = $false
}
foreach ($name in $inputs.Keys) {
    $report.sourceReports[$name] = [ordered]@{
        path = [IO.Path]::GetRelativePath($root,$inputs[$name]).Replace('\','/')
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $inputs[$name]).Hash
    }
}
$report.sourceReports.generatedIni = [ordered]@{
    path = [IO.Path]::GetRelativePath($root,$ini).Replace('\','/')
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $ini).Hash
}

[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,(($report | ConvertTo-Json -Depth 12)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Result='passed'; AcceptedShaders=$contract.matchCount; StructureOnlyOverlaps=$overlaps.Count; Output=$output; LiveFilesModified=$false }

