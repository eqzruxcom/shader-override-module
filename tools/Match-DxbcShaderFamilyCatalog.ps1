[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ShaderDirectory,
    [string]$CatalogPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\ue4-dxbc-semantic-family-catalog.json'),
    [string]$OutputPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\ue4-dxbc-semantic-catalog-matches.json'),
    [switch]$ExcludeReplacementArtifacts,
    [ValidateRange(0,100)]
    [int]$NearMatchLimitPerDescriptor = 0,
    [double]$MatchTimeoutSeconds = 1.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$artifacts = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts'))
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
if (-not $resolvedOutput.StartsWith($artifacts + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "OutputPath must remain beneath $artifacts" }
$resolvedCatalog = (Resolve-Path -LiteralPath $CatalogPath -ErrorAction Stop).Path
$resolvedShaders = (Resolve-Path -LiteralPath $ShaderDirectory -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $resolvedShaders -PathType Container)) { throw "ShaderDirectory not found: $ShaderDirectory" }
& (Join-Path $PSScriptRoot 'Assert-ShaderFamilyCatalog.ps1') -CatalogPath $resolvedCatalog -Quiet
$catalog = Get-Content -Raw -LiteralPath $resolvedCatalog | ConvertFrom-Json

$semanticEntries = [Collections.Generic.List[object]]::new()
foreach ($family in @($catalog.families)) {
    foreach ($implementation in @($family.implementations | Where-Object { $_.identityModel -eq 'ue4-dxbc-regex-semantic-v1' })) {
        if ($implementation.api -ne 'D3D11' -or $implementation.bytecodeFormat -ne 'DXBC') { throw "Semantic identity is not D3D11/DXBC: $($implementation.id)" }
        foreach ($variant in @($implementation.variants)) {
            $semanticEntries.Add([pscustomobject]@{ family=$family; implementation=$implementation; variant=$variant })
        }
    }
}
if ($semanticEntries.Count -lt 1) { throw "Catalog contains no ue4-dxbc-regex-semantic-v1 implementation: $resolvedCatalog" }

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$work = Join-Path $tempRoot ('ue4fx-family-catalog-match-' + [guid]::NewGuid().ToString('N'))
$descriptorDirectory = Join-Path $work 'descriptors'
$rawReportPath = Join-Path $work 'semantic-report.json'
try {
    [void](New-Item -ItemType Directory -Force -Path $descriptorDirectory)
    Copy-Item -LiteralPath (Join-Path $workspace 'src\Engine\UE4\PassDescriptors\schema.json') -Destination (Join-Path $descriptorDirectory 'schema.json')
    foreach ($entry in $semanticEntries) {
        $identity = $entry.variant.identity
        $descriptor = [ordered]@{
            schemaVersion=1
            id=[string]$identity.descriptorId
            family=if ($null -ne $entry.implementation.PSObject.Properties['role']) { [string]$entry.implementation.role } else { [string]$entry.family.id }
            displayName=[string]$entry.family.logicalName
            description=if ($null -ne $entry.family.PSObject.Properties['description']) { [string]$entry.family.description } else { [string]$entry.family.logicalName }
            stages=@([string]$entry.implementation.stage)
            shaderModels=@($entry.implementation.shaderModels)
            hashFastPaths=@($identity.hashFastPaths | ForEach-Object {
                $fast=[ordered]@{adapter=[string]$_.adapter;hash=([string]$_.hash).ToLowerInvariant()}
                if ($null -ne $_.PSObject.Properties['evidence']) {$fast['evidence']=[string]$_.evidence}
                $fast
            })
            semanticSignature=[ordered]@{checks=@($identity.checks)}
            runtimeContract=if ($null -ne $entry.implementation.PSObject.Properties['runtimeContract']) {$entry.implementation.runtimeContract} else {@{}}
            sourceEvidence=if ($null -ne $entry.implementation.PSObject.Properties['evidence']) {@($entry.implementation.evidence)} else {@()}
        }
        $descriptorPath = Join-Path $descriptorDirectory ("$($identity.descriptorId).json")
        [IO.File]::WriteAllText($descriptorPath,(($descriptor|ConvertTo-Json -Depth 12)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
    }

    $matcherArgs = @{
        ShaderDirectory=$resolvedShaders
        DescriptorDirectory=$descriptorDirectory
        OutputPath=$rawReportPath
        NearMatchLimitPerDescriptor=$NearMatchLimitPerDescriptor
        MatchTimeoutSeconds=$MatchTimeoutSeconds
    }
    if ($ExcludeReplacementArtifacts) { $matcherArgs['ExcludeReplacementArtifacts']=$true }
    & (Join-Path $PSScriptRoot 'Match-UE4SemanticPasses.ps1') @matcherArgs | Out-Host
    $raw = Get-Content -Raw -LiteralPath $rawReportPath | ConvertFrom-Json
    $report = [ordered]@{
        schemaVersion=1
        matcher='portable-family-catalog-dxbc-semantic'
        catalog=[ordered]@{
            id=[string]$catalog.id
            path=$resolvedCatalog
            sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedCatalog).Hash.ToUpperInvariant()
            identityModel='ue4-dxbc-regex-semantic-v1'
            semanticImplementationCount=$semanticEntries.Count
        }
        shaderScan=$raw.shaders
        descriptorSchema=[ordered]@{
            file=(Join-Path $workspace 'src\Engine\UE4\PassDescriptors\schema.json')
            sha256=[string]$raw.descriptorSchema.sha256
        }
        matchTimeouts=@($raw.matchTimeouts)
        matches=@($raw.matches)
    }
    if ($null -ne $raw.PSObject.Properties['nearMatches']) { $report['nearMatches']=@($raw.nearMatches) }
    [void](New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput -Parent))
    $report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $resolvedOutput -Encoding UTF8
    Write-Host "PASS: catalog semantic scan found $(@($raw.matches).Count) matches with $(@($raw.matchTimeouts).Count) regex timeouts."
    Write-Host "Report: $resolvedOutput"
}
finally {
    if (Test-Path -LiteralPath $work) {
        $resolvedWork=[IO.Path]::GetFullPath($work)
        $leaf=Split-Path -Leaf $resolvedWork
        if (-not $resolvedWork.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or -not $leaf.StartsWith('ue4fx-family-catalog-match-',[StringComparison]::Ordinal)) { throw "Refusing to remove unexpected test path: $resolvedWork" }
        Remove-Item -LiteralPath $resolvedWork -Recurse -Force
    }
}
