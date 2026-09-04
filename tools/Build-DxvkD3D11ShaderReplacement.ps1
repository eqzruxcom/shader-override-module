[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourcePath,
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\dxvk-d3d11-compiled-replacements'),
    [string]$EntryPoint = 'main',
    [string]$CompilerPath,
    [string[]]$IncludeDirectory = @(),
    [string]$OriginalBytecode,
    [string]$CompatibilityCheckerPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\dxbc-compatibility-tool\DxbcCompatibilityCheck.exe'),
    [string]$FamilyCatalogPath
)

$ErrorActionPreference = 'Stop'

function Resolve-FxcPath {
    param([string]$RequestedPath)

    if ($RequestedPath) {
        $resolved = (Resolve-Path -LiteralPath $RequestedPath -ErrorAction Stop).Path
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            throw "FXC compiler was not found: $RequestedPath"
        }
        return $resolved
    }

    $pathCommand = Get-Command fxc.exe -ErrorAction SilentlyContinue
    if ($pathCommand) {
        return $pathCommand.Source
    }

    $kitsBin = 'C:\Program Files (x86)\Windows Kits\10\bin'
    if (Test-Path -LiteralPath $kitsBin -PathType Container) {
        $candidates = @(Get-ChildItem -LiteralPath $kitsBin -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'x64\fxc.exe' } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Sort-Object { [version](Split-Path (Split-Path $_ -Parent) -Parent | Split-Path -Leaf) } -Descending)
        if ($candidates) {
            return $candidates[0]
        }
    }

    throw 'FXC was not found on PATH or in the Windows 10 SDK. Pass -CompilerPath explicitly.'
}

function Get-MigotoFnv1Hash {
    param([Parameter(Mandatory)][string]$Path)
    Add-Type -AssemblyName System.Numerics
    [System.Numerics.BigInteger]$hashValue = 0
    [System.Numerics.BigInteger]$prime = 1099511628211
    [System.Numerics.BigInteger]$mask = [System.Numerics.BigInteger]::Parse('18446744073709551615')
    foreach ($byte in [IO.File]::ReadAllBytes($Path)) {
        $hashValue = ((($hashValue * $prime) -band $mask) -bxor [System.Numerics.BigInteger]$byte)
    }
    return ('{0:x16}' -f [uint64]$hashValue)
}

$resolvedSource = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $resolvedSource -PathType Leaf)) {
    throw "HLSL source was not found: $SourcePath"
}

$sourceName = Split-Path -Leaf $resolvedSource
$match = [regex]::Match(
    $sourceName,
    '^(?<hash>[0-9A-Fa-f]{16})-(?<stage>vs|hs|ds|gs|ps|cs)_replace\.(?<extension>hlsl|txt)$',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase)
if (-not $match.Success) {
    throw "Source name must be <16-hex-hash>-<vs|hs|ds|gs|ps|cs>_replace.hlsl (or .txt): $sourceName"
}

