[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$OriginalBytecode,
    [Parameter(Mandatory)][string]$FamilyCatalogPath,
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\dxvk-d3d11-assembled-replacements'),
    [string]$AssemblerPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\shader-assembler-build\bin\cmd_Decompiler.exe'),
    [string]$CompatibilityCheckerPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\dxbc-compatibility-tool\DxbcCompatibilityCheck.exe')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RequiredFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Label)
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "$Label was not found: $Path"
    }
    return $resolved
}

function Get-MigotoFnv1Hash {
    param([Parameter(Mandatory)][string]$Path)
    Add-Type -AssemblyName System.Numerics
    [System.Numerics.BigInteger]$value = 0
    [System.Numerics.BigInteger]$prime = 1099511628211
    [System.Numerics.BigInteger]$mask = [System.Numerics.BigInteger]::Parse('18446744073709551615')
    foreach ($byte in [IO.File]::ReadAllBytes($Path)) {
        $value = ((($value * $prime) -band $mask) -bxor [System.Numerics.BigInteger]$byte)
    }
    return ('{0:x16}' -f [uint64]$value)
}

function Assert-Dxbc {
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 4 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'DXBC') {
        throw "Assembled output is not a DXBC container: $Path"
    }
}

function Get-CompatibilityStatus {
    param(
        [Parameter(Mandatory)][string]$Checker,
        [Parameter(Mandatory)][string]$Original,
        [Parameter(Mandatory)][string]$Replacement
    )
    $messages = @(& $Checker $Original $Replacement 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Assembled replacement is incompatible with original DXBC: $($messages -join ' ')"
    }
    $text = $messages -join ' '
    if ($text -match 'disassembled binding declarations') {
        return 'passed-declaration-contract-rdef-unavailable'
    }
    return 'passed-reflection-contract'
}

$source = Resolve-RequiredFile $SourcePath 'Assembly source'
$original = Resolve-RequiredFile $OriginalBytecode 'Original shader bytecode'
$catalog = Resolve-RequiredFile $FamilyCatalogPath 'Reviewed shader-family catalog'
$assembler = Resolve-RequiredFile $AssemblerPath 'Pinned shader assembler'
$checker = Resolve-RequiredFile $CompatibilityCheckerPath 'DXBC compatibility checker'

$sourceName = Split-Path -Leaf $source
$nameMatch = [regex]::Match(
    $sourceName,
    '^(?<hash>[0-9A-Fa-f]{16})-(?<stage>vs|hs|ds|gs|ps|cs)(?:_replace)?\.(?<extension>asm|txt)$',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase)
if (-not $nameMatch.Success) {
    throw "Source name must be <16-hex-hash>-<vs|hs|ds|gs|ps|cs>[_replace].asm (or .txt): $sourceName"
}

$hash = $nameMatch.Groups['hash'].Value.ToLowerInvariant()
$stage = $nameMatch.Groups['stage'].Value.ToLowerInvariant()
$identity = "$hash-$stage"
$profiles = @{ vs='vs_5_0'; hs='hs_5_0'; ds='ds_5_0'; gs='gs_5_0'; ps='ps_5_0'; cs='cs_5_0' }
$profile = $profiles[$stage]
$actualHash = Get-MigotoFnv1Hash $original
if ($actualHash -ne $hash) {
    throw "Source identity $hash does not match original bytecode hash $actualHash."
}

