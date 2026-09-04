[CmdletBinding()]
param(
    [string]$ShaderDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\ShaderCache',
    [string]$DescriptorDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Engine\UE4\PassDescriptors'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ue4-semantic-pass-matches.json'),
    [string]$DescriptorId,
    [switch]$ExcludeReplacementArtifacts,
    [ValidateRange(0, 100)]
    [int]$NearMatchLimitPerDescriptor = 0,
    [double]$MatchTimeoutSeconds = 1.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-OptionalProperty {
    param([object]$Object, [string]$Name, $Default = $null)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    $property.Value
}

function Assert-PropertySet {
    param(
        [object]$Object,
        [string[]]$Required,
        [string[]]$Allowed,
        [string]$Context
    )
    if ($null -eq $Object -or $Object -isnot [pscustomobject]) {
        throw "$Context must be an object."
    }
    $names = @($Object.PSObject.Properties.Name)
    foreach ($name in $Required) {
        if ($name -notin $names) { throw "$Context is missing required property '$name'." }
    }
    foreach ($name in $names) {
        if ($name -notin $Allowed) { throw "$Context has unsupported property '$name'." }
    }
}

function Assert-NonEmptyString {
    param($Value, [string]$Context, [string]$Pattern)
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) {
        throw "$Context must be a non-empty string."
    }
    if ($Pattern -and $Value -cnotmatch $Pattern) {
        throw "$Context does not match required pattern '$Pattern': $Value"
    }
}

function Assert-StringArray {
    param($Value, [string]$Context, [string[]]$Allowed, [string]$Pattern)
    if ($Value -isnot [Array]) { throw "$Context must be an array." }
    $items = @($Value)
    if (-not $items.Count) { throw "$Context must contain at least one item." }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($item in $items) {
        Assert-NonEmptyString $item "$Context item" $Pattern
        if ($Allowed -and $Allowed -cnotcontains $item) { throw "$Context contains unsupported value '$item'." }
        if (-not $seen.Add([string]$item)) { throw "$Context contains duplicate value '$item'." }
    }
}

