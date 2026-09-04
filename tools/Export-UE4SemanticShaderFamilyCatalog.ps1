[CmdletBinding()]
param(
    [string]$DescriptorDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Engine\UE4\PassDescriptors'),
    [string]$OutputPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\ue4-dxbc-semantic-family-catalog.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$artifacts = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts'))
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
if (-not $resolvedOutput.StartsWith($artifacts + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "OutputPath must remain beneath $artifacts" }
$resolvedDescriptors = (Resolve-Path -LiteralPath $DescriptorDirectory -ErrorAction Stop).Path
$schemaPath = Join-Path $resolvedDescriptors 'schema.json'
if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) { throw "Descriptor schema not found: $schemaPath" }

$descriptorFiles = @(Get-ChildItem -LiteralPath $resolvedDescriptors -File -Filter '*.json' | Where-Object { $_.Name -ne 'schema.json' } | Sort-Object Name)
if ($descriptorFiles.Count -lt 1) { throw 'No UE4 semantic descriptors found' }
$families = foreach ($file in $descriptorFiles) {
    $descriptor = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    $stages = @($descriptor.stages)
    if ($stages.Count -ne 1) { throw "Portable semantic implementation requires one stage per descriptor: $($descriptor.id)" }
    $stage = [string]$stages[0]
    $fastPaths = @($descriptor.hashFastPaths | Sort-Object adapter,hash | ForEach-Object {
        $item = [ordered]@{ adapter=[string]$_.adapter; hash=([string]$_.hash).ToUpperInvariant() }
        if ($null -ne $_.PSObject.Properties['evidence']) { $item['evidence']=[string]$_.evidence }
        $item
    })
    $checks = @($descriptor.semanticSignature.checks | ForEach-Object {
        $item = [ordered]@{ id=[string]$_.id; pattern=[string]$_.pattern; minCount=[int64]$_.minCount }
        if ($null -ne $_.PSObject.Properties['maxCount']) { $item['maxCount']=$_.maxCount }
        $item['meaning']=[string]$_.meaning
        $item
    })
    [ordered]@{
        id = [string]$descriptor.id
        logicalName = [string]$descriptor.displayName
        description = [string]$descriptor.description
        implementations = @([ordered]@{
            id = "$($descriptor.id)-d3d11"
            adapter = 'UE4-DXBC-Semantic'
            api = 'D3D11'
            bytecodeFormat = 'DXBC'
            stage = $stage
            shaderModels = @($descriptor.shaderModels)
            identityModel = 'ue4-dxbc-regex-semantic-v1'
            role = [string]$descriptor.family
            evidence = @($descriptor.sourceEvidence)
            runtimeContract = $descriptor.runtimeContract
            variants = @([ordered]@{
                id = 'semantic-v1'
                identity = [ordered]@{
                    descriptorId = [string]$descriptor.id
                    checks = $checks
                    hashFastPaths = $fastPaths
                }
                targets = @($fastPaths | ForEach-Object { [ordered]@{ versionGroup=$_.adapter; shaderHash=$_.hash } })
            })
        })
    }
}

$evidence = [Collections.Generic.List[object]]::new()
$evidence.Add([ordered]@{
    kind='descriptor-schema'; label='Strict UE4 semantic descriptor schema'
    path=[IO.Path]::GetRelativePath($workspace,$schemaPath).Replace('\','/')
    sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $schemaPath).Hash.ToUpperInvariant()
})
foreach ($file in $descriptorFiles) {
    $evidence.Add([ordered]@{
        kind='semantic-descriptor'; label=$file.BaseName
        path=[IO.Path]::GetRelativePath($workspace,$file.FullName).Replace('\','/')
        sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToUpperInvariant()
    })
}
$catalog = [ordered]@{
    schemaVersion=1
    kind='shader-family-catalog'
    id='ue4-dxbc-semantic-descriptors-v1'
    displayName='Independent UE4 D3D11 semantic shader families'
    provenance=[ordered]@{ evidence=@($evidence) }
    families=@($families)
}
[void](New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput -Parent))
$catalog | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $resolvedOutput -Encoding UTF8
Write-Host "PASS: exported $($families.Count) UE4 semantic families to $resolvedOutput"

