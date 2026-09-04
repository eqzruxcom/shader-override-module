[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceDirectory,
    [Parameter(Mandatory)][string]$OriginalDirectory,
    [Parameter(Mandatory)][string]$FamilyCatalogPath,
    [Parameter(Mandatory)][string]$ConstantMapPath,
    [Parameter(Mandatory)][string]$FamilyId,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateSet('vs','hs','ds','gs','ps','cs')][string]$Stage = 'cs',
    [string]$AssemblerPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\shader-assembler-build\bin\cmd_Decompiler.exe'),
    [string]$CompatibilityCheckerPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\dxbc-compatibility-tool\DxbcCompatibilityCheck.exe')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)

function Resolve-Directory([string]$Path, [string]$Label) {
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) { throw "$Label is not a directory: $Path" }
    return $resolved
}

function Resolve-File([string]$Path, [string]$Label) {
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "$Label is not a file: $Path" }
    return $resolved
}

$sourceRoot = Resolve-Directory $SourceDirectory 'Family source root'
$originalRoot = Resolve-Directory $OriginalDirectory 'Original DXBC root'
$catalogPath = Resolve-File $FamilyCatalogPath 'Reviewed family catalog'
$constantMap = Resolve-File $ConstantMapPath '3Dmigoto controller constant map'
$assembler = Resolve-File $AssemblerPath 'Pinned shader assembler'
$checker = Resolve-File $CompatibilityCheckerPath 'DXBC compatibility checker'
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $outputRoot) { throw "Refusing to overwrite an existing family build: $outputRoot" }

& (Join-Path $PSScriptRoot 'Assert-ShaderFamilyCatalog.ps1') -CatalogPath $catalogPath -Quiet
$catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
$families = @($catalog.families | Where-Object { [string]$_.id -eq $FamilyId })
if ($families.Count -ne 1) { throw "FamilyId '$FamilyId' matched $($families.Count) reviewed families; expected exactly one." }
$family = $families[0]
$implementations = @($family.implementations | Where-Object {
    [string]$_.api -eq 'D3D11' -and [string]$_.bytecodeFormat -eq 'DXBC' -and [string]$_.stage -eq $Stage
})
if ($implementations.Count -ne 1) { throw "Family '$FamilyId' has $($implementations.Count) D3D11/DXBC/$Stage implementations; expected exactly one." }
$implementation = $implementations[0]
if ([string]$implementation.identityModel -ne '3dmigoto-dxbc-fnv1-v1') { throw "Unsupported family identity model: $($implementation.identityModel)" }

$targets = [Collections.Generic.List[object]]::new()
$targetHashes = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($variant in @($implementation.variants)) {
    foreach ($target in @($variant.targets)) {
        $hash = ([string]$target.shaderHash).ToLowerInvariant()
        if ($hash -notmatch '^[0-9a-f]{16}$') { throw "Invalid reviewed shader hash: $hash" }
        if (-not $targetHashes.Add($hash)) { throw "Duplicate reviewed family target: $hash-$Stage" }
        $targets.Add([pscustomobject]@{ Hash=$hash; VariantId=[string]$variant.id; VersionGroup=[string]$target.versionGroup })
    }
}
if ($targets.Count -eq 0) { throw "Reviewed family '$FamilyId' has no targets for $Stage." }

[IO.Directory]::CreateDirectory((Join-Path $outputRoot 'source')) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $outputRoot 'replacement')) | Out-Null
$records = [Collections.Generic.List[object]]::new()

