[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MesonWheel,
    [Parameter(Mandatory)][string]$GlslangArchive,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedMesonSha256,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedGlslangArchiveSha256,
    [string]$InputManifest = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Backends\DxvkD3D11\toolchain-inputs.json'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\toolchains\dxvk-msvc')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $root 'artifacts'))
$resolvedOutput = [IO.Path]::GetFullPath($OutputRoot)
$wheel = [IO.Path]::GetFullPath($MesonWheel)
$glslangArchivePath = [IO.Path]::GetFullPath($GlslangArchive)
$inputManifestPath = [IO.Path]::GetFullPath($InputManifest)

if (-not $resolvedOutput.StartsWith($artifactsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing output outside the workspace artifacts directory: $resolvedOutput"
}
if (-not (Test-Path -LiteralPath $wheel -PathType Leaf) -or [IO.Path]::GetExtension($wheel) -ne '.whl') {
    throw "A local Meson wheel is required: $wheel"
}
if (-not (Test-Path -LiteralPath $glslangArchivePath -PathType Leaf) -or [IO.Path]::GetExtension($glslangArchivePath) -ne '.zip') {
    throw "The local pinned glslang Windows release ZIP is required: $glslangArchivePath"
}
if (-not (Test-Path -LiteralPath $inputManifestPath -PathType Leaf)) {
    throw "The reviewed toolchain input manifest is required: $inputManifestPath"
}

$inputs = Get-Content -Raw -LiteralPath $inputManifestPath | ConvertFrom-Json
if ($inputs.meson.status -ne 'pinned' -or $inputs.meson.sha256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw 'Meson is not fully pinned in the reviewed toolchain input manifest'
}
if ($inputs.glslangValidator.status -ne 'pinned' -or
    $inputs.glslangValidator.archiveSha256 -notmatch '^[0-9a-fA-F]{64}$' -or
    -not $inputs.glslangValidator.archiveUrl) {
    throw 'glslangValidator is not fully pinned to a versioned archive URL and SHA-256 in the reviewed toolchain input manifest'
}
if ($ExpectedMesonSha256.ToLowerInvariant() -ne $inputs.meson.sha256.ToLowerInvariant()) {
    throw 'Expected Meson SHA-256 does not match the reviewed toolchain input manifest'
}
if ($ExpectedGlslangArchiveSha256.ToLowerInvariant() -ne $inputs.glslangValidator.archiveSha256.ToLowerInvariant()) {
    throw 'Expected glslang archive SHA-256 does not match the reviewed toolchain input manifest'
}

$mesonHash = (Get-FileHash -LiteralPath $wheel -Algorithm SHA256).Hash
$glslangArchiveHash = (Get-FileHash -LiteralPath $glslangArchivePath -Algorithm SHA256).Hash
if ($mesonHash -ne $ExpectedMesonSha256.ToUpperInvariant()) {
    throw "Meson wheel SHA-256 mismatch: expected $ExpectedMesonSha256, got $mesonHash"
}
if ($glslangArchiveHash -ne $ExpectedGlslangArchiveSha256.ToUpperInvariant()) {
    throw "glslang archive SHA-256 mismatch: expected $ExpectedGlslangArchiveSha256, got $glslangArchiveHash"
}

$python = Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $python) {
    throw 'Python 3 is required to stage the local Meson wheel'
}

$mesonRoot = Join-Path $resolvedOutput 'meson'
$binRoot = Join-Path $resolvedOutput 'bin'
if ((Test-Path -LiteralPath $mesonRoot) -or (Test-Path -LiteralPath $binRoot)) {
    throw "Refusing to overwrite an existing staged toolchain: $resolvedOutput"
}
New-Item -ItemType Directory -Force -Path $mesonRoot, $binRoot | Out-Null