$hash = $match.Groups['hash'].Value.ToLowerInvariant()
$stage = $match.Groups['stage'].Value.ToLowerInvariant()
$profiles = @{
    vs = 'vs_5_0'
    hs = 'hs_5_0'
    ds = 'ds_5_0'
    gs = 'gs_5_0'
    ps = 'ps_5_0'
    cs = 'cs_5_0'
}
$profile = $profiles[$stage]
$identity = "$hash-$stage"
$resolvedFamilyCatalog = $null
$familyCatalogSha256 = $null
$reviewedFamily = $null
if ($FamilyCatalogPath) {
    $resolvedFamilyCatalog = (Resolve-Path -LiteralPath $FamilyCatalogPath -ErrorAction Stop).Path
    $reviewedFamily = & (Join-Path $PSScriptRoot 'Resolve-ShaderFamilyCatalogTarget.ps1') `
        -CatalogPath $resolvedFamilyCatalog -Stage $stage -ShaderHash $hash
    if ($reviewedFamily.api -ne 'D3D11' -or $reviewedFamily.bytecodeFormat -ne 'DXBC') {
        throw "Reviewed family target is not a D3D11/DXBC implementation: $($reviewedFamily.implementationId)"
    }
    if ($profile -notin @($reviewedFamily.shaderModels)) {
        throw "Reviewed family target does not allow shader model ${profile}: $($reviewedFamily.implementationId)"
    }
    $familyCatalogSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedFamilyCatalog).Hash.ToLowerInvariant()
}
$fxc = Resolve-FxcPath $CompilerPath
$resolvedOriginal = $null
$resolvedChecker = $null
if ($OriginalBytecode) {
    $resolvedOriginal = (Resolve-Path -LiteralPath $OriginalBytecode -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolvedOriginal -PathType Leaf)) {
        throw "Original shader bytecode was not found: $OriginalBytecode"
    }
    $actualHash = Get-MigotoFnv1Hash $resolvedOriginal
    if ($actualHash -ne $hash) {
        throw "Source identity $hash does not match original bytecode hash $actualHash."
    }
    $resolvedChecker = (Resolve-Path -LiteralPath $CompatibilityCheckerPath -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolvedChecker -PathType Leaf)) {
        throw "DXBC compatibility checker was not found: $CompatibilityCheckerPath"
    }
}

$resolvedOutput = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null
$outputPath = Join-Path $resolvedOutput ($identity + '_replace.bin')
$manifestPath = Join-Path $resolvedOutput ($identity + '_replace.manifest.json')
$temporaryPath = Join-Path $resolvedOutput ('.' + $identity + '.' + [guid]::NewGuid().ToString('N') + '.tmp')

$includePaths = @((Split-Path -Parent $resolvedSource)) + $IncludeDirectory
$arguments = @('/nologo', '/T', $profile, '/E', $EntryPoint, '/Fo', $temporaryPath)
foreach ($includePath in $includePaths | Select-Object -Unique) {
    $resolvedInclude = [IO.Path]::GetFullPath($includePath)
    if (-not (Test-Path -LiteralPath $resolvedInclude -PathType Container)) {
        throw "HLSL include directory was not found: $includePath"
    }
    $arguments += @('/I', $resolvedInclude)
}
$arguments += $resolvedSource

try {
    $compilerMessages = & $fxc @arguments 2>&1
    $compilerExitCode = $LASTEXITCODE
    if ($compilerExitCode -ne 0) {
        throw "FXC failed for $sourceName (exit code $compilerExitCode): $($compilerMessages -join ' ')"
    }
    if (-not (Test-Path -LiteralPath $temporaryPath -PathType Leaf)) {
        throw "FXC reported success but did not produce $temporaryPath"
    }

    $bytes = [IO.File]::ReadAllBytes($temporaryPath)
    if ($bytes.Length -lt 4 -or
        $bytes[0] -ne [byte][char]'D' -or
        $bytes[1] -ne [byte][char]'X' -or
        $bytes[2] -ne [byte][char]'B' -or
        $bytes[3] -ne [byte][char]'C') {
        throw 'Compiled output is not a DXBC container.'
    }

    $compatibilityStatus = 'not-checked-no-original-bytecode'
    if ($resolvedOriginal) {
        $compatibilityMessages = & $resolvedChecker $resolvedOriginal $temporaryPath 2>&1
        $compatibilityExitCode = $LASTEXITCODE
        if ($compatibilityExitCode -ne 0) {
            throw "Compiled replacement is incompatible with original DXBC: $($compatibilityMessages -join ' ')"
        }
        $compatibilityText=$compatibilityMessages -join ' '
        $compatibilityStatus = if($compatibilityText -match 'disassembled binding declarations'){'passed-declaration-contract-rdef-unavailable'}else{'passed-reflection-contract'}
    }

    Move-Item -LiteralPath $temporaryPath -Destination $outputPath -Force

    $compilerInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($fxc)
    $manifest = [ordered]@{
        schemaVersion = 1
        backend = 'dxvk-d3d11'
        identity = $identity
        hash = $hash
        stage = $stage
        profile = $profile
        entryPoint = $EntryPoint
        sourcePath = $resolvedSource
        sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedSource).Hash.ToLowerInvariant()
        originalPath = $resolvedOriginal
        originalSha256 = if ($resolvedOriginal) { (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedOriginal).Hash.ToLowerInvariant() } else { $null }
        originalIdentityVerified = [bool]$resolvedOriginal
        compatibilityStatus = $compatibilityStatus
        familyCatalogPath = $resolvedFamilyCatalog
        familyCatalogSha256 = $familyCatalogSha256
        reviewedFamily = if ($reviewedFamily) { [ordered]@{
            catalogId = $reviewedFamily.catalogId
            familyId = $reviewedFamily.familyId
            logicalName = $reviewedFamily.logicalName
            implementationId = $reviewedFamily.implementationId
            adapter = $reviewedFamily.adapter
            identityModel = $reviewedFamily.identityModel
            variantId = $reviewedFamily.variantId
            versionGroup = $reviewedFamily.versionGroup
        } } else { $null }
        outputPath = $outputPath
        outputSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash.ToLowerInvariant()
        compilerPath = $fxc
        compilerVersion = $compilerInfo.FileVersion
        generatedUtc = [DateTime]::UtcNow.ToString('o')
        runtimeEligible = $false
        installed = $false
    }
    [IO.File]::WriteAllText(
        $manifestPath,
        (($manifest | ConvertTo-Json -Depth 4) + [Environment]::NewLine),
        [Text.UTF8Encoding]::new($false))

    Write-Host "PASS: compiled $sourceName as $profile."
    Write-Host "DXBC: $outputPath"
    Write-Host "Manifest: $manifestPath"
}
finally {
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}