foreach ($target in $targets | Sort-Object Hash) {
    $hash = [string]$target.Hash
    $sourceCandidates = @(@(
        Join-Path $sourceRoot "$hash-$Stage.txt"
        Join-Path $sourceRoot "$hash-$Stage.asm"
        Join-Path $sourceRoot "$hash-${Stage}_replace.txt"
        Join-Path $sourceRoot "$hash-${Stage}_replace.asm"
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($sourceCandidates.Count -ne 1) { throw "Reviewed target $hash-$Stage has $($sourceCandidates.Count) matching source files; expected exactly one." }
    $original = Join-Path $originalRoot "$hash-$Stage.bin"
    if (-not (Test-Path -LiteralPath $original -PathType Leaf)) { throw "Reviewed target is missing original DXBC: $original" }

    $specialized = Join-Path $outputRoot "source\$hash-${Stage}_replace.asm"
    & (Join-Path $PSScriptRoot 'Convert-MigotoTextureConstantsForDxvk.ps1') `
        -SourcePath $sourceCandidates[0] -ConstantMapPath $constantMap -OutputPath $specialized
    & (Join-Path $PSScriptRoot 'Build-DxvkD3D11AssemblyReplacement.ps1') `
        -SourcePath $specialized -OriginalBytecode $original -FamilyCatalogPath $catalogPath `
        -OutputDirectory (Join-Path $outputRoot 'replacement') -AssemblerPath $assembler -CompatibilityCheckerPath $checker

    $identity = "$hash-$Stage"
    $specializationManifest = $specialized + '.specialization.json'
    $replacement = Join-Path $outputRoot "replacement\${identity}_replace.bin"
    $replacementManifest = Join-Path $outputRoot "replacement\${identity}_replace.manifest.json"
    foreach ($path in @($specialized, $specializationManifest, $replacement, $replacementManifest)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Family build output is missing: $path" }
    }
    $manifest = Get-Content -Raw -LiteralPath $replacementManifest | ConvertFrom-Json
    if ($manifest.identity -ne $identity -or $manifest.reviewedFamily.familyId -ne $FamilyId -or
        $manifest.reviewedFamily.variantId -ne $target.VariantId -or
        $manifest.reviewedFamily.versionGroup -ne $target.VersionGroup -or
        $manifest.originalIdentityVerified -ne $true -or
        $manifest.compatibilityStatus -notin @('passed-reflection-contract','passed-declaration-contract-rdef-unavailable') -or
        $manifest.installed -ne $false -or $manifest.runtimeEligible -ne $false) {
        throw "Family replacement evidence is inconsistent for $identity."
    }
    $records.Add([ordered]@{
        identity=$identity;hash=$hash;stage=$Stage;variantId=$target.VariantId;versionGroup=$target.VersionGroup
        sourcePath=(Resolve-Path -LiteralPath $sourceCandidates[0]).Path;sourceSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $sourceCandidates[0]).Hash
        originalPath=(Resolve-Path -LiteralPath $original).Path;originalSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $original).Hash
        specializedAssembly=$specialized;specializedAssemblySha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $specialized).Hash
        specializationManifest=$specializationManifest;specializationManifestSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $specializationManifest).Hash
        replacementBinary=$replacement;replacementBinarySha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $replacement).Hash
        replacementManifest=$replacementManifest;replacementManifestSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $replacementManifest).Hash
        compatibilityStatus=[string]$manifest.compatibilityStatus
    })
}

$familyManifest = [ordered]@{
    schemaVersion=1;kind='dxvk-d3d11-assembly-family-build';catalogId=[string]$catalog.id
    familyId=$FamilyId;logicalName=[string]$family.logicalName;implementationId=[string]$implementation.id
    adapter=[string]$implementation.adapter;api='D3D11';bytecodeFormat='DXBC';stage=$Stage
    identityModel=[string]$implementation.identityModel;targetCount=$targets.Count
    sourceDirectory=$sourceRoot;originalDirectory=$originalRoot
    familyCatalogPath=$catalogPath;familyCatalogSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $catalogPath).Hash
    constantMapPath=$constantMap;constantMapSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $constantMap).Hash
    assemblerPath=$assembler;assemblerSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $assembler).Hash
    compatibilityCheckerPath=$checker;compatibilityCheckerSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $checker).Hash
    variants=@($records);generatedUtc=[DateTime]::UtcNow.ToString('o');installed=$false;runtimeEligible=$false
}
$manifestPath = Join-Path $outputRoot 'family-build.json'
[IO.File]::WriteAllText($manifestPath, (($familyManifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine), $utf8)
Write-Host "PASS: built all $($records.Count) reviewed $FamilyId/$Stage variants with identity and compatibility evidence."
[pscustomobject]@{OutputDirectory=$outputRoot;ManifestPath=$manifestPath;FamilyId=$FamilyId;VariantCount=$records.Count;Installed=$false;RuntimeEligible=$false}
