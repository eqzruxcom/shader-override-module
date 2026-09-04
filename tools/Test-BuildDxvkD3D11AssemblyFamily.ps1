[CmdletBinding()]
param(
    [string]$PositiveManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\dxvk-d3d11-contact-family-automated-20260901-v2\family-build.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Assert-Throws([scriptblock]$Action, [string]$Pattern, [string]$Label) {
    try {
        & $Action
    } catch {
        $message = [string]$_.Exception.Message
        if ($message -notmatch $Pattern) {
            throw "$Label rejected for the wrong reason. Expected /$Pattern/; got: $message"
        }
        Write-Host "PASS: $Label rejected: $message"
        return
    }
    throw "$Label unexpectedly succeeded."
}

$manifestPath = (Resolve-Path -LiteralPath $PositiveManifestPath -ErrorAction Stop).Path
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
Assert-True ($manifest.kind -eq 'dxvk-d3d11-assembly-family-build') 'Positive evidence has the wrong kind.'
Assert-True ($manifest.familyId -eq 'tiled-surface-light-evaluation') 'Positive evidence has the wrong family.'
Assert-True ($manifest.targetCount -eq 5 -and @($manifest.variants).Count -eq 5) 'Positive evidence does not contain all five variants.'
Assert-True ($manifest.installed -eq $false -and $manifest.runtimeEligible -eq $false) 'Positive evidence must remain offline.'
foreach ($variant in @($manifest.variants)) {
    Assert-True (Test-Path -LiteralPath $variant.specializedAssembly -PathType Leaf) "Missing specialized assembly for $($variant.identity)."
    Assert-True (Test-Path -LiteralPath $variant.replacementBinary -PathType Leaf) "Missing replacement binary for $($variant.identity)."
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $variant.specializedAssembly).Hash -eq $variant.specializedAssemblySha256) "Specialized assembly hash drift for $($variant.identity)."
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $variant.replacementBinary).Hash -eq $variant.replacementBinarySha256) "Replacement hash drift for $($variant.identity)."
}
Write-Host 'PASS: retained positive family evidence contains five hash-verified offline variants.'

$builder = Join-Path $PSScriptRoot 'Build-DxvkD3D11AssemblyFamily.ps1'
$sourceRoot = [string]$manifest.sourceDirectory
$originalRoot = [string]$manifest.originalDirectory
$catalogPath = [string]$manifest.familyCatalogPath
$constantMap = [string]$manifest.constantMapPath
$assembler = [string]$manifest.assemblerPath
$checker = [string]$manifest.compatibilityCheckerPath
$familyId = [string]$manifest.familyId

$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempParent ('dxvk-family-regression-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
try {
    $existingOutput = Join-Path $testRoot 'already-exists'
    [IO.Directory]::CreateDirectory($existingOutput) | Out-Null
    Assert-Throws {
        & $builder -SourceDirectory $sourceRoot -OriginalDirectory $originalRoot `
            -FamilyCatalogPath $catalogPath -ConstantMapPath $constantMap -FamilyId $familyId `
            -OutputDirectory $existingOutput -AssemblerPath $assembler -CompatibilityCheckerPath $checker
    } 'Refusing to overwrite an existing family build' 'existing family output'

    $wrongFamilyOutput = Join-Path $testRoot 'wrong-family'
    Assert-Throws {
        & $builder -SourceDirectory $sourceRoot -OriginalDirectory $originalRoot `
            -FamilyCatalogPath $catalogPath -ConstantMapPath $constantMap -FamilyId '__not_a_reviewed_family__' `
            -OutputDirectory $wrongFamilyOutput -AssemblerPath $assembler -CompatibilityCheckerPath $checker
    } "FamilyId '__not_a_reviewed_family__' matched 0 reviewed families" 'unknown family identity'

    $incompleteSource = Join-Path $testRoot 'incomplete-source'
    [IO.Directory]::CreateDirectory($incompleteSource) | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $sourceRoot -File) {
        Copy-Item -LiteralPath $file.FullName -Destination $incompleteSource
    }
    $firstIdentity = [string](@($manifest.variants | Sort-Object identity)[0].identity)
    $candidatePaths = @(
        (Join-Path $incompleteSource "$firstIdentity.txt"),
        (Join-Path $incompleteSource "$firstIdentity.asm"),
        (Join-Path $incompleteSource ($firstIdentity -replace '-cs$', '-cs_replace.txt')),
        (Join-Path $incompleteSource ($firstIdentity -replace '-cs$', '-cs_replace.asm'))
    )
    foreach ($candidate in $candidatePaths) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { Remove-Item -LiteralPath $candidate -Force }
    }
    $incompleteOutput = Join-Path $testRoot 'incomplete-output'
    Assert-Throws {
        & $builder -SourceDirectory $incompleteSource -OriginalDirectory $originalRoot `
            -FamilyCatalogPath $catalogPath -ConstantMapPath $constantMap -FamilyId $familyId `
            -OutputDirectory $incompleteOutput -AssemblerPath $assembler -CompatibilityCheckerPath $checker
    } "Reviewed target $([regex]::Escape($firstIdentity)) has 0 matching source files" 'incomplete reviewed family source set'

    Write-Host 'PASS: family builder fail-closed regressions passed.'
} finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    if ($resolvedTestRoot.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedTestRoot).StartsWith('dxvk-family-regression-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        throw "Refusing to clean unexpected test path: $resolvedTestRoot"
    }
}
