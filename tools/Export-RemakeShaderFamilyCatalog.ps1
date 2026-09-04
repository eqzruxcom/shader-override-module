[CmdletBinding()]
param(
    [string]$ClassificationPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Adapters\FF7RemakeIntergrade\verified-shader-classifications.json'),
    [string]$OutputPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\ff7-remake-intergrade-verified-family-catalog.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$artifacts = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts'))
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
if (-not $resolvedOutput.StartsWith($artifacts + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must remain beneath $artifacts"
}
if (-not (Test-Path -LiteralPath $ClassificationPath -PathType Leaf)) { throw "Classification manifest not found: $ClassificationPath" }

$source = Get-Content -Raw -LiteralPath $ClassificationPath | ConvertFrom-Json
if ($source.schemaVersion -ne 1 -or $source.renderer -ne 'D3D11') { throw 'Unsupported Remake classification manifest' }

$families = foreach ($family in @($source.families | Sort-Object familyId)) {
    if ([string]$family.familyId -cnotmatch '^[a-z0-9][a-z0-9-]+$') { throw "Invalid family ID: $($family.familyId)" }
    $stage = ([string]$family.stage).ToLowerInvariant()
    if ($stage -notin @('vs','ps','cs','hs','ds','gs')) { throw "Invalid stage for $($family.familyId): $stage" }
    $variants = foreach ($shader in @($family.hashes | Sort-Object hash)) {
        $hash = ([string]$shader.hash).ToUpperInvariant()
        if ($hash -cnotmatch '^[0-9A-F]{16}$') { throw "Invalid shader hash in $($family.familyId): $hash" }
        [ordered]@{
            id = "hash-$($hash.ToLowerInvariant())"
            identity = [ordered]@{ canonicalShaderHash = $hash }
            targets = @([ordered]@{
                versionGroup = [string]$source.captureId
                shaderHash = $hash
            })
        }
    }
    [ordered]@{
        id = [string]$family.familyId
        logicalName = [string]$family.familyId
        description = [string]$family.role
        implementations = @([ordered]@{
            id = "ff7-remake-d3d11-$($family.familyId)"
            adapter = [string]$source.adapterId
            api = 'D3D11'
            bytecodeFormat = 'DXBC'
            stage = $stage
            shaderModels = @("${stage}_5_0")
            identityModel = '3dmigoto-dxbc-fnv1-v1'
            role = [string]$family.role
            status = [string]$family.status
            insertionEligibility = [string]$family.insertionEligibility
            evidence = @($family.evidence)
            constraints = @($family.constraints)
            variants = @($variants)
        })
    }
}

$classificationFullPath = [IO.Path]::GetFullPath($ClassificationPath)
$inventoryFullPath = [IO.Path]::GetFullPath((Join-Path $workspace ([string]$source.inventory)))
if (-not (Test-Path -LiteralPath $inventoryFullPath -PathType Leaf)) { throw "Referenced inventory not found: $inventoryFullPath" }
$catalog = [ordered]@{
    schemaVersion = 1
    kind = 'shader-family-catalog'
    id = 'ff7-remake-intergrade-verified-area-20260831'
    displayName = 'FF7 Remake Intergrade verified D3D11 families'
    provenance = [ordered]@{ evidence = @(
        [ordered]@{
            kind = 'classification-manifest'
            label = 'Authoritative verified Remake classifications'
            path = [IO.Path]::GetRelativePath($workspace, $classificationFullPath).Replace('\', '/')
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $classificationFullPath).Hash.ToUpperInvariant()
        },
        [ordered]@{
            kind = 'regional-inventory'
            label = [string]$source.captureId
            path = [IO.Path]::GetRelativePath($workspace, $inventoryFullPath).Replace('\', '/')
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $inventoryFullPath).Hash.ToUpperInvariant()
        }
    ) }
    families = @($families)
}

[void](New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput -Parent))
$catalog | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resolvedOutput -Encoding UTF8
Write-Host "PASS: exported $($families.Count) verified Remake families to $resolvedOutput"

