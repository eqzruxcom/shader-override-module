[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$DecisionLedgerPath,
    [string]$CatalogPath,
    [string]$CandidatePath,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Has-Property([object]$Object,[string]$Name){return $null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name}
function Require-Text([object]$Object,[string]$Name,[string]$Context){
    if(-not (Has-Property $Object $Name) -or [string]::IsNullOrWhiteSpace([string]$Object.$Name)){throw "$Context requires non-empty $Name"}
}
function Resolve-EvidencePath([string]$Path,[string]$Workspace){
    if([IO.Path]::IsPathRooted($Path)){return [IO.Path]::GetFullPath($Path)}
    return [IO.Path]::GetFullPath((Join-Path $Workspace $Path))
}

$workspace=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$resolvedLedger=(Resolve-Path -LiteralPath $DecisionLedgerPath -ErrorAction Stop).Path
$ledger=Get-Content -Raw -LiteralPath $resolvedLedger|ConvertFrom-Json
if(-not (Has-Property $ledger 'schemaVersion') -or $ledger.schemaVersion -ne 1){throw 'Alias decision ledger schemaVersion must be 1'}
if(-not (Has-Property $ledger 'kind') -or $ledger.kind -ne 'shader-family-alias-decisions'){throw 'Unexpected alias decision ledger kind'}
Require-Text $ledger 'id' 'Alias decision ledger'
if(-not (Has-Property $ledger 'catalog')){throw 'Alias decision ledger requires catalog pin'}
Require-Text $ledger.catalog 'id' 'Catalog pin'
if([string]$ledger.catalog.sha256 -cnotmatch '^[0-9A-F]{64}$'){throw 'Catalog pin requires uppercase SHA-256'}
if(-not (Has-Property $ledger 'provenance') -or -not (Has-Property $ledger.provenance 'candidateArtifact')){throw 'Alias decision ledger requires candidateArtifact provenance'}

$allEvidence=[Collections.Generic.List[object]]::new()
$allEvidence.Add($ledger.provenance.candidateArtifact)
$entryIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$targetKeys=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$states=@{pending=0;accepted=0;rejected=0}
foreach($entry in @($ledger.entries)){
    foreach($name in @('id','stage','shaderHash','familyId','implementationId','variantId','state','rationale')){Require-Text $entry $name "Alias entry"}
    if(-not $entryIds.Add([string]$entry.id)){throw "Duplicate alias entry id: $($entry.id)"}
    if([string]$entry.stage -cnotmatch '^(vs|ps|cs|hs|ds|gs)$'){throw "Invalid shader stage in alias entry: $($entry.stage)"}
    if([string]$entry.shaderHash -cnotmatch '^[0-9A-F]{16}$'){throw "Alias entry requires uppercase 16-digit shaderHash: $($entry.id)"}
    $key="$($entry.stage)|$($entry.shaderHash)"
    if(-not $targetKeys.Add($key)){throw "Duplicate alias stage/hash decision: $key"}
    if(-not $states.ContainsKey([string]$entry.state)){throw "Invalid alias review state: $($entry.state)"}
    $states[[string]$entry.state]++
    if(@($entry.evidence).Count -lt 1){throw "Alias entry requires evidence: $($entry.id)"}
    foreach($evidence in @($entry.evidence)){$allEvidence.Add($evidence)}
    if($entry.state -ne 'pending'){
        Require-Text $entry 'reviewer' "Resolved alias entry $($entry.id)"
        Require-Text $entry 'reviewedAtUtc' "Resolved alias entry $($entry.id)"
        Require-Text $entry 'adapter' "Resolved alias entry $($entry.id)"
        Require-Text $entry 'versionGroup' "Resolved alias entry $($entry.id)"
        if($entry.reviewedAtUtc -is [DateTime]){
            if($entry.reviewedAtUtc.Kind -ne [DateTimeKind]::Utc){throw "Resolved alias entry reviewedAtUtc must be UTC: $($entry.id)"}
        }
        elseif($entry.reviewedAtUtc -is [DateTimeOffset]){
            if($entry.reviewedAtUtc.Offset -ne [TimeSpan]::Zero){throw "Resolved alias entry reviewedAtUtc must have zero UTC offset: $($entry.id)"}
        }
        else{
            if([string]$entry.reviewedAtUtc -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$'){throw "Resolved alias entry reviewedAtUtc must be canonical UTC: $($entry.id)"}
            $parsedDate=[DateTimeOffset]::MinValue
            if(-not [DateTimeOffset]::TryParse([string]$entry.reviewedAtUtc,[ref]$parsedDate)){throw "Resolved alias entry has invalid reviewedAtUtc: $($entry.id)"}
        }
    }
}

foreach($evidence in $allEvidence){
    foreach($name in @('kind','label','path','sha256')){Require-Text $evidence $name 'Alias evidence'}
    if([string]$evidence.sha256 -cnotmatch '^[0-9A-F]{64}$'){throw "Alias evidence requires uppercase SHA-256: $($evidence.label)"}
    $evidencePath=Resolve-EvidencePath ([string]$evidence.path) $workspace
    if(-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)){throw "Alias evidence file is missing: $evidencePath"}
    $actualHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $evidencePath).Hash.ToUpperInvariant()
    if($actualHash -ne [string]$evidence.sha256){throw "Alias evidence hash mismatch: $evidencePath"}
}

