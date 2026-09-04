[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$builder = Join-Path $PSScriptRoot 'Build-DxvkD3D11AssemblyReplacement.ps1'
$assembler = Join-Path $root 'artifacts\shader-assembler-build\bin\cmd_Decompiler.exe'
$checker = Join-Path $root 'artifacts\dxbc-compatibility-tool\DxbcCompatibilityCheck.exe'
$fxc = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$work = Join-Path $tempRoot ('ue4fx-dxvk-assembly-build-test-' + [guid]::NewGuid().ToString('N'))
$utf8 = [Text.UTF8Encoding]::new($false)

foreach ($required in @($builder, $assembler, $checker, $fxc)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required test input is missing: $required" }
}

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

function Write-Catalog([string]$Path, [string]$Hash) {
    $upper = $Hash.ToUpperInvariant()
    $catalog = [ordered]@{
        schemaVersion = 1
        kind = 'shader-family-catalog'
        id = 'assembly-replacement-builder-fixture'
        displayName = 'Assembly replacement builder fixture'
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
    [IO.File]::WriteAllText($Path, (($catalog | ConvertTo-Json -Depth 12) + [Environment]::NewLine), $utf8)
}

function Assert-Rejected([scriptblock]$Action, [string]$Expected, [string]$Label) {
    $rejected = $false
    try { & $Action }
    catch {
        $rejected = $_.Exception.Message -match [regex]::Escape($Expected)
        if (-not $rejected) { throw "Unexpected rejection for ${Label}: $($_.Exception.Message)" }
    }
    if (-not $rejected) { throw "Expected rejection was not raised: $Label" }
    Write-Host "PASS: rejected $Label."
}

try {
    [IO.Directory]::CreateDirectory($work) | Out-Null
    $hlsl = Join-Path $work 'original.hlsl'
    $original = Join-Path $work 'original.bin'
    [IO.File]::WriteAllText($hlsl, "float4 main(float4 p : SV_Position) : SV_Target0 { return float4(0.25, 0.5, 0.75, 1.0); }`r`n", $utf8)
    $fxcMessages = @(& $fxc /nologo /T ps_5_0 /E main /Fo $original $hlsl 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Fixture compilation failed: $($fxcMessages -join ' ')" }

    Push-Location $work
    try {
        $disassemblyMessages = @(& $assembler -d $original 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Fixture disassembly failed: $($disassemblyMessages -join ' ')" }
    }
    finally { Pop-Location }
    $disassembly = [IO.Path]::ChangeExtension($original, '.asm')
    if (-not (Test-Path -LiteralPath $disassembly -PathType Leaf)) { throw 'Fixture disassembly was not produced.' }

    $hash = Get-MigotoFnv1Hash $original
    $identity = "$hash-ps"
    $source = Join-Path $work ($identity + '_replace.asm')
    Copy-Item -LiteralPath $disassembly -Destination $source
    $catalog = Join-Path $work 'family-catalog.json'
    Write-Catalog $catalog $hash
    $output = Join-Path $work 'output'

    & $builder -SourcePath $source -OriginalBytecode $original -FamilyCatalogPath $catalog -OutputDirectory $output -AssemblerPath $assembler -CompatibilityCheckerPath $checker
    $binary = Join-Path $output ($identity + '_replace.bin')
    $manifestPath = Join-Path $output ($identity + '_replace.manifest.json')
    if (-not (Test-Path -LiteralPath $binary -PathType Leaf) -or -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'Assembly builder did not publish its binary and manifest.'
    }
    $bytes = [IO.File]::ReadAllBytes($binary)
    if ($bytes.Length -lt 4 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'DXBC') { throw 'Published fixture is not DXBC.' }
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    if ($manifest.identity -ne $identity -or $manifest.sourceFormat -ne 'd3d-assembly' -or
        $manifest.originalIdentityVerified -ne $true -or
        $manifest.compatibilityStatus -notin @('passed-reflection-contract','passed-declaration-contract-rdef-unavailable') -or
        $manifest.reviewedFamily.familyId -ne 'fixture-pixel-family' -or
        $manifest.reviewedFamily.identityModel -ne '3dmigoto-dxbc-fnv1-v1' -or
        $manifest.outputSha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $binary).Hash.ToLowerInvariant() -or
        $manifest.runtimeEligible -ne $false -or $manifest.installed -ne $false) {
        throw 'Assembly replacement manifest does not preserve the required offline evidence.'
    }

    & $builder -SourcePath $source -OriginalBytecode $original -FamilyCatalogPath $catalog -OutputDirectory $output -AssemblerPath $assembler -CompatibilityCheckerPath $checker

    $badIdentity = Join-Path $work '0000000000000000-ps_replace.asm'
    Copy-Item -LiteralPath $source -Destination $badIdentity
    Assert-Rejected { & $builder -SourcePath $badIdentity -OriginalBytecode $original -FamilyCatalogPath $catalog -OutputDirectory (Join-Path $work 'bad-id-output') -AssemblerPath $assembler -CompatibilityCheckerPath $checker } 'does not match original bytecode hash' 'mismatched 3Dmigoto identity'

    $unrelatedCatalog = Join-Path $work 'unrelated-catalog.json'
    Write-Catalog $unrelatedCatalog '1111111111111111'
    Assert-Rejected { & $builder -SourcePath $source -OriginalBytecode $original -FamilyCatalogPath $unrelatedCatalog -OutputDirectory (Join-Path $work 'unreviewed-output') -AssemblerPath $assembler -CompatibilityCheckerPath $checker } 'No reviewed catalog target matches' 'unreviewed shader family'

    $badContractRoot = Join-Path $work 'bad-contract'
    [IO.Directory]::CreateDirectory($badContractRoot) | Out-Null
    $badContract = Join-Path $badContractRoot ($identity + '_replace.asm')
    $badLines = [Collections.Generic.List[string]]::new()
    $inserted = $false
    foreach ($line in [IO.File]::ReadAllLines($source)) {
        $badLines.Add($line)
        if (-not $inserted -and $line -match '^dcl_globalFlags') {
            $badLines.Add('dcl_resource_texture2d (float,float,float,float) t0')
            $inserted = $true
        }
    }
    if (-not $inserted) { throw 'Could not inject the fixture contract mismatch.' }
    [IO.File]::WriteAllLines($badContract, $badLines, $utf8)
    Assert-Rejected { & $builder -SourcePath $badContract -OriginalBytecode $original -FamilyCatalogPath $catalog -OutputDirectory (Join-Path $work 'bad-contract-output') -AssemblerPath $assembler -CompatibilityCheckerPath $checker } 'incompatible with original DXBC' 'changed executable resource contract'

    Add-Content -LiteralPath $source -Value '// evidence mismatch probe' -Encoding utf8
    Assert-Rejected { & $builder -SourcePath $source -OriginalBytecode $original -FamilyCatalogPath $catalog -OutputDirectory $output -AssemblerPath $assembler -CompatibilityCheckerPath $checker } 'Refusing to overwrite mismatched prior replacement evidence' 'mismatched prior evidence overwrite'

    Write-Host 'PASS: DXVK assembly adapter publishes only identity-verified, reviewed-family, contract-compatible DXBC and preserves prior evidence.'
}
finally {
    if (Test-Path -LiteralPath $work) {
        $resolvedWork = [IO.Path]::GetFullPath($work)
        $leaf = Split-Path -Leaf $resolvedWork
        if (-not $resolvedWork.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
            -not $leaf.StartsWith('ue4fx-dxvk-assembly-build-test-', [StringComparison]::Ordinal)) {
            throw "Refusing to remove unexpected test path: $resolvedWork"
        }
        Remove-Item -LiteralPath $resolvedWork -Recurse -Force
    }
}
