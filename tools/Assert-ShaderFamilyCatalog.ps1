[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CatalogPath,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-PropertySet($Object, [string[]]$Required, [string[]]$Allowed, [string]$Context) {
    if ($null -eq $Object -or $Object -isnot [pscustomobject]) { throw "$Context must be an object" }
    $names = @($Object.PSObject.Properties.Name)
    foreach ($name in $Required) { if ($name -notin $names) { throw "$Context is missing '$name'" } }
    foreach ($name in $names) { if ($name -notin $Allowed) { throw "$Context has unsupported property '$name'" } }
}

function Assert-String($Value, [string]$Context, [string]$Pattern = $null) {
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) { throw "$Context must be a non-empty string" }
    if ($Pattern -and $Value -cnotmatch $Pattern) { throw "$Context is malformed: $Value" }
}

function Assert-Hash16($Value, [string]$Context) { Assert-String $Value $Context '^[0-9A-F]{16}$' }
function Assert-Hash64($Value, [string]$Context) { Assert-String $Value $Context '^[0-9A-F]{64}$' }

function Assert-HashSet($Value, [string]$Context) {
    $items = @($Value)
    if ($Value -isnot [Array] -or $items.Count -lt 1) { throw "$Context must be a non-empty array" }
    foreach ($item in $items) { Assert-Hash16 $item "$Context item" }
    if (@($items | Sort-Object -Unique).Count -ne $items.Count) { throw "$Context contains duplicates" }
}

if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) { throw "Catalog not found: $CatalogPath" }
$catalog = Get-Content -Raw -LiteralPath $CatalogPath | ConvertFrom-Json
Assert-PropertySet $catalog @('schemaVersion','kind','id','displayName','provenance','families') @('schemaVersion','kind','id','displayName','provenance','families') 'Catalog'
if ($catalog.schemaVersion -ne 1 -or $catalog.kind -ne 'shader-family-catalog') { throw 'Unsupported catalog envelope' }
Assert-String $catalog.id 'Catalog id' '^[a-z0-9][a-z0-9-]+$'
Assert-String $catalog.displayName 'Catalog displayName'

Assert-PropertySet $catalog.provenance @('evidence') @('evidence') 'Catalog provenance'
$provenance = @($catalog.provenance.evidence)
if ($catalog.provenance.evidence -isnot [Array] -or $provenance.Count -lt 1) { throw 'Catalog provenance evidence must be a non-empty array' }
foreach ($entry in $provenance) {
    Assert-PropertySet $entry @('kind','label') @('kind','label','path','sha256') 'Provenance entry'
    Assert-String $entry.kind 'Provenance kind'
    Assert-String $entry.label 'Provenance label'
    if ($null -ne $entry.PSObject.Properties['path']) { Assert-String $entry.path 'Provenance path' }
    if ($null -ne $entry.PSObject.Properties['sha256']) { Assert-Hash64 $entry.sha256 'Provenance SHA-256' }
}

