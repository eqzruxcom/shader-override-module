[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CatalogPath,
    [Parameter(Mandatory)]
    [ValidateSet('vs','ps','cs','hs','ds','gs')]
    [string]$Stage,
    [Parameter(Mandatory)]
    [string]$ShaderHash,
    [switch]$AllowNoMatch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($ShaderHash -cnotmatch '^[0-9A-Fa-f]{16}$') { throw "ShaderHash must be exactly 16 hexadecimal digits: $ShaderHash" }
$normalizedHash = $ShaderHash.ToUpperInvariant()
& (Join-Path $PSScriptRoot 'Assert-ShaderFamilyCatalog.ps1') -CatalogPath $CatalogPath -Quiet
$catalog = Get-Content -Raw -LiteralPath $CatalogPath | ConvertFrom-Json

$matches = [Collections.Generic.List[object]]::new()
foreach ($family in @($catalog.families)) {
    foreach ($implementation in @($family.implementations | Where-Object { $_.stage -eq $Stage })) {
        foreach ($variant in @($implementation.variants)) {
            foreach ($target in @($variant.targets | Where-Object { $_.shaderHash -eq $normalizedHash })) {
                $matches.Add([pscustomobject]@{
                    catalogId = [string]$catalog.id
                    familyId = [string]$family.id
                    logicalName = [string]$family.logicalName
                    implementationId = [string]$implementation.id
                    adapter = [string]$implementation.adapter
                    api = [string]$implementation.api
                    bytecodeFormat = [string]$implementation.bytecodeFormat
                    stage = [string]$implementation.stage
                    shaderModels = @($implementation.shaderModels)
                    identityModel = [string]$implementation.identityModel
                    variantId = [string]$variant.id
                    versionGroup = [string]$target.versionGroup
                    shaderHash = [string]$target.shaderHash
                })
            }
        }
    }
}

if ($matches.Count -gt 1) { throw "Ambiguous catalog target: $Stage|$normalizedHash matched $($matches.Count) entries" }
if ($matches.Count -eq 0) {
    if ($AllowNoMatch) { return }
    throw "No reviewed catalog target matches $Stage|$normalizedHash"
}
return $matches[0]

