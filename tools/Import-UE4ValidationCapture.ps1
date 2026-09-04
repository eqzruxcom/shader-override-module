[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CaptureDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')][string]$CaptureId,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputDirectory,
    [string]$FxcPath,
    [ValidateRange(0,100)][int]$NearMatchLimitPerDescriptor = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$captureRoot = (Resolve-Path -LiteralPath $CaptureDirectory).Path.TrimEnd('\')
$shaderCache = if ((Split-Path -Leaf $captureRoot) -ieq 'ShaderCache') { $captureRoot } else { Join-Path $captureRoot 'ShaderCache' }
if (-not (Test-Path -LiteralPath $shaderCache -PathType Container)) { throw "ShaderCache directory is missing: $shaderCache" }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectPath "artifacts\validation-captures\$CaptureId"
}
$outputFull = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $projectPath 'artifacts\validation-captures')).TrimEnd('\')
if (-not $outputFull.StartsWith($allowedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Imported capture output must remain below artifacts/validation-captures.'
}
if ([string]::IsNullOrWhiteSpace($FxcPath)) {
    $FxcPath = Get-ChildItem -LiteralPath 'C:\Program Files (x86)\Windows Kits\10\bin' -Filter fxc.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object FullName -match '\\x64\\fxc\.exe$' | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if ([string]::IsNullOrWhiteSpace($FxcPath) -or -not (Test-Path -LiteralPath $FxcPath -PathType Leaf)) { throw 'An x64 Windows SDK fxc.exe is required.' }

$captured = @(Get-ChildItem -LiteralPath $shaderCache -Filter '*.bin' -File | Where-Object Name -match '^(?<hash>[0-9A-Fa-f]{16})-(?<stage>ps|vs|cs|gs|hs|ds)\.bin$' | Sort-Object Name)
if (-not $captured.Count) { throw 'No 3Dmigoto 16-hex SM5 shader binaries were found.' }
if (Test-Path -LiteralPath $outputFull) { Remove-Item -LiteralPath $outputFull -Recurse -Force }
$binaryRoot = Join-Path $outputFull 'dxbc'
$assemblyRoot = Join-Path $outputFull 'assembly'
[IO.Directory]::CreateDirectory($binaryRoot) | Out-Null
[IO.Directory]::CreateDirectory($assemblyRoot) | Out-Null

$records = foreach ($file in $captured) {
    $baseName = [IO.Path]::GetFileNameWithoutExtension($file.Name).ToLowerInvariant()
    $binaryOut = Join-Path $binaryRoot "$baseName.bin"
    $assemblyOut = Join-Path $assemblyRoot "$baseName.asm"
    Copy-Item -LiteralPath $file.FullName -Destination $binaryOut
    $compilerOutput = & $FxcPath /nologo /dumpbin /Fc $assemblyOut $binaryOut 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $assemblyOut -PathType Leaf)) {
        throw "FXC failed to disassemble $($file.Name): $($compilerOutput -join [Environment]::NewLine)"
    }
    [pscustomobject][ordered]@{
        shader = $baseName
        sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
        binary = "dxbc/$baseName.bin"
        assembly = "assembly/$baseName.asm"
        assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assemblyOut).Hash
    }
}

$matcher = Join-Path $projectPath 'tools\Match-UE4SemanticPasses.ps1'
$matchPath = Join-Path $outputFull 'semantic-matches.json'
& $matcher -ShaderDirectory $assemblyRoot -OutputPath $matchPath -ExcludeReplacementArtifacts -NearMatchLimitPerDescriptor $NearMatchLimitPerDescriptor | Out-Null
$matches = Get-Content -Raw -LiteralPath $matchPath | ConvertFrom-Json
$manifest = [ordered]@{
    schemaVersion = 1
    captureId = $CaptureId
    importedAtUtc = [DateTime]::UtcNow.ToString('o')
    source = $shaderCache
    localResearchOnly = $true
    redistributionAllowed = $false
    fxc = [ordered]@{ path = $FxcPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $FxcPath).Hash }
    capturedShaderCount = $records.Count
    semanticMatchCount = @($matches.matches).Count
    nearMatchCount = @($matches.nearMatches).Count
    semanticReport = 'semantic-matches.json'
    semanticReportSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $matchPath).Hash
    shaders = @($records)
}
$manifestPath = Join-Path $outputFull 'capture-manifest.json'
$manifestJson = ($manifest | ConvertTo-Json -Depth 7) + [Environment]::NewLine
$manifestSchema = Join-Path $projectPath 'src\Engine\UE4\ValidationCapture\capture-manifest.schema.json'
if (-not ($manifestJson | Test-Json -SchemaFile $manifestSchema -ErrorAction Stop)) { throw 'Generated capture manifest failed its schema.' }
[IO.File]::WriteAllText($manifestPath, $manifestJson, [Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'Assert-UE4ValidationManifest.ps1') -Kind Capture -Path $manifestPath -ProjectRoot $projectPath | Out-Null

[pscustomobject]@{
    CaptureId = $CaptureId
    Shaders = $manifest.capturedShaderCount
    SemanticMatches = $manifest.semanticMatchCount
    NearMatches = $manifest.nearMatchCount
    Output = $outputFull
    Result = 'imported-and-scanned'
}