function Test-IsJsonInteger {
    param($Value)
    $Value -is [sbyte] -or $Value -is [byte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function Assert-Descriptor {
    param(
        [object]$Descriptor,
        [string]$File,
        [TimeSpan]$Timeout,
        [Text.RegularExpressions.RegexOptions]$RegexOptions
    )

    $context = "Descriptor $File"
    Assert-PropertySet $Descriptor @(
        'schemaVersion','id','family','displayName','stages','shaderModels','semanticSignature'
    ) @(
        'schemaVersion','id','family','displayName','description','stages','shaderModels',
        'hashFastPaths','semanticSignature','runtimeContract','sourceEvidence'
    ) $context

    if (-not (Test-IsJsonInteger $Descriptor.schemaVersion) -or $Descriptor.schemaVersion -ne 1) {
        throw "Unsupported descriptor schema in $($File): $($Descriptor.schemaVersion)"
    }
    Assert-NonEmptyString $Descriptor.id "$context id" '^[a-z0-9][a-z0-9-]+$'
    Assert-NonEmptyString $Descriptor.family "$context family" $null
    Assert-NonEmptyString $Descriptor.displayName "$context displayName" $null

    $description = Get-OptionalProperty $Descriptor 'description'
    if ($null -ne $description -and $description -isnot [string]) {
        throw "$context description must be a string."
    }

    Assert-StringArray $Descriptor.stages "$context stages" @('vs','ps','cs','hs','ds','gs') $null
    Assert-StringArray $Descriptor.shaderModels "$context shaderModels" $null '^(vs|ps|cs|hs|ds|gs)_5_0$'
    foreach ($model in @($Descriptor.shaderModels)) {
        if ($model.Substring(0, 2) -notin @($Descriptor.stages)) {
            throw "$context shader model '$model' has no corresponding stage."
        }
    }

    $fastPathsProperty = $Descriptor.PSObject.Properties['hashFastPaths']
    [object]$fastPathsValue = $null
    if ($null -ne $fastPathsProperty) { $fastPathsValue = $fastPathsProperty.Value }
    if ($null -ne $fastPathsValue -and $fastPathsValue -isnot [Array]) {
        throw "$context hashFastPaths must be an array."
    }
    $fastPathKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($fastPath in @($fastPathsValue)) {
        Assert-PropertySet $fastPath @('adapter','hash') @('adapter','hash','evidence') "$context hashFastPath"
        Assert-NonEmptyString $fastPath.adapter "$context hashFastPath adapter" $null
        Assert-NonEmptyString $fastPath.hash "$context hashFastPath hash" '^[0-9a-f]{16}$'
        $evidence = Get-OptionalProperty $fastPath 'evidence'
        if ($null -ne $evidence -and $evidence -isnot [string]) {
            throw "$context hashFastPath evidence must be a string."
        }
        $key = "$($fastPath.adapter)|$($fastPath.hash)"
        if (-not $fastPathKeys.Add($key)) { throw "$context has duplicate hashFastPath '$key'." }
    }

    $semantic = $Descriptor.semanticSignature
    Assert-PropertySet $semantic @('checks') @('checks') "$context semanticSignature"
    if ($semantic.checks -isnot [Array]) { throw "$context semanticSignature checks must be an array." }
    $checks = @($semantic.checks)
    if (-not $checks.Count) { throw "$context has no semantic checks." }

    $checkIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $compiledChecks = [Collections.Generic.List[object]]::new()
    foreach ($check in $checks) {
        Assert-PropertySet $check @('id','pattern','minCount','meaning') @(
            'id','pattern','minCount','maxCount','meaning'
        ) "$context semantic check"
        Assert-NonEmptyString $check.id "$context semantic check id" '^[a-z0-9][a-z0-9-]+$'
        if (-not $checkIds.Add([string]$check.id)) {
            throw "$context has duplicate semantic check id '$($check.id)'."
        }
        Assert-NonEmptyString $check.pattern "$context check '$($check.id)' pattern" $null
        Assert-NonEmptyString $check.meaning "$context check '$($check.id)' meaning" $null

        if (-not (Test-IsJsonInteger $check.minCount) -or [int64]$check.minCount -lt 0) {
            throw "$context check '$($check.id)' minCount must be a non-negative integer."
        }
        $maxCount = Get-OptionalProperty $check 'maxCount'
        if ($null -ne $maxCount) {
            if (-not (Test-IsJsonInteger $maxCount) -or [int64]$maxCount -lt 0) {
                throw "$context check '$($check.id)' maxCount must be null or a non-negative integer."
            }
            if ([int64]$maxCount -lt [int64]$check.minCount) {
                throw "$context check '$($check.id)' maxCount is less than minCount."
            }
        }

        try {
            $compiled = [regex]::new([string]$check.pattern, $RegexOptions, $Timeout)
        }
        catch [ArgumentException] {
            throw "$context check '$($check.id)' has invalid regex: $($_.Exception.Message)"
        }
        $compiledChecks.Add([pscustomobject]@{ definition = $check; regex = $compiled })
    }

    $runtimeContract = Get-OptionalProperty $Descriptor 'runtimeContract'
    if ($null -ne $runtimeContract -and $runtimeContract -isnot [pscustomobject]) {
        throw "$context runtimeContract must be an object."
    }
    $sourceEvidenceProperty = $Descriptor.PSObject.Properties['sourceEvidence']
    [object]$sourceEvidence = $null
    if ($null -ne $sourceEvidenceProperty) { $sourceEvidence = $sourceEvidenceProperty.Value }
    if ($null -ne $sourceEvidence) {
        if ($sourceEvidence -isnot [Array]) { throw "$context sourceEvidence must be an array." }
        foreach ($evidence in @($sourceEvidence)) {
            if ($evidence -isnot [string]) { throw "$context sourceEvidence items must be strings." }
        }
    }

    @($compiledChecks)
}

if (-not (Test-Path -LiteralPath $ShaderDirectory -PathType Container)) {
    throw "Shader directory not found: $ShaderDirectory"
}
if (-not (Test-Path -LiteralPath $DescriptorDirectory -PathType Container)) {
    throw "Descriptor directory not found: $DescriptorDirectory"
}

$schemaPath = Join-Path $DescriptorDirectory 'schema.json'
if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
    throw "Descriptor schema not found: $schemaPath"
}
if ($MatchTimeoutSeconds -le 0) { throw 'MatchTimeoutSeconds must be greater than zero.' }
$timeout = [TimeSpan]::FromSeconds($MatchTimeoutSeconds)
$regexOptions = [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
    [Text.RegularExpressions.RegexOptions]::Multiline

$descriptorFiles = @(Get-ChildItem -LiteralPath $DescriptorDirectory -File -Filter '*.json' |
    Where-Object { $_.Name -ne 'schema.json' } |
    Sort-Object Name)
if (-not $descriptorFiles.Count) {
    throw "No semantic pass descriptors found in $DescriptorDirectory"
}

$descriptorIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$knownHashOwners = @{}
$descriptors = foreach ($file in $descriptorFiles) {
    try {
        $descriptor = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    }
    catch {
        throw "Descriptor JSON is invalid in $($file.FullName): $($_.Exception.Message)"
    }

    $compiledChecks = @(Assert-Descriptor $descriptor $file.FullName $timeout $regexOptions)
    if (-not $descriptorIds.Add([string]$descriptor.id)) {
        throw "Duplicate semantic descriptor id: $($descriptor.id)"
    }

    $fastPaths = @(Get-OptionalProperty $descriptor 'hashFastPaths' @())
    foreach ($fastPath in $fastPaths) {
        foreach ($stage in @($descriptor.stages)) {
            $hashKey = "$stage|$($fastPath.hash)"
            if ($knownHashOwners.ContainsKey($hashKey) -and $knownHashOwners[$hashKey] -ne $descriptor.id) {
                throw "Known shader hash $($fastPath.hash) for stage $stage is assigned to multiple descriptors: $($knownHashOwners[$hashKey]), $($descriptor.id)"
            }
            $knownHashOwners[$hashKey] = [string]$descriptor.id
        }
    }

    if ($DescriptorId -and $descriptor.id -ne $DescriptorId) { continue }
    [pscustomobject]@{
        definition = $descriptor
        compiledChecks = $compiledChecks
        file = $file.FullName
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
    }
}
if (-not @($descriptors).Count) {
    throw "No descriptor matched -DescriptorId '$DescriptorId'."
}

$semanticMatches = [Collections.Generic.List[object]]::new()
$nearCandidates = [Collections.Generic.List[object]]::new()
$timeouts = [Collections.Generic.List[object]]::new()
$shaderCount = 0

$shaderFiles = @(Get-ChildItem -LiteralPath $ShaderDirectory -Recurse -File |
    Where-Object {
        $_.Extension -in @('.asm', '.txt') -and
        $_.Name -match '^(?<hash>[0-9a-fA-F]{16})-(?<stage>vs|ps|cs|hs|ds|gs)(?:[_-][^\.]*)?\.(?:asm|txt)$' -and
        (-not $ExcludeReplacementArtifacts -or $_.Name -notmatch '(?i)_replace\.(?:asm|txt)$')
    } |
    Sort-Object FullName)

foreach ($shader in $shaderFiles) {
    if ($shader.Name -notmatch '^(?<hash>[0-9a-fA-F]{16})-(?<stage>vs|ps|cs|hs|ds|gs)(?:[_-][^\.]*)?\.(?:asm|txt)$') {
        continue
    }
    $hash = $Matches.hash.ToLowerInvariant()
    $stage = $Matches.stage.ToLowerInvariant()
    $assembly = (Get-Content -Raw -LiteralPath $shader.FullName).Replace(
        [Environment]::NewLine,
        [string][char]10
    )
    $modelMatch = [regex]::Match($assembly, '(?m)^(?<model>(?:vs|ps|cs|hs|ds|gs)_5_0)\s*$')
    if (-not $modelMatch.Success) { continue }
    $shaderModel = $modelMatch.Groups['model'].Value.ToLowerInvariant()
    $shaderCount++

    foreach ($entry in @($descriptors)) {
        $descriptor = $entry.definition
        if ($stage -notin @($descriptor.stages) -or $shaderModel -notin @($descriptor.shaderModels)) {
            continue
        }

        $checkEvidence = [Collections.Generic.List[object]]::new()
        $passed = $true
        foreach ($compiledCheck in @($entry.compiledChecks)) {
            $check = $compiledCheck.definition
            $minCount = [int]$check.minCount
            $maxRaw = Get-OptionalProperty $check 'maxCount'
            $maxCount = if ($null -eq $maxRaw) { $null } else { [int]$maxRaw }
            try {
                $count = $compiledCheck.regex.Matches($assembly).Count
                $satisfied = $count -ge $minCount -and ($null -eq $maxCount -or $count -le $maxCount)
                if (-not $satisfied) { $passed = $false }
                $checkEvidence.Add([pscustomobject]@{
                    id = [string]$check.id
                    count = $count
                    minCount = $minCount
                    maxCount = $maxCount
                    satisfied = $satisfied
                    meaning = [string]$check.meaning
                })
            }
            catch [Text.RegularExpressions.RegexMatchTimeoutException] {
                $passed = $false
                $timeouts.Add([pscustomobject]@{
                    descriptor = [string]$descriptor.id
                    check = [string]$check.id
                    hash = $hash
                    file = $shader.FullName
                })
            }
        }

        if (-not $passed) {
            if ($NearMatchLimitPerDescriptor -gt 0) {
                $satisfiedCount = @($checkEvidence | Where-Object satisfied).Count
                if ($satisfiedCount -gt 0) {
                    $nearCandidates.Add([pscustomobject]@{
                        descriptor = [string]$descriptor.id
                        family = [string]$descriptor.family
                        displayName = [string]$descriptor.displayName
                        hash = $hash
                        stage = $stage
                        shaderModel = $shaderModel
                        file = $shader.FullName
                        satisfiedChecks = $satisfiedCount
                        totalChecks = @($entry.compiledChecks).Count
                        coverage = [Math]::Round($satisfiedCount / @($entry.compiledChecks).Count, 4)
                        evidence = @($checkEvidence)
                    })
                }
            }
            continue
        }
        $fastPath = @((Get-OptionalProperty $descriptor 'hashFastPaths' @()) |
            Where-Object { $_.hash -eq $hash })
        $semanticMatches.Add([pscustomobject]@{
            descriptor = [string]$descriptor.id
            family = [string]$descriptor.family
            displayName = [string]$descriptor.displayName
            hash = $hash
            stage = $stage
            shaderModel = $shaderModel
            file = $shader.FullName
            semanticChecksPassed = $checkEvidence.Count
            fastPathAdapters = @($fastPath | ForEach-Object { $_.adapter })
            evidence = @($checkEvidence)
        })
    }
}

$groupedMatches = @($semanticMatches |
    Group-Object descriptor, hash, stage |
    ForEach-Object {
        $first = $_.Group[0]
        [pscustomobject]@{
            descriptor = $first.descriptor
            family = $first.family
            displayName = $first.displayName
            hash = $first.hash
            stage = $first.stage
            shaderModel = $first.shaderModel
            semanticChecksPassed = $first.semanticChecksPassed
            fastPathAdapters = @($_.Group |
                ForEach-Object { @((Get-OptionalProperty $_ 'fastPathAdapters' @())) } |
                Sort-Object -Unique)
            evidence = @($first.evidence)
            artifacts = @($_.Group | ForEach-Object {
                [pscustomobject]@{
                    file = $_.file
                    semanticChecksPassed = $_.semanticChecksPassed
                }
            } | Sort-Object file)
        }
    } |
    Sort-Object descriptor, hash, stage)

$rankedNearMatches = if ($NearMatchLimitPerDescriptor -gt 0) {
    @($nearCandidates |
        Group-Object descriptor |
        ForEach-Object {
            @($_.Group |
                Sort-Object @{ Expression = 'coverage'; Descending = $true },
                    @{ Expression = 'satisfiedChecks'; Descending = $true }, hash, file |
                Select-Object -First $NearMatchLimitPerDescriptor)
        } |
        Sort-Object descriptor, @{ Expression = 'coverage'; Descending = $true }, hash)
} else {
    @()
}

$report = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    matcher = 'independent-semantic-descriptors'
    licensedRegexDependency = $false
    descriptorValidation = 'schema-v1-strict'
    descriptorSchema = [ordered]@{
        file = (Resolve-Path -LiteralPath $schemaPath).Path
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $schemaPath).Hash
    }
    descriptorDirectory = (Resolve-Path -LiteralPath $DescriptorDirectory).Path
    descriptors = @($descriptors | ForEach-Object {
        [ordered]@{
            id = $_.definition.id
            family = $_.definition.family
            file = $_.file
            sha256 = $_.sha256
            checkCount = @($_.definition.semanticSignature.checks).Count
        }
    })
    shaders = [ordered]@{
        directory = (Resolve-Path -LiteralPath $ShaderDirectory).Path
        scanned = $shaderCount
        replacementArtifactsExcluded = [bool]$ExcludeReplacementArtifacts
    }
    matchTimeouts = @($timeouts)
    matches = $groupedMatches
}
if ($NearMatchLimitPerDescriptor -gt 0) {
    $report['nearMatchLimitPerDescriptor'] = $NearMatchLimitPerDescriptor
    $report['nearMatches'] = @($rankedNearMatches)
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

Write-Output "Semantic descriptors: $(@($descriptors).Count)"
Write-Output "Shader assemblies scanned: $shaderCount"
Write-Output "Semantic matches: $($groupedMatches.Count)"
if ($NearMatchLimitPerDescriptor -gt 0) {
    Write-Output "Near matches: $(@($rankedNearMatches).Count)"
}
Write-Output "Regex timeouts: $($timeouts.Count)"
Write-Output "Report: $OutputPath"