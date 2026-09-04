[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CatalogPath,
    [Parameter(Mandatory)]
    [string]$DecisionLedgerPath,
    [Parameter(Mandatory)]
    [string]$OutputPath,
    [switch]$AllowNoAccepted
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$artifacts=[IO.Path]::GetFullPath((Join-Path $workspace 'artifacts'))
$resolvedOutput=[IO.Path]::GetFullPath($OutputPath)
if(-not $resolvedOutput.StartsWith($artifacts+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "OutputPath must remain beneath $artifacts"}
$resolvedCatalog=(Resolve-Path -LiteralPath $CatalogPath -ErrorAction Stop).Path
$resolvedLedger=(Resolve-Path -LiteralPath $DecisionLedgerPath -ErrorAction Stop).Path
& (Join-Path $PSScriptRoot 'Assert-ShaderFamilyCatalog.ps1') -CatalogPath $resolvedCatalog -Quiet
& (Join-Path $PSScriptRoot 'Assert-ShaderFamilyAliasDecisions.ps1') -DecisionLedgerPath $resolvedLedger -CatalogPath $resolvedCatalog -Quiet

$catalog=Get-Content -Raw -LiteralPath $resolvedCatalog|ConvertFrom-Json
$ledger=Get-Content -Raw -LiteralPath $resolvedLedger|ConvertFrom-Json
$accepted=@($ledger.entries|Where-Object state -eq 'accepted'|Sort-Object stage,shaderHash)
if($accepted.Count -eq 0 -and -not $AllowNoAccepted){throw 'Alias ledger contains no accepted entries to publish'}

$existing=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($family in @($catalog.families)){foreach($implementation in @($family.implementations)){foreach($variant in @($implementation.variants)){foreach($target in @($variant.targets)){
    [void]$existing.Add("$($implementation.stage)|$($target.shaderHash)")
}}}}

foreach($entry in $accepted){
    $key="$($entry.stage)|$($entry.shaderHash)"
    if($existing.Contains($key)){throw "Accepted alias is already an exact catalog target: $key"}
    $family=@($catalog.families|Where-Object id -eq $entry.familyId)
    if($family.Count -ne 1){throw "Accepted alias family is not unique: $($entry.familyId)"}
    $implementation=@($family[0].implementations|Where-Object id -eq $entry.implementationId)
    if($implementation.Count -ne 1){throw "Accepted alias implementation is not unique: $($entry.implementationId)"}
    if($implementation[0].identityModel -ne 'ue4-dxbc-regex-semantic-v1'){throw "Accepted alias publication requires a semantic DXBC implementation: $($entry.id)"}
    $variant=@($implementation[0].variants|Where-Object id -eq $entry.variantId)
    if($variant.Count -ne 1){throw "Accepted alias variant is not unique: $($entry.variantId)"}

    $fastPaths=[Collections.Generic.List[object]]::new()
    foreach($item in @($variant[0].identity.hashFastPaths)){$fastPaths.Add($item)}
    $fastPaths.Add([pscustomobject][ordered]@{
        adapter=[string]$entry.adapter
        hash=[string]$entry.shaderHash
        evidence="Accepted by alias ledger $($ledger.id) entry $($entry.id): $($entry.rationale)"
    })
    $variant[0].identity.hashFastPaths=@($fastPaths|Sort-Object adapter,hash)

    $targets=[Collections.Generic.List[object]]::new()
    foreach($item in @($variant[0].targets)){$targets.Add($item)}
    $targets.Add([pscustomobject][ordered]@{versionGroup=[string]$entry.versionGroup;shaderHash=[string]$entry.shaderHash})
    $variant[0].targets=@($targets|Sort-Object versionGroup,shaderHash)
    [void]$existing.Add($key)
}

$catalog.id="$($catalog.id)-reviewed-aliases"
$catalog.displayName="$($catalog.displayName) + reviewed aliases"
$provenance=[Collections.Generic.List[object]]::new()
foreach($item in @($catalog.provenance.evidence)){$provenance.Add($item)}
$provenance.Add([pscustomobject][ordered]@{kind='base-catalog';label='Immutable input catalog';path=$resolvedCatalog;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedCatalog).Hash.ToUpperInvariant()})
$provenance.Add([pscustomobject][ordered]@{kind='alias-decision-ledger';label='Reviewed shader-family alias decisions';path=$resolvedLedger;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedLedger).Hash.ToUpperInvariant()})
$catalog.provenance.evidence=@($provenance)

[void](New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput -Parent))
[IO.File]::WriteAllText($resolvedOutput,(($catalog|ConvertTo-Json -Depth 16)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
try{& (Join-Path $PSScriptRoot 'Assert-ShaderFamilyCatalog.ps1') -CatalogPath $resolvedOutput -Quiet}
catch{Remove-Item -LiteralPath $resolvedOutput -Force -ErrorAction SilentlyContinue;throw}
Write-Host "PASS: published $($accepted.Count) accepted aliases into derived catalog $resolvedOutput"