& $python.Source -m pip install --disable-pip-version-check --no-index --no-deps --target $mesonRoot $wheel
if ($LASTEXITCODE -ne 0) {
    throw "Staging the local Meson wheel failed (exit code $LASTEXITCODE)"
}
if (-not (Test-Path -LiteralPath (Join-Path $mesonRoot 'mesonbuild\mesonmain.py') -PathType Leaf)) {
    throw 'Staged wheel did not contain mesonbuild/mesonmain.py'
}

$stagedGlslang = Join-Path $binRoot 'glslangValidator.exe'
$extractRoot = Join-Path $resolvedOutput '_glslang-extract'
$selectedGlslang = $null
try {
    Expand-Archive -LiteralPath $glslangArchivePath -DestinationPath $extractRoot
    foreach ($name in @($inputs.glslangValidator.executableCandidates)) {
        $matches = @(Get-ChildItem -LiteralPath $extractRoot -Recurse -File -Filter $name)
        if ($matches.Count -eq 1) {
            $selectedGlslang = $matches[0]
            break
        }
        if ($matches.Count -gt 1) {
            throw "Pinned glslang archive contains multiple $name candidates"
        }
    }
    if (-not $selectedGlslang) {
        throw 'Pinned glslang archive does not contain a recognized standalone executable'
    }
    $glslangPathInArchive = [IO.Path]::GetRelativePath($extractRoot, $selectedGlslang.FullName).Replace('\', '/')
    Copy-Item -LiteralPath $selectedGlslang.FullName -Destination $stagedGlslang
}
finally {
    if (Test-Path -LiteralPath $extractRoot -PathType Container) {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force
    }
}
$versionLines = @(& $stagedGlslang --version 2>&1)
if ($LASTEXITCODE -ne 0 -or $versionLines.Count -eq 0) {
    throw 'Staged glslang executable did not run successfully'
}

$previousPythonPath = $env:PYTHONPATH
try {
    $env:PYTHONPATH = if ($previousPythonPath) { "$mesonRoot;$previousPythonPath" } else { $mesonRoot }
    $mesonVersionLines = @(& $python.Source -m mesonbuild.mesonmain --version 2>&1)
    if ($LASTEXITCODE -ne 0 -or $mesonVersionLines.Count -eq 0) {
        throw 'Staged Meson module did not run successfully'
    }
}
finally {
    $env:PYTHONPATH = $previousPythonPath
}

$stagedFiles = @(
    Get-ChildItem -LiteralPath $mesonRoot, $binRoot -Recurse -File |
        Sort-Object FullName |
        ForEach-Object {
            [ordered]@{
                Path = [IO.Path]::GetRelativePath($resolvedOutput, $_.FullName).Replace('\', '/')
                Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        }
)

$manifest = [ordered]@{
    Schema = 1
    MesonWheelSource = $wheel
    MesonWheelSha256 = $mesonHash
    MesonVersion = $mesonVersionLines[0].ToString().Trim()
    GlslangArchiveSource = $glslangArchivePath
    GlslangArchiveSha256 = $glslangArchiveHash
    GlslangPathInArchive = $glslangPathInArchive
    GlslangExecutableSha256 = (Get-FileHash -LiteralPath $stagedGlslang -Algorithm SHA256).Hash
    GlslangVersion = $versionLines[0].ToString().Trim()
    InputManifest = $inputManifestPath
    InputManifestSha256 = (Get-FileHash -LiteralPath $inputManifestPath -Algorithm SHA256).Hash
    Files = $stagedFiles
    OutputRoot = $resolvedOutput
    NetworkUsed = $false
    SystemInstalled = $false
    GameInstalled = $false
}
$manifestPath = Join-Path $resolvedOutput 'manifest.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8

[pscustomobject]@{
    OutputRoot = $resolvedOutput
    ManifestPath = $manifestPath
    MesonVersion = $manifest.MesonVersion
    GlslangVersion = $manifest.GlslangVersion
    SystemInstalled = $false
    GameInstalled = $false
}
