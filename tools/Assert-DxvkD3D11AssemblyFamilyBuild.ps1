[CmdletBinding()]
param([Parameter(Mandatory)][string]$ManifestPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-ExactProperties {
    param($Object, [string[]]$Names, [string]$Context)
    $actual = @($Object.PSObject.Properties.Name | Sort-Object)
    $expected = @($Names | Sort-Object)
    if (@(Compare-Object $actual $expected).Count) {
        throw "$Context has missing or unexpected properties. Expected: $($expected -join ', '); actual: $($actual -join ', ')"
    }
}

function Assert-Sha256([string]$Value, [string]$Context) {
    if ($Value -notmatch '^[0-9A-Fa-f]{64}$') { throw "$Context is not SHA-256: $Value" }
}

function Assert-FileHash([string]$Path, [string]$Expected, [string]$Context) {
    Assert-Sha256 $Expected "$Context expected hash"
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Context is missing: $Path" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
    if ($actual -ne $Expected.ToUpperInvariant()) { throw "$Context hash mismatch: $Path" }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Assert-UnderRoot([string]$Path, [string]$Root, [string]$Context) {
    $full = [IO.Path]::GetFullPath($Path)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    if (-not $full.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Context escapes its required root: $full"
    }
    return $full
}

function Get-UnseededFnv1([string]$Path) {
    $value = [Numerics.BigInteger]::Zero
    $prime = [Numerics.BigInteger]::Parse('1099511628211')
    $mask = [Numerics.BigInteger]::Parse('18446744073709551615')
    foreach ($byte in [IO.File]::ReadAllBytes($Path)) {
        $value = ($value * $prime) -band $mask
        $value = $value -bxor [int]$byte
    }
    $hex = $value.ToString('x')
    if ($hex.Length -gt 16) { $hex = $hex.Substring($hex.Length - 16) }
    return $hex.PadLeft(16, '0')
}

function Get-CompatibilityStatus([string]$Checker, [string]$Original, [string]$Replacement) {
    $messages = @(& $Checker $Original $Replacement 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Independent compatibility check failed: $($messages -join ' ')" }
    if (($messages -join ' ') -match 'disassembled binding declarations') {
        return 'passed-declaration-contract-rdef-unavailable'
    }
    return 'passed-reflection-contract'
}

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$manifestFile = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
$buildRoot = (Split-Path -Parent $manifestFile).TrimEnd('\')
if (-not $buildRoot.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing family-build evidence outside workspace artifacts: $buildRoot"
}
if ([IO.Path]::GetFileName($manifestFile) -ne 'family-build.json') { throw 'Family-build manifest must be named family-build.json.' }

$manifest = Get-Content -Raw -LiteralPath $manifestFile | ConvertFrom-Json
Assert-ExactProperties $manifest @(
    'schemaVersion','kind','catalogId','familyId','logicalName','implementationId','adapter','api','bytecodeFormat','stage',
    'identityModel','targetCount','sourceDirectory','originalDirectory','familyCatalogPath','familyCatalogSha256','constantMapPath',
    'constantMapSha256','assemblerPath','assemblerSha256','compatibilityCheckerPath','compatibilityCheckerSha256','variants',
    'generatedUtc','installed','runtimeEligible'
) 'DXVK assembly family-build manifest'
if ($manifest.schemaVersion -ne 1 -or $manifest.kind -ne 'dxvk-d3d11-assembly-family-build') { throw 'Unexpected family-build schema or kind.' }
if ($manifest.api -ne 'D3D11' -or $manifest.bytecodeFormat -ne 'DXBC' -or $manifest.identityModel -ne '3dmigoto-dxbc-fnv1-v1') { throw 'Family build is not the reviewed D3D11/DXBC identity model.' }
if ($manifest.stage -notin @('vs','hs','ds','gs','ps','cs')) { throw "Invalid family-build stage: $($manifest.stage)" }
if ($manifest.installed -ne $false -or $manifest.runtimeEligible -ne $false) { throw 'Family build must remain non-installing and non-runtime-eligible.' }

$sourceRoot = Assert-UnderRoot ([string]$manifest.sourceDirectory) $workspace 'Family source directory'
$originalRoot = Assert-UnderRoot ([string]$manifest.originalDirectory) $workspace 'Original DXBC directory'
if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { throw "Family source directory is missing: $sourceRoot" }
if (-not (Test-Path -LiteralPath $originalRoot -PathType Container)) { throw "Original DXBC directory is missing: $originalRoot" }
$catalogPath = Assert-FileHash ([string]$manifest.familyCatalogPath) ([string]$manifest.familyCatalogSha256) 'Reviewed family catalog'
$constantMap = Assert-FileHash ([string]$manifest.constantMapPath) ([string]$manifest.constantMapSha256) 'Controller constant map'
$assembler = Assert-FileHash ([string]$manifest.assemblerPath) ([string]$manifest.assemblerSha256) 'Pinned assembler'
$checker = Assert-FileHash ([string]$manifest.compatibilityCheckerPath) ([string]$manifest.compatibilityCheckerSha256) 'Compatibility checker'
foreach ($path in @($catalogPath,$constantMap,$assembler,$checker)) { [void](Assert-UnderRoot $path $workspace 'Family-build dependency') }

& (Join-Path $PSScriptRoot 'Assert-ShaderFamilyCatalog.ps1') -CatalogPath $catalogPath -Quiet
$catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
if ($catalog.id -ne $manifest.catalogId) { throw 'Family-build catalog ID does not match its pinned catalog.' }
$families = @($catalog.families | Where-Object { $_.id -eq $manifest.familyId })
if ($families.Count -ne 1) { throw 'Family-build family does not resolve uniquely in its pinned catalog.' }
$family = $families[0]
$implementations = @($family.implementations | Where-Object {
    $_.id -eq $manifest.implementationId -and $_.adapter -eq $manifest.adapter -and $_.api -eq $manifest.api -and
    $_.bytecodeFormat -eq $manifest.bytecodeFormat -and $_.stage -eq $manifest.stage -and $_.identityModel -eq $manifest.identityModel
})
if ($implementations.Count -ne 1) { throw 'Family-build implementation does not resolve uniquely in its pinned catalog.' }
if ($family.logicalName -ne $manifest.logicalName) { throw 'Family-build logical name does not match its pinned catalog.' }
$implementation = $implementations[0]

$catalogTargets = @{}
foreach ($variant in @($implementation.variants)) {
    foreach ($target in @($variant.targets)) {
        $identity = "$(([string]$target.shaderHash).ToLowerInvariant())-$($manifest.stage)"
        if ($catalogTargets.ContainsKey($identity)) { throw "Duplicate catalog target: $identity" }
        $catalogTargets[$identity] = [pscustomobject]@{ VariantId=[string]$variant.id; VersionGroup=[string]$target.versionGroup }
    }
}
$records = @($manifest.variants)
if ($manifest.targetCount -ne $catalogTargets.Count -or $records.Count -ne $catalogTargets.Count) { throw 'Family-build target count does not exactly match its pinned catalog.' }

$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$expectedFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
[void]$expectedFiles.Add($manifestFile)
foreach ($record in $records) {
    Assert-ExactProperties $record @(
        'identity','hash','stage','variantId','versionGroup','sourcePath','sourceSha256','originalPath','originalSha256',
        'specializedAssembly','specializedAssemblySha256','specializationManifest','specializationManifestSha256',
        'replacementBinary','replacementBinarySha256','replacementManifest','replacementManifestSha256','compatibilityStatus'
    ) "Family-build variant '$($record.identity)'"
    $identity = [string]$record.identity
    if ($identity -notmatch '^([0-9a-f]{16})-(vs|hs|ds|gs|ps|cs)$') { throw "Invalid family-build identity: $identity" }
    if (-not $seen.Add($identity)) { throw "Duplicate family-build identity: $identity" }
    if ($record.hash -ne $Matches[1] -or $record.stage -ne $Matches[2] -or $record.stage -ne $manifest.stage) { throw "Family-build identity fields disagree: $identity" }
    if (-not $catalogTargets.ContainsKey($identity)) { throw "Family-build identity is absent from its pinned catalog: $identity" }
    $target = $catalogTargets[$identity]
    if ($record.variantId -ne $target.VariantId -or $record.versionGroup -ne $target.VersionGroup) { throw "Family-build catalog metadata mismatch: $identity" }

    $source = Assert-FileHash ([string]$record.sourcePath) ([string]$record.sourceSha256) "Source shader $identity"
    $original = Assert-FileHash ([string]$record.originalPath) ([string]$record.originalSha256) "Original DXBC $identity"
    [void](Assert-UnderRoot $source $sourceRoot "Source shader $identity")
    [void](Assert-UnderRoot $original $originalRoot "Original DXBC $identity")
    if ((Get-UnseededFnv1 $original) -ne $record.hash) { throw "Original DXBC identity mismatch: $identity" }

    $specialized = Assert-FileHash ([string]$record.specializedAssembly) ([string]$record.specializedAssemblySha256) "Specialized assembly $identity"
    $specializationManifest = Assert-FileHash ([string]$record.specializationManifest) ([string]$record.specializationManifestSha256) "Specialization manifest $identity"
    $replacement = Assert-FileHash ([string]$record.replacementBinary) ([string]$record.replacementBinarySha256) "Replacement DXBC $identity"
    $replacementManifest = Assert-FileHash ([string]$record.replacementManifest) ([string]$record.replacementManifestSha256) "Replacement manifest $identity"
    foreach ($path in @($specialized,$specializationManifest,$replacement,$replacementManifest)) {
        [void](Assert-UnderRoot $path $buildRoot "Generated family artifact $identity")
        [void]$expectedFiles.Add($path)
    }
    if ($specialized -notlike (Join-Path $buildRoot 'source\*') -or $specializationManifest -notlike (Join-Path $buildRoot 'source\*') -or
        $replacement -notlike (Join-Path $buildRoot 'replacement\*') -or $replacementManifest -notlike (Join-Path $buildRoot 'replacement\*')) {
        throw "Generated family artifact is in the wrong subdirectory: $identity"
    }
    $executableAssembly = (@(Get-Content -LiteralPath $specialized | Where-Object { $_ -notmatch '^\s*//' }) -join [Environment]::NewLine)
    if ($executableAssembly -match '\bt120\b') { throw "Specialized assembly still declares or reads t120: $identity" }
    $bytes = [IO.File]::ReadAllBytes($replacement)
    if ($bytes.Length -lt 4 -or [Text.Encoding]::ASCII.GetString($bytes,0,4) -ne 'DXBC') { throw "Replacement is not DXBC: $identity" }

    $specialization = Get-Content -Raw -LiteralPath $specializationManifest | ConvertFrom-Json
    Assert-ExactProperties $specialization @('schemaVersion','kind','sourcePath','sourceSha256','constantMapPath','constantMapSha256','resource','declarationsRemoved','loadsReplaced','replacements','outputPath','outputSha256','generatedUtc','runtimeEligible','installed') "Specialization manifest $identity"
    if ($specialization.schemaVersion -ne 1 -or $specialization.kind -ne 'dxvk-migoto-texture-constant-specialization' -or
        $specialization.sourcePath -ne $source -or $specialization.sourceSha256.ToUpperInvariant() -ne $record.sourceSha256.ToUpperInvariant() -or
        $specialization.constantMapPath -ne $constantMap -or $specialization.constantMapSha256.ToUpperInvariant() -ne $manifest.constantMapSha256.ToUpperInvariant() -or
        $specialization.resource -ne 't120' -or $specialization.declarationsRemoved -ne 1 -or $specialization.loadsReplaced -lt 1 -or
        $specialization.outputPath -ne $specialized -or $specialization.outputSha256.ToUpperInvariant() -ne $record.specializedAssemblySha256.ToUpperInvariant() -or
        $specialization.runtimeEligible -ne $false -or $specialization.installed -ne $false) { throw "Specialization evidence is inconsistent: $identity" }

    $provenance = Get-Content -Raw -LiteralPath $replacementManifest | ConvertFrom-Json
    Assert-ExactProperties $provenance @('schemaVersion','backend','identity','hash','stage','profile','sourceFormat','sourcePath','sourceSha256','originalPath','originalSha256','originalIdentityVerified','compatibilityStatus','familyCatalogPath','familyCatalogSha256','reviewedFamily','outputPath','outputSha256','assemblerPath','assemblerSha256','assemblerVersion','compatibilityCheckerPath','compatibilityCheckerSha256','generatedUtc','runtimeEligible','installed') "Replacement manifest $identity"
    if ($provenance.schemaVersion -ne 1 -or $provenance.backend -ne 'dxvk-d3d11' -or $provenance.identity -ne $identity -or
        $provenance.hash -ne $record.hash -or $provenance.stage -ne $record.stage -or $provenance.profile -ne "$($record.stage)_5_0" -or
        $provenance.sourceFormat -ne 'd3d-assembly' -or $provenance.sourcePath -ne $specialized -or
        $provenance.sourceSha256.ToUpperInvariant() -ne $record.specializedAssemblySha256.ToUpperInvariant() -or
        $provenance.originalPath -ne $original -or $provenance.originalSha256.ToUpperInvariant() -ne $record.originalSha256.ToUpperInvariant() -or
        $provenance.originalIdentityVerified -ne $true -or $provenance.familyCatalogPath -ne $catalogPath -or
        $provenance.familyCatalogSha256.ToUpperInvariant() -ne $manifest.familyCatalogSha256.ToUpperInvariant() -or
        $provenance.outputPath -ne $replacement -or $provenance.outputSha256.ToUpperInvariant() -ne $record.replacementBinarySha256.ToUpperInvariant() -or
        $provenance.assemblerPath -ne $assembler -or $provenance.assemblerSha256.ToUpperInvariant() -ne $manifest.assemblerSha256.ToUpperInvariant() -or
        $provenance.compatibilityCheckerPath -ne $checker -or $provenance.compatibilityCheckerSha256.ToUpperInvariant() -ne $manifest.compatibilityCheckerSha256.ToUpperInvariant() -or
        $provenance.reviewedFamily.catalogId -ne $manifest.catalogId -or $provenance.reviewedFamily.familyId -ne $manifest.familyId -or
        $provenance.reviewedFamily.implementationId -ne $manifest.implementationId -or $provenance.reviewedFamily.variantId -ne $record.variantId -or
        $provenance.reviewedFamily.versionGroup -ne $record.versionGroup -or $provenance.runtimeEligible -ne $false -or $provenance.installed -ne $false) {
        throw "Replacement provenance is inconsistent: $identity"
    }
    $compatibility = Get-CompatibilityStatus $checker $original $replacement
    if ($compatibility -ne $record.compatibilityStatus -or $compatibility -ne $provenance.compatibilityStatus) { throw "Compatibility status drift: $identity" }
}

if ($seen.Count -ne $catalogTargets.Count) { throw 'Family-build identities do not exactly cover the pinned catalog implementation.' }
$actualFiles = @(Get-ChildItem -LiteralPath $buildRoot -Recurse -File | ForEach-Object { $_.FullName })
if (@(Compare-Object @($expectedFiles | Sort-Object) @($actualFiles | Sort-Object)).Count) { throw 'Family-build directory contains an unlisted file or lists a missing file.' }

Write-Host "PASS: independently validated $($seen.Count) hash-closed $($manifest.familyId)/$($manifest.stage) variants."
[pscustomobject]@{ManifestPath=$manifestFile;FamilyId=[string]$manifest.familyId;VariantCount=$seen.Count;Installed=$false;RuntimeEligible=$false}
