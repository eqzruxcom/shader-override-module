[CmdletBinding()]
param(
    [string]$SourceManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\dxvk-d3d11-contact-family-automated-20260901-v2\family-build.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$testRunsRoot = Join-Path $workspace 'artifacts\test-runs'
$runRoot = Join-Path $testRunsRoot ('dxvk-family-validator-' + [Guid]::NewGuid().ToString('N'))
$validator = Join-Path $PSScriptRoot 'Assert-DxvkD3D11AssemblyFamilyBuild.ps1'
$sourceManifest = (Resolve-Path -LiteralPath $SourceManifestPath -ErrorAction Stop).Path
$sourceRoot = Split-Path -Parent $sourceManifest

function Write-Json([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 16) + [Environment]::NewLine), $utf8)
}

function Assert-Throws([scriptblock]$Action, [string]$Pattern, [string]$Label) {
    try { & $Action } catch {
        $message = [string]$_.Exception.Message
        if ($message -notmatch $Pattern) { throw "$Label rejected for the wrong reason. Expected /$Pattern/; got: $message" }
        Write-Host "PASS: $Label rejected: $message"
        return
    }
    throw "$Label unexpectedly succeeded."
}

function New-RelocatedClone([string]$Name) {
    $destination = Join-Path $runRoot $Name
    [IO.Directory]::CreateDirectory($destination) | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $sourceRoot) {
        Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse
    }

    $manifestPath = Join-Path $destination 'family-build.json'
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    foreach ($variant in @($manifest.variants)) {
        $identity = [string]$variant.identity
        $variant.specializedAssembly = Join-Path $destination "source\${identity}_replace.asm"
        $variant.specializationManifest = $variant.specializedAssembly + '.specialization.json'
        $variant.replacementBinary = Join-Path $destination "replacement\${identity}_replace.bin"
        $variant.replacementManifest = Join-Path $destination "replacement\${identity}_replace.manifest.json"

        $specialization = Get-Content -Raw -LiteralPath $variant.specializationManifest | ConvertFrom-Json
        $specialization.outputPath = [string]$variant.specializedAssembly
        Write-Json $variant.specializationManifest $specialization
        $variant.specializationManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $variant.specializationManifest).Hash

        $replacement = Get-Content -Raw -LiteralPath $variant.replacementManifest | ConvertFrom-Json
        $replacement.sourcePath = [string]$variant.specializedAssembly
        $replacement.outputPath = [string]$variant.replacementBinary
        Write-Json $variant.replacementManifest $replacement
        $variant.replacementManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $variant.replacementManifest).Hash
    }
    Write-Json $manifestPath $manifest
    return $manifestPath
}

[IO.Directory]::CreateDirectory($runRoot) | Out-Null
try {
    $baseline = New-RelocatedClone 'baseline'
    $result = & $validator -ManifestPath $baseline
    if ($result.VariantCount -ne 5 -or $result.Installed -ne $false -or $result.RuntimeEligible -ne $false) {
        throw 'Relocated baseline validator result is inconsistent.'
    }
    Write-Host 'PASS: relocated, hash-closed five-variant baseline accepted.'

    $extraFileManifest = New-RelocatedClone 'extra-file'
    [IO.File]::WriteAllText((Join-Path (Split-Path -Parent $extraFileManifest) 'unlisted.txt'), 'not in manifest', $utf8)
    Assert-Throws { & $validator -ManifestPath $extraFileManifest } 'contains an unlisted file' 'unlisted payload mutation'

    $binaryHashManifest = New-RelocatedClone 'binary-hash'
    $binaryHash = Get-Content -Raw -LiteralPath $binaryHashManifest | ConvertFrom-Json
    $binaryHash.variants[0].replacementBinarySha256 = ('0' * 64)
    Write-Json $binaryHashManifest $binaryHash
    Assert-Throws { & $validator -ManifestPath $binaryHashManifest } 'Replacement DXBC .* hash mismatch' 'replacement hash mutation'

    $provenanceManifest = New-RelocatedClone 'provenance'
    $provenanceParent = Get-Content -Raw -LiteralPath $provenanceManifest | ConvertFrom-Json
    $first = $provenanceParent.variants[0]
    $provenance = Get-Content -Raw -LiteralPath $first.replacementManifest | ConvertFrom-Json
    $provenance.reviewedFamily.variantId = 'hash-tampered-variant'
    Write-Json $first.replacementManifest $provenance
    $first.replacementManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $first.replacementManifest).Hash
    Write-Json $provenanceManifest $provenanceParent
    Assert-Throws { & $validator -ManifestPath $provenanceManifest } 'Replacement provenance is inconsistent' 'reviewed-family provenance mutation'

    $coverageManifest = New-RelocatedClone 'coverage'
    $coverage = Get-Content -Raw -LiteralPath $coverageManifest | ConvertFrom-Json
    $coverage.variants = @($coverage.variants | Select-Object -Skip 1)
    $coverage.targetCount = 4
    Write-Json $coverageManifest $coverage
    Assert-Throws { & $validator -ManifestPath $coverageManifest } 'target count does not exactly match' 'incomplete catalog coverage mutation'

    Write-Host 'PASS: independent family-build validator mutation regressions passed.'
} finally {
    $resolvedRunRoot = [IO.Path]::GetFullPath($runRoot)
    $resolvedTestRuns = [IO.Path]::GetFullPath($testRunsRoot).TrimEnd('\')
    if ($resolvedRunRoot.StartsWith($resolvedTestRuns + '\', [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedRunRoot).StartsWith('dxvk-family-validator-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedRunRoot -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        throw "Refusing to clean unexpected validator test path: $resolvedRunRoot"
    }
}
