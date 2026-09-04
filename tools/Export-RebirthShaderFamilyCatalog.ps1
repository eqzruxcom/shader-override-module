[CmdletBinding()]
param(
    [string]$AuditPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\rebirth-shader-injector-v2.2.1-preset-audit.json'),
    [string]$OutputPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\rebirth-shader-injector-v2.2.1-family-catalog.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$artifacts = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts'))
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
if (-not $resolvedOutput.StartsWith($artifacts + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must remain beneath $artifacts"
}
if (-not (Test-Path -LiteralPath $AuditPath -PathType Leaf)) { throw "Audit report not found: $AuditPath" }

function Convert-ToKebab([string]$Value) {
    $withBoundaries = [regex]::Replace($Value, '([a-z0-9])([A-Z])', '$1-$2')
    return ([regex]::Replace($withBoundaries, '[^A-Za-z0-9]+', '-')).Trim('-').ToLowerInvariant()
}

function Get-UniqueSorted($Values) {
    $result = @($Values | ForEach-Object { ([string]$_).ToUpperInvariant() } | Sort-Object -Unique)
    return ,$result
}

$audit = Get-Content -Raw -LiteralPath $AuditPath | ConvertFrom-Json
if ($audit.SchemaVersion -ne 1 -or $audit.FingerprintInventory.Count -ne 44) {
    throw 'Unsupported or incomplete Rebirth preset audit'
}

$stageMap = @{ PixelShader = 'ps'; ComputeShader = 'cs'; VertexShader = 'vs'; GeometryShader = 'gs'; HullShader = 'hs'; DomainShader = 'ds' }
$families = foreach ($familyGroup in @($audit.FingerprintInventory.Targets | Group-Object Family | Sort-Object Name)) {
    $familyId = Convert-ToKebab $familyGroup.Name
    $stages = @($familyGroup.Group.Stage | Sort-Object -Unique)
    if ($stages.Count -ne 1 -or -not $stageMap.ContainsKey([string]$stages[0])) {
        throw "Family $($familyGroup.Name) does not have one recognized stage"
    }
    $profiles = @($familyGroup.Group.ShaderProfile | Sort-Object -Unique)
    $variants = foreach ($variantGroup in @($familyGroup.Group | Group-Object CrossVersionIdentityHash | Sort-Object Name)) {
        $crossHash = ([string]$variantGroup.Name).ToUpperInvariant()
        [ordered]@{
            id = "cross-$($crossHash.ToLowerInvariant())"
            identity = [ordered]@{
                crossVersionIdentityHash = $crossHash
                interfaceSignatureHashes = Get-UniqueSorted $variantGroup.Group.InterfaceSignatureHash
                resourceSignatureHashes = Get-UniqueSorted $variantGroup.Group.ResourceSignatureHash
                constantBufferSignatureHashes = Get-UniqueSorted $variantGroup.Group.ConstantBufferSignatureHash
                executionSignatureHashes = Get-UniqueSorted $variantGroup.Group.ExecutionSignatureHash
                portableReflectionIdentityHashes = Get-UniqueSorted $variantGroup.Group.PortableReflectionIdentityHash
                semanticInstructionSetHashes = Get-UniqueSorted $variantGroup.Group.SemanticInstructionSetHash
            }
            targets = @($variantGroup.Group | Sort-Object VersionGroup | ForEach-Object {
                [ordered]@{
                    versionGroup = [string]$_.VersionGroup
                    shaderHash = ([string]$_.TargetHash).ToUpperInvariant()
                    bytecodeLength = [int64]$_.OriginalBytecodeLength
                    entryFunction = [string]$_.EntryFunction
                    sourceFile = [string]$_.SourceFile
                    compiledBlobFile = [string]$_.CompiledBlobFile
                }
            })
        }
    }
    [ordered]@{
        id = $familyId
        logicalName = [string]$familyGroup.Name
        implementations = @([ordered]@{
            id = "ff7-rebirth-d3d12-$familyId"
            adapter = 'FF7Rebirth-ShaderInjector-v2.2.1'
            api = 'D3D12'
            bytecodeFormat = 'DXIL'
            stage = $stageMap[[string]$stages[0]]
            shaderModels = $profiles
            identityModel = 'shader-injector-dxil-analysis-v1'
            variants = @($variants)
        })
    }
}

$catalog = [ordered]@{
    schemaVersion = 1
    kind = 'shader-family-catalog'
    id = 'ff7-rebirth-shader-injector-v2-2-1'
    displayName = 'FF7 Rebirth Shader Injector v2.2.1 donor families'
    provenance = [ordered]@{ evidence = @(
        [ordered]@{
            kind = 'audit-report'
            label = 'Reproducible preset and fingerprint audit'
            path = [IO.Path]::GetRelativePath($workspace, [IO.Path]::GetFullPath($AuditPath)).Replace('\', '/')
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $AuditPath).Hash.ToUpperInvariant()
        },
        [ordered]@{ kind = 'archive'; label = 'Performance'; sha256 = ([string]$audit.Archives.Performance.Sha256).ToUpperInvariant() },
        [ordered]@{ kind = 'archive'; label = 'MaximumQuality'; sha256 = ([string]$audit.Archives.MaximumQuality.Sha256).ToUpperInvariant() }
    ) }
    families = @($families)
}

[void](New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput -Parent))
$catalog | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resolvedOutput -Encoding UTF8
Write-Host "PASS: exported 11 portable donor families to $resolvedOutput"