$reviewedFamily = & (Join-Path $PSScriptRoot 'Resolve-ShaderFamilyCatalogTarget.ps1') `
    -CatalogPath $catalog -Stage $stage -ShaderHash $hash
if ($reviewedFamily.api -ne 'D3D11' -or $reviewedFamily.bytecodeFormat -ne 'DXBC') {
    throw "Reviewed family target is not a D3D11/DXBC implementation: $($reviewedFamily.implementationId)"
}
if ($reviewedFamily.stage -ne $stage -or $profile -notin @($reviewedFamily.shaderModels)) {
    throw "Reviewed family target does not allow ${profile}: $($reviewedFamily.implementationId)"
}
if ($reviewedFamily.identityModel -ne '3dmigoto-dxbc-fnv1-v1') {
    throw "Reviewed family target uses an unsupported identity model: $($reviewedFamily.identityModel)"
}

$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$outputPath = Join-Path $outputRoot ($identity + '_replace.bin')
$manifestPath = Join-Path $outputRoot ($identity + '_replace.manifest.json')
$token = [guid]::NewGuid().ToString('N')
$temporaryAssembly = Join-Path $outputRoot ('.' + $identity + '.' + $token + '.asm')
$temporaryBytecode = [IO.Path]::ChangeExtension($temporaryAssembly, '.shdr')
$temporaryManifest = Join-Path $outputRoot ('.' + $identity + '.' + $token + '.manifest.tmp')

$sourceSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash.ToLowerInvariant()
$originalSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $original).Hash.ToLowerInvariant()
$catalogSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $catalog).Hash.ToLowerInvariant()
$assemblerSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $assembler).Hash.ToLowerInvariant()
$checkerSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $checker).Hash.ToLowerInvariant()
$utf8 = [Text.UTF8Encoding]::new($false)

try {
    Copy-Item -LiteralPath $source -Destination $temporaryAssembly
    $assemblerMessages = @(& $assembler -a --copy-reflection $original $temporaryAssembly 2>&1)
    $assemblerExitCode = $LASTEXITCODE
    if ($assemblerExitCode -ne 0) {
        throw "Shader assembly failed for $sourceName (exit code $assemblerExitCode): $($assemblerMessages -join ' ')"
    }
    if (-not (Test-Path -LiteralPath $temporaryBytecode -PathType Leaf)) {
        throw "Shader assembler reported success but did not produce: $temporaryBytecode"
    }
    Assert-Dxbc $temporaryBytecode
    $compatibilityStatus = Get-CompatibilityStatus -Checker $checker -Original $original -Replacement $temporaryBytecode
    $outputSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $temporaryBytecode).Hash.ToLowerInvariant()

    $assemblerInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($assembler)
    $manifest = [ordered]@{
        schemaVersion = 1
        backend = 'dxvk-d3d11'
        identity = $identity
        hash = $hash
        stage = $stage
        profile = $profile
        sourceFormat = 'd3d-assembly'
        sourcePath = $source
        sourceSha256 = $sourceSha
        originalPath = $original
        originalSha256 = $originalSha
        originalIdentityVerified = $true
        compatibilityStatus = $compatibilityStatus
        familyCatalogPath = $catalog
        familyCatalogSha256 = $catalogSha
        reviewedFamily = [ordered]@{
            catalogId = $reviewedFamily.catalogId
            familyId = $reviewedFamily.familyId
            logicalName = $reviewedFamily.logicalName
            implementationId = $reviewedFamily.implementationId
            adapter = $reviewedFamily.adapter
            identityModel = $reviewedFamily.identityModel
            variantId = $reviewedFamily.variantId
            versionGroup = $reviewedFamily.versionGroup
        }
        outputPath = $outputPath
        outputSha256 = $outputSha
        assemblerPath = $assembler
        assemblerSha256 = $assemblerSha
        assemblerVersion = $assemblerInfo.FileVersion
        compatibilityCheckerPath = $checker
        compatibilityCheckerSha256 = $checkerSha
        generatedUtc = [DateTime]::UtcNow.ToString('o')
        runtimeEligible = $false
        installed = $false
    }

    $outputExists = Test-Path -LiteralPath $outputPath -PathType Leaf
    $manifestExists = Test-Path -LiteralPath $manifestPath -PathType Leaf
    if ($outputExists -or $manifestExists) {
        if (-not ($outputExists -and $manifestExists)) {
            throw "Refusing to overwrite incomplete prior evidence for ${identity}: binary=$outputExists manifest=$manifestExists"
        }
        $existing = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        $existingOutputSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash.ToLowerInvariant()
        $sameEvidence =
            $existing.identity -eq $identity -and
            $existing.sourceSha256 -eq $sourceSha -and
            $existing.originalSha256 -eq $originalSha -and
            $existing.familyCatalogSha256 -eq $catalogSha -and
            $existing.assemblerSha256 -eq $assemblerSha -and
            $existing.compatibilityCheckerSha256 -eq $checkerSha -and
            $existing.compatibilityStatus -eq $compatibilityStatus -and
            $existing.outputSha256 -eq $existingOutputSha -and
            $existingOutputSha -eq $outputSha -and
            $existing.runtimeEligible -eq $false -and
            $existing.installed -eq $false
        if (-not $sameEvidence) {
            throw "Refusing to overwrite mismatched prior replacement evidence for $identity. Use a new output directory."
        }
        Write-Host "PASS: existing replacement evidence is byte-for-byte identical for $identity."
        Write-Host "DXBC: $outputPath"
        Write-Host "Manifest: $manifestPath"
        return
    }

    [IO.File]::WriteAllText($temporaryManifest, (($manifest | ConvertTo-Json -Depth 6) + [Environment]::NewLine), $utf8)
    Move-Item -LiteralPath $temporaryBytecode -Destination $outputPath
    try {
        Move-Item -LiteralPath $temporaryManifest -Destination $manifestPath
    }
    catch {
        if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
            Remove-Item -LiteralPath $outputPath -Force
        }
        throw
    }

    Write-Host "PASS: assembled $sourceName as $profile with reviewed identity and compatible DXBC bindings."
    Write-Host "DXBC: $outputPath"
    Write-Host "Manifest: $manifestPath"
}
finally {
    foreach ($temporary in @($temporaryAssembly, $temporaryBytecode, $temporaryManifest)) {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}
