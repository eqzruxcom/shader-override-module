[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$auditPath = Join-Path $PSScriptRoot 'Test-DxvkMsvcBuildPrerequisites.ps1'
$buildPath = Join-Path $PSScriptRoot 'Build-DxvkD3D11Msvc.ps1'
$stagePath = Join-Path $PSScriptRoot 'Stage-DxvkMsvcBuildPrerequisites.ps1'
$acquireTestPath = Join-Path $PSScriptRoot 'Test-DxvkMsvcAcquisition.ps1'
$inputsPath = Join-Path $root 'src\Backends\DxvkD3D11\toolchain-inputs.json'

foreach ($path in @($auditPath, $buildPath, $stagePath, $acquireTestPath)) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -ne 0) {
        throw "PowerShell parse errors in $path`: $($errors.Message -join '; ')"
    }
}

& $acquireTestPath

if (-not (Test-Path -LiteralPath $inputsPath -PathType Leaf)) {
    throw "Missing pinned toolchain input manifest: $inputsPath"
}
$inputs = Get-Content -Raw -LiteralPath $inputsPath | ConvertFrom-Json
if ($inputs.schema -ne 1) {
    throw 'Unexpected DXVK toolchain input manifest schema'
}
if ($inputs.meson.status -ne 'pinned' -or $inputs.meson.version -ne '1.12.0') {
    throw 'Meson input is not pinned to the reviewed version'
}
if ($inputs.meson.sha256 -notmatch '^[0-9a-f]{64}$' -or $inputs.meson.sizeBytes -le 0) {
    throw 'Meson input is missing exact content provenance'
}
if ($inputs.glslangValidator.status -ne 'pinned' -or $inputs.glslangValidator.version -ne '16.5.0') {
    throw 'glslang input is not pinned to the reviewed Khronos release'
}
if ($inputs.glslangValidator.archiveSha256 -notmatch '^[0-9a-f]{64}$' -or -not $inputs.glslangValidator.archiveUrl) {
    throw 'glslang release archive is missing exact provenance'
}
if ($inputs.policy.automaticDownload -or $inputs.policy.systemInstall -or $inputs.policy.gameInstall) {
    throw 'Toolchain input policy unexpectedly permits download or installation'
}
if (-not $inputs.policy.requireBothArchiveSha256ValuesBeforeBuild) {
    throw 'Toolchain input policy must require both hashes before building'
}

$stageText = [IO.File]::ReadAllText($stagePath)
foreach ($evidence in @('--no-index', '--no-deps', 'SystemInstalled = $false', 'GameInstalled = $false', "[Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]`$ExpectedMesonSha256", "[Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]`$ExpectedGlslangArchiveSha256", "glslangValidator.status -ne 'pinned'", 'Files = $stagedFiles')) {
    if ($stageText -notmatch [regex]::Escape($evidence)) {
        throw "Local prerequisite staging script is missing safety evidence: $evidence"
    }
}

$auditText = [IO.File]::ReadAllText($auditPath)
foreach ($evidence in @('InputManifestSha256 -eq $inputManifestHash', '$stagedFilesValid', "Contains('bin/glslangValidator.exe')", "Contains('meson/mesonbuild/mesonmain.py')")) {
    if ($auditText -notmatch [regex]::Escape($evidence)) {
        throw "Prerequisite audit is missing staged-file provenance evidence: $evidence"
    }
}
foreach ($term in @('Invoke-WebRequest', 'Start-BitsTransfer', 'curl.exe')) {
    if ($stageText -match [regex]::Escape($term)) {
        throw "Local prerequisite staging script unexpectedly contains a downloader: $term"
    }
}

$audit = & $auditPath
if ($audit.PinnedRevision -ne 'adeda6639a09ad1b6a1b7c4158a781ffaf68947d') {
    throw 'Prerequisite audit does not pin the intended DXVK revision'
}
if (-not $audit.VsDevCmd -or -not $audit.MsBuildPath) {
    throw 'Installed Visual Studio native toolchain was not detected'
}

$buildText = [IO.File]::ReadAllText($buildPath)
$requiredEvidence = @(
    '-Denable_dxgi=true',
    '-Denable_d3d11=true',
    '-Denable_d3d10=false',
    '-Denable_d3d9=false',
    '-Denable_d3d8=false',
    "Installed = `$false",
    "RuntimeEligible = `$false",
    'Refusing output outside the workspace artifacts directory',
    "@('d3d11.dll', 'dxgi.dll')",
    'Export-GitTree $SourceRoot $revision',
    'submodule foreach --recursive',
    '$patchDirectoryArgument = "--directory=$stagedSourceRelative"',
    "Join-Path `$stagedSource 'src\d3d11\d3d11_shader_override.cpp'",
    'MesonWheelSha256 = $prerequisites.StagedToolchainManifest.MesonWheelSha256',
    'GlslangArchiveSha256 = $prerequisites.StagedToolchainManifest.GlslangArchiveSha256'
)
foreach ($evidence in $requiredEvidence) {
    if ($buildText -notmatch [regex]::Escape($evidence)) {
        throw "Build script is missing safety evidence: $evidence"
    }
}

$forbidden = @('Invoke-WebRequest', 'Start-BitsTransfer', 'curl.exe', 'game\', 'Win64', 'robocopy')
foreach ($term in $forbidden) {
    if ($buildText -match [regex]::Escape($term)) {
        throw "Build script unexpectedly contains network or live-install behavior: $term"
    }
}

Write-Host 'PASS: DXVK MSVC audit and non-installing x64 D3D11/DXGI build pipeline are structurally valid.'
if ($audit.Ready) {
    Write-Host 'READY: all external build prerequisites are present.'
}
else {
    Write-Host ('NOT READY (expected until dependencies are approved): ' + ($audit.Missing -join ', '))
}
