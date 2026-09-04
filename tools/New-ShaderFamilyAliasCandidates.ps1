[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CatalogPath,
    [Parameter(Mandatory)]
    [string]$MatchReportPath,
    [string]$OutputPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\shader-family-alias-candidates.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$artifacts=[IO.Path]::GetFullPath((Join-Path $workspace 'artifacts'))
$resolvedOutput=[IO.Path]::GetFullPath($OutputPath)
if (-not $resolvedOutput.StartsWith($artifacts+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "OutputPath must remain beneath $artifacts"}
$resolvedCatalog=(Resolve-Path -LiteralPath $CatalogPath -ErrorAction Stop).Path
$resolvedReport=(Resolve-Path -LiteralPath $MatchReportPath -ErrorAction Stop).Path
& (Join-Path $PSScriptRoot 'Assert-ShaderFamilyCatalog.ps1') -CatalogPath $resolvedCatalog -Quiet
$catalog=Get-Content -Raw -LiteralPath $resolvedCatalog|ConvertFrom-Json
$scan=Get-Content -Raw -LiteralPath $resolvedReport|ConvertFrom-Json
$catalogHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedCatalog).Hash.ToUpperInvariant()
if ($scan.matcher -ne 'portable-family-catalog-dxbc-semantic'){throw 'Match report was not produced by the portable catalog semantic matcher'}
if ($scan.catalog.id -ne $catalog.id -or $scan.catalog.sha256 -ne $catalogHash){throw 'Match report does not pin the supplied catalog identity and hash'}

$semanticIndex=@{}
$knownTargets=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($family in @($catalog.families)){
    foreach($implementation in @($family.implementations)){
        foreach($variant in @($implementation.variants)){
            foreach($target in @($variant.targets)){[void]$knownTargets.Add("$($implementation.stage)|$($target.shaderHash)")}
            if($implementation.identityModel -eq 'ue4-dxbc-regex-semantic-v1'){
                $descriptorId=[string]$variant.identity.descriptorId
                if($semanticIndex.ContainsKey($descriptorId)){throw "Duplicate semantic descriptor identity in catalog: $descriptorId"}
                $semanticIndex[$descriptorId]=[pscustomobject]@{family=$family;implementation=$implementation;variant=$variant}
            }
        }
    }
}

$candidates=[Collections.Generic.List[object]]::new()
foreach($match in @($scan.matches|Sort-Object descriptor,stage,hash)){
    $key="$($match.stage)|$($match.hash)"
    if($knownTargets.Contains($key)){continue}
    if(-not $semanticIndex.ContainsKey([string]$match.descriptor)){throw "Structural match references unknown semantic descriptor: $($match.descriptor)"}
    $entry=$semanticIndex[[string]$match.descriptor]
    if($entry.implementation.stage -ne $match.stage){throw "Structural match stage disagrees with catalog: $key"}
    $candidates.Add([pscustomobject]@{
        catalogId=[string]$catalog.id
        familyId=[string]$entry.family.id
        implementationId=[string]$entry.implementation.id
        variantId=[string]$entry.variant.id
        identityModel=[string]$entry.implementation.identityModel
        stage=[string]$match.stage
        shaderHash=([string]$match.hash).ToUpperInvariant()
        shaderModel=[string]$match.shaderModel
        semanticChecksPassed=[int]$match.semanticChecksPassed
        fastPathAdapters=@($match.fastPathAdapters)
        evidence=@($match.evidence)
        artifacts=@($match.artifacts)
        status='review-required'
        catalogMutation=$false
        runtimeEligible=$false
        reason='All bounded semantic checks passed, but this stage/hash is not an existing exact catalog target.'
    })
}

$result=[ordered]@{
    schemaVersion=1
    kind='shader-family-alias-candidates'
    catalog=[ordered]@{id=[string]$catalog.id;path=$resolvedCatalog;sha256=$catalogHash}
    matchReport=[ordered]@{path=$resolvedReport;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedReport).Hash.ToUpperInvariant()}
    candidateCount=$candidates.Count
    candidates=@($candidates)
}
[void](New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput -Parent))
$result|ConvertTo-Json -Depth 14|Set-Content -LiteralPath $resolvedOutput -Encoding UTF8
Write-Host "PASS: wrote $($candidates.Count) review-only learned-alias candidates to $resolvedOutput"

