[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $PSScriptRoot 'Build-DxvkD3D11ShaderReplacement.ps1'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$work = Join-Path $tempRoot ('ue4fx-hlsl-build-test-' + [guid]::NewGuid().ToString('N'))
$output = Join-Path $work 'output'
$fxc = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'

function Get-MigotoFnv1Hash([string]$Path) {
    Add-Type -AssemblyName System.Numerics
    [System.Numerics.BigInteger]$value = 0
    [System.Numerics.BigInteger]$prime = 1099511628211
    [System.Numerics.BigInteger]$mask = [System.Numerics.BigInteger]::Parse('18446744073709551615')
    foreach ($byte in [IO.File]::ReadAllBytes($Path)) {
        $value = ((($value * $prime) -band $mask) -bxor [System.Numerics.BigInteger]$byte)
    }
    return ('{0:x16}' -f [uint64]$value)
}

function Write-ExactCatalogFixture([string]$Path, [string]$Hash) {
    $upper = $Hash.ToUpperInvariant()
    $catalog = [ordered]@{
        schemaVersion = 1
        kind = 'shader-family-catalog'
        id = 'replacement-builder-fixture'
        displayName = 'Replacement builder fixture'
        provenance = [ordered]@{ evidence = @([ordered]@{ kind='test-fixture'; label='Generated local test fixture' }) }
        families = @([ordered]@{
            id = 'fixture-pixel-family'
            logicalName = 'FixturePixelFamily'
            implementations = @([ordered]@{
                id = 'fixture-d3d11-pixel-family'
                adapter = 'TestFixture'
                api = 'D3D11'
                bytecodeFormat = 'DXBC'
                stage = 'ps'
                shaderModels = @('ps_5_0')
                identityModel = '3dmigoto-dxbc-fnv1-v1'
                variants = @([ordered]@{
                    id = "hash-$($upper.ToLowerInvariant())"
                    identity = [ordered]@{ canonicalShaderHash = $upper }
                    targets = @([ordered]@{ versionGroup='fixture'; shaderHash=$upper })
                })
            })
        })
    }
    [IO.File]::WriteAllText($Path, (($catalog | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

try {
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $originalSource = Join-Path $work 'original.hlsl'
    $originalBinary = Join-Path $work 'original.bin'
    [IO.File]::WriteAllText(
        $originalSource,
        "float4 main(float4 position : SV_Position) : SV_Target0 { return float4(0.25, 0.5, 0.75, 1.0); }`r`n",
        [Text.UTF8Encoding]::new($false))
    $fxcMessages = & $fxc /nologo /T ps_5_0 /E main /Fo $originalBinary $originalSource 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Original fixture compilation failed: $fxcMessages" }

    $identity = (Get-MigotoFnv1Hash $originalBinary) + '-ps'
    $source = Join-Path $work ($identity + '_replace.hlsl')
    [IO.File]::WriteAllText(
        $source,
        "float4 main(float4 position : SV_Position) : SV_Target0 { return float4(0.75, 0.5, 0.25, 1.0); }`r`n",
        [Text.UTF8Encoding]::new($false))
    $checkerBuild = & (Join-Path $PSScriptRoot 'Build-DxbcCompatibilityChecker.ps1') -OutputDirectory (Join-Path $work 'checker')
    $checker = [string]$checkerBuild.Executable
    $familyCatalog = Join-Path $work 'family-catalog.json'
    Write-ExactCatalogFixture $familyCatalog ($identity.Substring(0, 16))

    & $buildScript -SourcePath $source -OutputDirectory $output -OriginalBytecode $originalBinary -CompatibilityCheckerPath $checker -FamilyCatalogPath $familyCatalog
    if ($LASTEXITCODE -ne 0) {
        throw "Replacement build script failed (exit code $LASTEXITCODE)"
    }

    $binary = Join-Path $output ($identity + '_replace.bin')
    $manifestPath = Join-Path $output ($identity + '_replace.manifest.json')
    if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
        throw 'Expected compiled replacement was not created.'
    }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'Expected replacement manifest was not created.'
    }

    $bytes = [IO.File]::ReadAllBytes($binary)
    if ([Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'DXBC') {
        throw 'Replacement does not begin with DXBC magic.'
    }

    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    if ($manifest.identity -ne $identity -or
        $manifest.profile -ne 'ps_5_0' -or
        $manifest.originalIdentityVerified -ne $true -or
        $manifest.compatibilityStatus -ne 'passed-reflection-contract' -or
        $manifest.reviewedFamily.familyId -ne 'fixture-pixel-family' -or
        $manifest.reviewedFamily.identityModel -ne '3dmigoto-dxbc-fnv1-v1' -or
        $manifest.familyCatalogSha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $familyCatalog).Hash.ToLowerInvariant() -or
        $manifest.runtimeEligible -ne $false -or
        $manifest.installed -ne $false) {
        throw 'Replacement manifest does not preserve verified identity, compatibility, profile, and offline state.'
    }
    if ($manifest.outputSha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $binary).Hash.ToLowerInvariant()) {
        throw 'Replacement manifest output hash is incorrect.'
    }

    $badIdentitySource = Join-Path $work '0000000000000000-ps_replace.hlsl'
    [IO.File]::WriteAllText($badIdentitySource, [IO.File]::ReadAllText($source), [Text.UTF8Encoding]::new($false))
    $badIdentityRejected = $false
    try {
        & $buildScript -SourcePath $badIdentitySource -OutputDirectory (Join-Path $work 'bad-identity-output') -OriginalBytecode $originalBinary -CompatibilityCheckerPath $checker
    }
    catch {
        $badIdentityRejected = $_.Exception.Message -match 'does not match original bytecode hash'
    }
    if (-not $badIdentityRejected) { throw 'Mismatched source identity was not rejected.' }

    $badContractRoot = Join-Path $work 'bad-contract-source'
    New-Item -ItemType Directory -Force -Path $badContractRoot | Out-Null
    $badContractSource = Join-Path $badContractRoot ($identity + '_replace.hlsl')
    [IO.File]::WriteAllText(
        $badContractSource,
        "float4 main(float2 uv : TEXCOORD0) : SV_Target0 { return float4(uv, 0.0, 1.0); }`r`n",
        [Text.UTF8Encoding]::new($false))
    $badContractOutput = Join-Path $work 'bad-contract-output'
    $badContractRejected = $false
    try {
        & $buildScript -SourcePath $badContractSource -OutputDirectory $badContractOutput -OriginalBytecode $originalBinary -CompatibilityCheckerPath $checker
    }
    catch {
        $badContractRejected = $_.Exception.Message -match 'incompatible with original DXBC'
    }
    if (-not $badContractRejected) { throw 'Incompatible compiled signature was not rejected.' }
    if (Test-Path -LiteralPath (Join-Path $badContractOutput ($identity + '_replace.bin')) -PathType Leaf) {
        throw 'Incompatible replacement was published despite rejection.'
    }

    $unrelatedCatalog = Join-Path $work 'unrelated-family-catalog.json'
    Write-ExactCatalogFixture $unrelatedCatalog '1111111111111111'
    $unreviewedOutput = Join-Path $work 'unreviewed-output'
    $unreviewedRejected = $false
    try {
        & $buildScript -SourcePath $source -OutputDirectory $unreviewedOutput -OriginalBytecode $originalBinary -CompatibilityCheckerPath $checker -FamilyCatalogPath $unrelatedCatalog
    }
    catch {
        $unreviewedRejected = $_.Exception.Message -match 'No reviewed catalog target matches'
    }
    if (-not $unreviewedRejected) { throw 'Unreviewed shader identity was not rejected by the optional family gate.' }
    if (Test-Path -LiteralPath (Join-Path $unreviewedOutput ($identity + '_replace.bin')) -PathType Leaf) {
        throw 'Unreviewed replacement was published despite rejection.'
    }

    Write-Host 'PASS: offline HLSL adapter publishes only identity-verified, contract-compatible SM5 DXBC and optionally requires a reviewed family.'
}
finally {
    if (Test-Path -LiteralPath $work) {
        $resolvedWork = [IO.Path]::GetFullPath($work)
        $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
        $leaf = Split-Path -Leaf $resolvedWork
        if (-not $resolvedWork.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -or
            -not $leaf.StartsWith('ue4fx-hlsl-build-test-', [StringComparison]::Ordinal)) {
            throw "Refusing to remove unexpected test path: $resolvedWork"
        }
        Remove-Item -LiteralPath $resolvedWork -Recurse -Force
    }
}
