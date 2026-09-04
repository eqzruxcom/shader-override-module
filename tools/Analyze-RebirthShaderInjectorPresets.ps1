[CmdletBinding()]
param(
    [string]$PerformanceArchive = 'F:\New folder\package\New folder\New folder\Shader Injector v2.2.1 (Performance Preset) 2153 2.2.1 2026-07-31T16-21Z rP4B0ThId.zip',
    [string]$QualityArchive = 'F:\New folder\package\New folder\New folder\Shader Injector v2.2.1 (Maximum Quality Preset) 2153 2.2.1 2026-07-31T16-21Z sMpd9F7eU.zip',
    [string]$OutputPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\rebirth-shader-injector-v2.2.1-preset-audit.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$ExpectedPerformanceHash = '21C8715F311B1B25CE8C19489F97729F7CBD0846B1A18AF5C976349C74EDE4BA'
$ExpectedQualityHash = 'CED1790992265E203E0DB418203881D5570A58C5AF0663E5F50C05A7996CD119'
$WorkspaceRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$ArtifactsRoot = [IO.Path]::GetFullPath((Join-Path $WorkspaceRoot 'artifacts'))
$ResolvedOutput = [IO.Path]::GetFullPath($OutputPath)
if (-not $ResolvedOutput.StartsWith($ArtifactsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must remain beneath $ArtifactsRoot"
}

function Get-FileSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Archive not found: $Path"
    }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Get-NormalizedEntryPath([string]$FullName) {
    $parts = $FullName.Replace('\', '/').Split('/', [StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -lt 2) {
        throw "ZIP entry has no removable package root: $FullName"
    }
    return ($parts[1..($parts.Count - 1)] -join '/')
}

function Read-EntryBytes([IO.Compression.ZipArchiveEntry]$Entry) {
    $stream = $Entry.Open()
    try {
        $memory = [IO.MemoryStream]::new()
        try {
            $stream.CopyTo($memory)
            return $memory.ToArray()
        }
        finally {
            $memory.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-BytesSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Get-ZipInventory([string]$Path, [string]$ExpectedHash) {
    $actualHash = Get-FileSha256 $Path
    if ($actualHash -ne $ExpectedHash) {
        throw "Archive hash mismatch for $Path. Expected $ExpectedHash; got $actualHash"
    }

    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $files = [ordered]@{}
        foreach ($entry in $archive.Entries) {
            if ([string]::IsNullOrEmpty($entry.Name)) { continue }
            $normalized = Get-NormalizedEntryPath $entry.FullName
            if ($files.Contains($normalized)) {
                throw "Duplicate normalized path in ${Path}: $normalized"
            }
            $bytes = Read-EntryBytes $entry
            $files[$normalized] = [pscustomobject]@{
                Path = $normalized
                Size = [int64]$bytes.LongLength
                Sha256 = Get-BytesSha256 $bytes
                Bytes = $bytes
            }
        }
        return [pscustomobject]@{
            Path = [IO.Path]::GetFullPath($Path)
            Sha256 = $actualHash
            Files = $files
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Get-UniqueFileByName($Inventory, [string]$FileName) {
    $matches = @($Inventory.Files.Values | Where-Object { [IO.Path]::GetFileName($_.Path) -eq $FileName })
    if ($matches.Count -ne 1) {
        throw "Expected one $FileName entry; found $($matches.Count)"
    }
    return $matches[0]
}

function Convert-BytesToText([byte[]]$Bytes) {
    return [Text.Encoding]::UTF8.GetString($Bytes).TrimStart([char]0xFEFF)
}

function Test-DefineEnabled([string]$Text, [string]$Name) {
    return [regex]::IsMatch($Text, "(?m)^\s*#define\s+$([regex]::Escape($Name))\b")
}

$performance = Get-ZipInventory $PerformanceArchive $ExpectedPerformanceHash
$quality = Get-ZipInventory $QualityArchive $ExpectedQualityHash

$performancePaths = @($performance.Files.Keys | Sort-Object)
$qualityPaths = @($quality.Files.Keys | Sort-Object)
$pathDelta = @((Compare-Object $performancePaths $qualityPaths))
if ($pathDelta.Count -ne 0) {
    throw "Preset normalized path sets differ: $($pathDelta | Out-String)"
}

$identical = [Collections.Generic.List[string]]::new()
$different = [Collections.Generic.List[string]]::new()
foreach ($path in $performancePaths) {
    if ($performance.Files[$path].Sha256 -eq $quality.Files[$path].Sha256) {
        $identical.Add($path)
    }
    else {
        $different.Add($path)
    }
}

$differentSources = @($different | Where-Object { $_ -like '*.hlsl' })
$differentBlobs = @($different | Where-Object { $_ -like '*.blob' })
$expectedSourceNames = @(
    'ComputeShaderPass_ReflectionEnvironment.hlsl',
    'ComputeShaderPass_SampleGI.hlsl',
    'PixelShaderPass_PostProcessFinal.hlsl'
) | Sort-Object
$actualSourceNames = @($differentSources | ForEach-Object { [IO.Path]::GetFileName($_) } | Sort-Object)
if (@(Compare-Object $expectedSourceNames $actualSourceNames).Count -ne 0) {
    throw "Unexpected set of differing HLSL files: $($actualSourceNames -join ', ')"
}

$featureSpecs = @(
    [pscustomobject]@{ Source = 'ComputeShaderPass_ReflectionEnvironment.hlsl'; Define = 'SSGI_AMBIENT_OCCLUSION' },
    [pscustomobject]@{ Source = 'ComputeShaderPass_ReflectionEnvironment.hlsl'; Define = 'SSGI_BOUNCE_LIGHT' },
    [pscustomobject]@{ Source = 'ComputeShaderPass_SampleGI.hlsl'; Define = 'CHARACTER_DOMINANT_DIRECTION_SHADING' },
    [pscustomobject]@{ Source = 'PixelShaderPass_PostProcessFinal.hlsl'; Define = 'AUTO_EXPOSURE' }
)
$features = foreach ($spec in $featureSpecs) {
    $pText = Convert-BytesToText (Get-UniqueFileByName $performance $spec.Source).Bytes
    $qText = Convert-BytesToText (Get-UniqueFileByName $quality $spec.Source).Bytes
    [pscustomobject]@{
        Source = $spec.Source
        Define = $spec.Define
        PerformanceEnabled = Test-DefineEnabled $pText $spec.Define
        MaximumQualityEnabled = Test-DefineEnabled $qText $spec.Define
    }
}
foreach ($feature in $features) {
    if ($feature.PerformanceEnabled -or -not $feature.MaximumQualityEnabled) {
        throw "Unexpected preset state for $($feature.Define)"
    }
}

$knownFamilyPattern = 'DirectionalLight|LocalLight|LocalLightIES|OceanA|PostProcessFinal|PostProcessFog|ReflectionEnvironment|SampleGI|SSR|WaterA|WaterB'
$fingerprints = [Collections.Generic.List[object]]::new()
foreach ($entry in @($quality.Files.Values | Where-Object { $_.Path -like '*_Fingerprint.json' } | Sort-Object Path)) {
    $json = Convert-BytesToText $entry.Bytes | ConvertFrom-Json
    if ($json.targets.Count -ne 1) {
        throw "Expected exactly one target in $($entry.Path)"
    }
    $target = $json.targets[0]
    $analysis = $target.shaderAnalysis
    if (-not $analysis.succeeded) {
        throw "Shader analysis was not successful in $($entry.Path)"
    }
    if ($json.name -notmatch "^(GameVersion[0-9_]+)_($knownFamilyPattern)$") {
        throw "Unexpected fingerprint name: $($json.name)"
    }
    $knownHashes = @($target.knownShaderBytecodeHashes)
    if ($knownHashes.Count -ne 1) {
        throw "Expected one known bytecode hash in $($entry.Path)"
    }
    $fingerprints.Add([pscustomobject]@{
        Name = [string]$json.name
        VersionGroup = [string]$Matches[1]
        Family = [string]$Matches[2]
        ShaderType = [int]$json.shaderType
        ShaderProfile = [string]$json.shaderProfile
        SourceFile = [string]$json.sourceFile
        CompiledBlobFile = [string]$json.compiledBlobFile
        Stage = [string]$analysis.shaderStageName
        TargetHash = [string]$knownHashes[0]
        OriginalBytecodeLength = [int64]$target.originalShaderBytecodeLength
        EntryFunction = [string]$analysis.entryFunctionName
        InterfaceSignatureHash = [string]$analysis.interfaceSignatureHash
        ResourceSignatureHash = [string]$analysis.resourceSignatureHash
        ConstantBufferSignatureHash = [string]$analysis.constantBufferSignatureHash
        ExecutionSignatureHash = [string]$analysis.executionSignatureHash
        PortableReflectionIdentityHash = [string]$analysis.portableReflectionIdentityHash
        SemanticInstructionSetHash = [string]$analysis.semanticInstructionSetHash
        CrossVersionIdentityHash = [string]$analysis.crossVersionIdentityHash
    })
}

$families = @($fingerprints.Family | Sort-Object -Unique)
$versions = @($fingerprints.VersionGroup | Sort-Object -Unique)
$stageCounts = [ordered]@{}
foreach ($group in @($fingerprints | Group-Object Stage | Sort-Object Name)) {
    $stageCounts[$group.Name] = $group.Count
}
$familyIdentityVariation = foreach ($group in @($fingerprints | Group-Object Family | Sort-Object Name)) {
    [pscustomobject]@{
        Family = $group.Name
        VersionTargetCount = $group.Count
        InterfaceIdentityCount = @($group.Group.InterfaceSignatureHash | Sort-Object -Unique).Count
        ResourceIdentityCount = @($group.Group.ResourceSignatureHash | Sort-Object -Unique).Count
        ConstantBufferIdentityCount = @($group.Group.ConstantBufferSignatureHash | Sort-Object -Unique).Count
        ExecutionIdentityCount = @($group.Group.ExecutionSignatureHash | Sort-Object -Unique).Count
        SemanticInstructionSetIdentityCount = @($group.Group.SemanticInstructionSetHash | Sort-Object -Unique).Count
        CrossVersionIdentityCount = @($group.Group.CrossVersionIdentityHash | Sort-Object -Unique).Count
    }
}

if ($performance.Files.Count -ne 158 -or $quality.Files.Count -ne 158) { throw 'Expected 158 files in each preset' }
if ($identical.Count -ne 143 -or $different.Count -ne 15) { throw 'Expected 143 identical and 15 different files' }
if ($differentSources.Count -ne 3 -or $differentBlobs.Count -ne 12) { throw 'Expected 3 differing HLSL sources and 12 differing blobs' }
if ($fingerprints.Count -ne 44 -or $families.Count -ne 11 -or $versions.Count -ne 4) { throw 'Expected 44 fingerprints, 11 families, and 4 version groups' }
if ($stageCounts.PixelShader -ne 36 -or $stageCounts.ComputeShader -ne 8) { throw 'Expected 36 pixel and 8 compute targets' }

$report = [ordered]@{
    SchemaVersion = 1
    Scope = 'Read-only comparison of the two user-provided Shader Injector v2.2.1 preset archives; no archive payload was extracted or executed.'
    Archives = [ordered]@{
        Performance = [ordered]@{ Path = $performance.Path; Sha256 = $performance.Sha256; FileCount = $performance.Files.Count }
        MaximumQuality = [ordered]@{ Path = $quality.Path; Sha256 = $quality.Sha256; FileCount = $quality.Files.Count }
    }
    Comparison = [ordered]@{
        IdenticalFileCount = $identical.Count
        DifferentFileCount = $different.Count
        DifferentPaths = @($different)
        DifferentSourcePaths = $differentSources
        DifferentCompiledBlobPaths = $differentBlobs
    }
    FunctionalPresetDifferences = @($features)
    FingerprintInventory = [ordered]@{
        Count = $fingerprints.Count
        VersionGroups = $versions
        Families = $families
        StageCounts = $stageCounts
        FamilyIdentityVariation = @($familyIdentityVariation)
        Targets = @($fingerprints)
    }
    Conclusions = @(
        'Maximum Quality enables four compile-time features that Performance disables: SSGI ambient occlusion, SSGI bounce light, character dominant-direction shading, and automatic exposure.',
        'DirectionalLight, LocalLight, LocalLightIES, contact-shadow source, and their compiled targets are byte-identical between presets.',
        'The donor inventory contains 9 pixel-shader families and 2 compute-shader families across 4 Rebirth version groups; it contains no vertex-shader replacement family.',
        'DirectionalLight, LocalLight, LocalLightIES, and SampleGI each retain one cross-version identity across all four targets; several post, reflection, ocean, SSR, and water families legitimately retain multiple identities.',
        'These DX12 SM6.6 fingerprints are architectural evidence for family discovery, not directly loadable Remake DX11 SM5 replacements.'
    )
}

$outputDirectory = Split-Path $ResolvedOutput -Parent
[void](New-Item -ItemType Directory -Force -Path $outputDirectory)
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ResolvedOutput -Encoding UTF8
Write-Host "PASS: verified both archives and wrote $ResolvedOutput"