$catalog=$null
if(-not [string]::IsNullOrWhiteSpace($CatalogPath)){
    $resolvedCatalog=(Resolve-Path -LiteralPath $CatalogPath -ErrorAction Stop).Path
    & (Join-Path $PSScriptRoot 'Assert-ShaderFamilyCatalog.ps1') -CatalogPath $resolvedCatalog -Quiet
    $catalog=Get-Content -Raw -LiteralPath $resolvedCatalog|ConvertFrom-Json
    $catalogHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedCatalog).Hash.ToUpperInvariant()
    if($ledger.catalog.id -ne $catalog.id -or $ledger.catalog.sha256 -ne $catalogHash){throw 'Alias decision ledger does not pin the supplied catalog identity and hash'}
    $catalogIndex=@{}
    foreach($family in @($catalog.families)){foreach($implementation in @($family.implementations)){foreach($variant in @($implementation.variants)){
        $catalogIndex["$($family.id)|$($implementation.id)|$($variant.id)"]=$implementation.stage
    }}}
    foreach($entry in @($ledger.entries)){
        $identity="$($entry.familyId)|$($entry.implementationId)|$($entry.variantId)"
        if(-not $catalogIndex.ContainsKey($identity)){throw "Alias entry references an unknown catalog identity: $identity"}
        if($catalogIndex[$identity] -ne $entry.stage){throw "Alias entry stage disagrees with catalog identity: $($entry.id)"}
    }
}

if(-not [string]::IsNullOrWhiteSpace($CandidatePath)){
    $resolvedCandidates=(Resolve-Path -LiteralPath $CandidatePath -ErrorAction Stop).Path
    $candidates=Get-Content -Raw -LiteralPath $resolvedCandidates|ConvertFrom-Json
    if($candidates.kind -ne 'shader-family-alias-candidates'){throw 'Unexpected alias candidate artifact kind'}
    if($candidates.catalog.id -ne $ledger.catalog.id -or $candidates.catalog.sha256 -ne $ledger.catalog.sha256){throw 'Alias candidates and decision ledger pin different catalogs'}
    foreach($candidate in @($candidates.candidates)){
        $key="$($candidate.stage)|$($candidate.shaderHash)"
        if(-not $targetKeys.Contains($key)){throw "Alias candidate lacks a durable review-ledger entry: $key"}
        $entry=@($ledger.entries|Where-Object { $_.stage -eq $candidate.stage -and $_.shaderHash -eq $candidate.shaderHash })[0]
        foreach($name in @('familyId','implementationId','variantId')){if($entry.$name -ne $candidate.$name){throw "Alias decision disagrees with candidate $name for $key"}}
    }
}

if(-not $Quiet){Write-Host "PASS: alias ledger accounts for $($targetKeys.Count) unique targets (pending=$($states.pending), accepted=$($states.accepted), rejected=$($states.rejected))."}