$families = @($catalog.families)
if ($catalog.families -isnot [Array] -or $families.Count -lt 1) { throw 'Catalog families must be a non-empty array' }
$familyIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$implementationIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$targetKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($family in $families) {
    Assert-PropertySet $family @('id','logicalName','implementations') @('id','logicalName','description','implementations') 'Family'
    Assert-String $family.id 'Family id' '^[a-z0-9][a-z0-9-]+$'
    if (-not $familyIds.Add([string]$family.id)) { throw "Duplicate family id: $($family.id)" }
    Assert-String $family.logicalName "Family $($family.id) logicalName"
    if ($null -ne $family.PSObject.Properties['description']) { Assert-String $family.description "Family $($family.id) description" }
    $implementations = @($family.implementations)
    if ($family.implementations -isnot [Array] -or $implementations.Count -lt 1) { throw "Family $($family.id) has no implementations" }
    foreach ($implementation in $implementations) {
        $context = "Implementation $($implementation.id)"
        Assert-PropertySet $implementation @('id','adapter','api','bytecodeFormat','stage','shaderModels','identityModel','variants') @(
            'id','adapter','api','bytecodeFormat','stage','shaderModels','identityModel','role','status','insertionEligibility','evidence','constraints','runtimeContract','variants'
        ) $context
        Assert-String $implementation.id "$context id" '^[a-z0-9][a-z0-9-]+$'
        if (-not $implementationIds.Add([string]$implementation.id)) { throw "Duplicate implementation id: $($implementation.id)" }
        Assert-String $implementation.adapter "$context adapter"
        Assert-String $implementation.api "$context api"
        Assert-String $implementation.bytecodeFormat "$context bytecodeFormat"
        Assert-String $implementation.stage "$context stage" '^(vs|ps|cs|hs|ds|gs)$'
        Assert-String $implementation.identityModel "$context identityModel"
        foreach ($optional in @('role','status','insertionEligibility')) {
            if ($null -ne $implementation.PSObject.Properties[$optional]) { Assert-String $implementation.$optional "$context $optional" }
        }
        foreach ($optionalArray in @('evidence','constraints')) {
            if ($null -ne $implementation.PSObject.Properties[$optionalArray]) {
                if ($implementation.$optionalArray -isnot [Array]) { throw "$context $optionalArray must be an array" }
                foreach ($value in @($implementation.$optionalArray)) { Assert-String $value "$context $optionalArray item" }
            }
        }
        if ($null -ne $implementation.PSObject.Properties['runtimeContract'] -and $implementation.runtimeContract -isnot [pscustomobject]) {
            throw "$context runtimeContract must be an object"
        }
        $models = @($implementation.shaderModels)
        if ($implementation.shaderModels -isnot [Array] -or $models.Count -lt 1) { throw "$context shaderModels must be a non-empty array" }
        foreach ($model in $models) {
            Assert-String $model "$context shader model" "^$([regex]::Escape([string]$implementation.stage))_[0-9]+_[0-9]+$"
        }
        if (@($models | Sort-Object -Unique).Count -ne $models.Count) { throw "$context shaderModels contains duplicates" }

        $variants = @($implementation.variants)
        if ($implementation.variants -isnot [Array] -or $variants.Count -lt 1) { throw "$context variants must be a non-empty array" }
        $variantIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($variant in $variants) {
            Assert-PropertySet $variant @('id','identity','targets') @('id','identity','targets') "$context variant"
            Assert-String $variant.id "$context variant id" '^[a-z0-9][a-z0-9-]+$'
            if (-not $variantIds.Add([string]$variant.id)) { throw "$context contains duplicate variant id $($variant.id)" }
            switch ([string]$implementation.identityModel) {
                'shader-injector-dxil-analysis-v1' {
                    Assert-PropertySet $variant.identity @(
                        'crossVersionIdentityHash','interfaceSignatureHashes','resourceSignatureHashes','constantBufferSignatureHashes',
                        'executionSignatureHashes','portableReflectionIdentityHashes','semanticInstructionSetHashes'
                    ) @(
                        'crossVersionIdentityHash','interfaceSignatureHashes','resourceSignatureHashes','constantBufferSignatureHashes',
                        'executionSignatureHashes','portableReflectionIdentityHashes','semanticInstructionSetHashes'
                    ) "$context DXIL identity"
                    Assert-Hash16 $variant.identity.crossVersionIdentityHash "$context crossVersionIdentityHash"
                    foreach ($setName in @('interfaceSignatureHashes','resourceSignatureHashes','constantBufferSignatureHashes','executionSignatureHashes','portableReflectionIdentityHashes','semanticInstructionSetHashes')) {
                        Assert-HashSet $variant.identity.$setName "$context $setName"
                    }
                }
                '3dmigoto-dxbc-fnv1-v1' {
                    Assert-PropertySet $variant.identity @('canonicalShaderHash') @('canonicalShaderHash') "$context exact DXBC identity"
                    Assert-Hash16 $variant.identity.canonicalShaderHash "$context canonicalShaderHash"
                }
                'ue4-dxbc-regex-semantic-v1' {
                    Assert-PropertySet $variant.identity @('descriptorId','checks','hashFastPaths') @('descriptorId','checks','hashFastPaths') "$context semantic DXBC identity"
                    Assert-String $variant.identity.descriptorId "$context descriptorId" '^[a-z0-9][a-z0-9-]+$'
                    $checks = @($variant.identity.checks)
                    if ($variant.identity.checks -isnot [Array] -or $checks.Count -lt 1) { throw "$context semantic checks must be a non-empty array" }
                    $checkIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                    foreach ($check in $checks) {
                        Assert-PropertySet $check @('id','pattern','minCount','meaning') @('id','pattern','minCount','maxCount','meaning') "$context semantic check"
                        Assert-String $check.id "$context semantic check id" '^[a-z0-9][a-z0-9-]+$'
                        if (-not $checkIds.Add([string]$check.id)) { throw "$context has duplicate semantic check id $($check.id)" }
                        Assert-String $check.pattern "$context semantic check pattern"
                        Assert-String $check.meaning "$context semantic check meaning"
                        if ($check.minCount -isnot [int] -and $check.minCount -isnot [long]) { throw "$context minCount must be an integer" }
                        if ([int64]$check.minCount -lt 0) { throw "$context minCount must be non-negative" }
                        $maxProperty = $check.PSObject.Properties['maxCount']
                        if ($null -ne $maxProperty -and $null -ne $check.maxCount) {
                            if ($check.maxCount -isnot [int] -and $check.maxCount -isnot [long]) { throw "$context maxCount must be null or an integer" }
                            if ([int64]$check.maxCount -lt [int64]$check.minCount) { throw "$context maxCount must not be below minCount" }
                        }
                        try { [void][regex]::new([string]$check.pattern, [Text.RegularExpressions.RegexOptions]::CultureInvariant, [TimeSpan]::FromSeconds(1)) }
                        catch { throw "$context contains invalid semantic regex '$($check.id)': $($_.Exception.Message)" }
                    }
                    $fastPaths = @($variant.identity.hashFastPaths)
                    if ($variant.identity.hashFastPaths -isnot [Array]) { throw "$context hashFastPaths must be an array" }
                    $fastPathKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                    foreach ($fastPath in $fastPaths) {
                        Assert-PropertySet $fastPath @('adapter','hash') @('adapter','hash','evidence') "$context semantic fast path"
                        Assert-String $fastPath.adapter "$context fast-path adapter"
                        Assert-Hash16 $fastPath.hash "$context fast-path hash"
                        if ($null -ne $fastPath.PSObject.Properties['evidence'] -and $fastPath.evidence -isnot [string]) { throw "$context fast-path evidence must be a string" }
                        if (-not $fastPathKeys.Add("$($fastPath.adapter)|$($fastPath.hash)")) { throw "$context contains a duplicate semantic fast path" }
                    }
                }
                default { throw "$context uses unsupported identity model: $($implementation.identityModel)" }
            }

            $targets = @($variant.targets)
            if ($variant.targets -isnot [Array]) { throw "$context variant $($variant.id) targets must be an array" }
            foreach ($target in $targets) {
                Assert-PropertySet $target @('versionGroup','shaderHash') @('versionGroup','shaderHash','bytecodeLength','entryFunction','sourceFile','compiledBlobFile') "$context target"
                Assert-String $target.versionGroup "$context target versionGroup"
                Assert-Hash16 $target.shaderHash "$context target shaderHash"
                $targetKey = "$($implementation.stage)|$($target.shaderHash)"
                if (-not $targetKeys.Add($targetKey)) { throw "Duplicate stage/hash target in catalog: $targetKey" }
                if ($implementation.identityModel -eq '3dmigoto-dxbc-fnv1-v1' -and $target.shaderHash -ne $variant.identity.canonicalShaderHash) {
                    throw "$context exact identity does not equal target hash"
                }
                if ($implementation.identityModel -eq 'shader-injector-dxil-analysis-v1') {
                    foreach ($requiredTargetField in @('bytecodeLength','entryFunction','sourceFile','compiledBlobFile')) {
                        if ($null -eq $target.PSObject.Properties[$requiredTargetField]) { throw "$context DXIL target is missing $requiredTargetField" }
                    }
                    if ($target.bytecodeLength -isnot [int] -and $target.bytecodeLength -isnot [long]) { throw "$context bytecodeLength must be an integer" }
                    if ([int64]$target.bytecodeLength -lt 1) { throw "$context bytecodeLength must be positive" }
                    foreach ($field in @('entryFunction','sourceFile','compiledBlobFile')) { Assert-String $target.$field "$context target $field" }
                }
            }
            if ($implementation.identityModel -eq 'ue4-dxbc-regex-semantic-v1') {
                $fastKeys = @($variant.identity.hashFastPaths | ForEach-Object { "$($implementation.stage)|$($_.hash)" } | Sort-Object)
                $targetFastKeys = @($targets | ForEach-Object { "$($implementation.stage)|$($_.shaderHash)" } | Sort-Object)
                if (@(Compare-Object $fastKeys $targetFastKeys).Count -ne 0) { throw "$context semantic targets must exactly mirror hashFastPaths" }
            }
        }
    }
}

if (-not $Quiet) {
    Write-Host "PASS: strict portable catalog validation accepted $($families.Count) families and $($targetKeys.Count) unique stage/hash targets."
}
