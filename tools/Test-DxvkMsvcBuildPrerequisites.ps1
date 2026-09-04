[CmdletBinding()]
param(
    [string]$SourceRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'reference\external\dxvk-source-official'),
    [string]$PatchPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Backends\DxvkD3D11\patches\dxvk-adeda663-d3d11-shader-overrides.patch'),
    [switch]$RequireReady
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$revision = 'adeda6639a09ad1b6a1b7c4158a781ffaf68947d'
$workspaceToolchainRoot = Join-Path $root 'artifacts\toolchains\dxvk-msvc'
$toolchainInputManifestPath = Join-Path $root 'src\Backends\DxvkD3D11\toolchain-inputs.json'
$stagedToolchainManifestPath = Join-Path $workspaceToolchainRoot 'manifest.json'

function Find-CommandPath {
    param([Parameter(Mandatory)][string[]]$Names)

    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) {
            return $command.Source
        }
    }
    return $null
}

function Get-NativeVersion {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList
    )

    $lines = @(& $FilePath @ArgumentList 2>&1)
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    return (($lines | Select-Object -First 1).ToString()).Trim()
}

$missing = [Collections.Generic.List[string]]::new()
$notes = [Collections.Generic.List[string]]::new()

$gitPath = Find-CommandPath @('git.exe', 'git')
if (-not $gitPath) {
    $missing.Add('Git')
}

$sourceRevision = $null
$submodulesReady = $false
$sourceWorkingTreeClean = $null
if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    $missing.Add('Pinned DXVK source mirror')
}
elseif ($gitPath) {
    $revisionLines = @(& $gitPath -C $SourceRoot rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $revisionLines.Count -gt 0) {
        $sourceRevision = $revisionLines[0].Trim()
    }
    if ($sourceRevision -ne $revision) {
        $missing.Add("Pinned DXVK revision $revision")
    }

    $statusLines = @(& $gitPath -C $SourceRoot status --short 2>$null)
    if ($LASTEXITCODE -eq 0) {
        $sourceWorkingTreeClean = $statusLines.Count -eq 0
    }

    $submoduleLines = @(& $gitPath -C $SourceRoot submodule status --recursive 2>$null)
    if ($LASTEXITCODE -eq 0 -and $submoduleLines.Count -gt 0) {
        $badSubmodules = @($submoduleLines | Where-Object { $_ -match '^[+-U]' })
        $submodulesReady = $badSubmodules.Count -eq 0
    }
    if (-not $submodulesReady) {
        $missing.Add('Initialized pinned DXVK submodules')
    }
}

if (-not (Test-Path -LiteralPath $PatchPath -PathType Leaf)) {
    $missing.Add('Pinned D3D11 shader-override patch')
}

$pythonPath = Find-CommandPath @('python.exe', 'python')
if (-not $pythonPath) {
    $pyLauncher = Find-CommandPath @('py.exe', 'py')
    if ($pyLauncher) {
        $pythonProbe = @(& $pyLauncher -3 -c 'import sys; print(sys.executable)' 2>$null)
        if ($LASTEXITCODE -eq 0 -and $pythonProbe.Count -gt 0) {
            $pythonPath = $pythonProbe[0].Trim()
        }
    }
}
if (-not $pythonPath) {
    $missing.Add('Python 3')
}

$pythonVersion = if ($pythonPath) { Get-NativeVersion $pythonPath @('--version') } else { $null }
$mesonPath = $null
$mesonMode = $null
$mesonModuleRoot = $null
$mesonVersion = $null
$toolchainProvenanceReady = $false
$toolchainInputs = if (Test-Path -LiteralPath $toolchainInputManifestPath -PathType Leaf) {
    Get-Content -Raw -LiteralPath $toolchainInputManifestPath | ConvertFrom-Json
}
else {
    $missing.Add('Reviewed DXVK toolchain input manifest')
    $null
}
$stagedToolchain = if (Test-Path -LiteralPath $stagedToolchainManifestPath -PathType Leaf) {
    Get-Content -Raw -LiteralPath $stagedToolchainManifestPath | ConvertFrom-Json
}
else {
    $null
}

if ($pythonPath -and $toolchainInputs -and $stagedToolchain) {
    $workspaceMesonRoot = Join-Path $workspaceToolchainRoot 'meson'
    $workspaceMesonMain = Join-Path $workspaceMesonRoot 'mesonbuild\mesonmain.py'
    $workspaceGlslang = Join-Path $workspaceToolchainRoot 'bin\glslangValidator.exe'
    $inputManifestHash = (Get-FileHash -LiteralPath $toolchainInputManifestPath -Algorithm SHA256).Hash
    $stagedFilesValid = $stagedToolchain.Files.Count -gt 0
    $stagedFileNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in @($stagedToolchain.Files)) {
        $relative = $file.Path.ToString().Replace('/', [IO.Path]::DirectorySeparatorChar)
        $candidate = [IO.Path]::GetFullPath((Join-Path $workspaceToolchainRoot $relative))
        if (-not $candidate.StartsWith([IO.Path]::GetFullPath($workspaceToolchainRoot) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $candidate -PathType Leaf) -or
            (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash -ne $file.Sha256) {
            $stagedFilesValid = $false
            break
        }
        [void]$stagedFileNames.Add($file.Path.ToString().Replace('\', '/'))
    }
    if (-not $stagedFileNames.Contains('bin/glslangValidator.exe') -or
        -not $stagedFileNames.Contains('meson/mesonbuild/mesonmain.py')) {
        $stagedFilesValid = $false
    }

    $provenanceMatches =
        $toolchainInputs.meson.status -eq 'pinned' -and
        $toolchainInputs.glslangValidator.status -eq 'pinned' -and
        $toolchainInputs.meson.sha256 -match '^[0-9a-fA-F]{64}$' -and
        $toolchainInputs.glslangValidator.archiveSha256 -match '^[0-9a-fA-F]{64}$' -and
        $stagedToolchain.InputManifestSha256 -eq $inputManifestHash -and
        $stagedToolchain.MesonWheelSha256 -eq $toolchainInputs.meson.sha256.ToUpperInvariant() -and
        $stagedToolchain.GlslangArchiveSha256 -eq $toolchainInputs.glslangValidator.archiveSha256.ToUpperInvariant() -and
        $stagedToolchain.GlslangExecutableSha256 -eq (Get-FileHash -LiteralPath $workspaceGlslang -Algorithm SHA256).Hash -and
        $stagedFilesValid

    if ($provenanceMatches -and
        (Test-Path -LiteralPath $workspaceMesonMain -PathType Leaf) -and
        (Test-Path -LiteralPath $workspaceGlslang -PathType Leaf) -and
        (Get-FileHash -LiteralPath $workspaceGlslang -Algorithm SHA256).Hash -eq $stagedToolchain.GlslangExecutableSha256) {
        $previousPythonPath = $env:PYTHONPATH
        try {
            $env:PYTHONPATH = if ($previousPythonPath) { "$workspaceMesonRoot;$previousPythonPath" } else { $workspaceMesonRoot }
            $versionProbe = @(& $pythonPath -m mesonbuild.mesonmain --version 2>$null)
            if ($LASTEXITCODE -eq 0 -and $versionProbe.Count -gt 0) {
                $mesonPath = $pythonPath
                $mesonMode = 'workspace-python-module'
                $mesonModuleRoot = $workspaceMesonRoot
                $mesonVersion = $versionProbe[0].Trim()
                $toolchainProvenanceReady = $true
            }
        }
        finally {
            $env:PYTHONPATH = $previousPythonPath
        }
    }
}
if (-not $mesonPath) {
    $missing.Add('Hash-verified workspace Meson')
}

$workspaceGlslang = Join-Path $workspaceToolchainRoot 'bin\glslangValidator.exe'
$glslangPath = if ($toolchainProvenanceReady -and (Test-Path -LiteralPath $workspaceGlslang -PathType Leaf)) {
    $workspaceGlslang
}
else {
    $null
}
$glslangVersion = if ($glslangPath) { Get-NativeVersion $glslangPath @('--version') } else { $null }
if (-not $glslangPath) {
    $missing.Add('Hash-verified workspace glslangValidator')
}

$vsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsInstall = $null
if (Test-Path -LiteralPath $vsWhere -PathType Leaf) {
    $vsProbe = @(& $vsWhere -latest -products * -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath 2>$null)
    if ($LASTEXITCODE -eq 0 -and $vsProbe.Count -gt 0) {
        $vsInstall = $vsProbe[0].Trim()
    }
    if (-not $vsInstall) {
        # Some Build Tools installations contain the required compiler and SDK
        # components but do not advertise the aggregate workload ID to vswhere.
        # Accept the installation only after checking the actual entry points.
        $fallbackProbe = @(& $vsWhere -latest -products * -property installationPath 2>$null)
        if ($LASTEXITCODE -eq 0 -and $fallbackProbe.Count -gt 0) {
            $candidate = $fallbackProbe[0].Trim()
            if ((Test-Path -LiteralPath (Join-Path $candidate 'Common7\Tools\VsDevCmd.bat') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $candidate 'MSBuild\Current\Bin\MSBuild.exe') -PathType Leaf)) {
                $vsInstall = $candidate
            }
        }
    }
}

$vsDevCmd = if ($vsInstall) { Join-Path $vsInstall 'Common7\Tools\VsDevCmd.bat' } else { $null }
$msBuildPath = if ($vsInstall) { Join-Path $vsInstall 'MSBuild\Current\Bin\MSBuild.exe' } else { $null }
if (-not $vsDevCmd -or -not (Test-Path -LiteralPath $vsDevCmd -PathType Leaf)) {
    $missing.Add('Visual Studio Native Desktop toolchain')
}
if (-not $msBuildPath -or -not (Test-Path -LiteralPath $msBuildPath -PathType Leaf)) {
    $missing.Add('MSBuild')
}

$notes.Add('D3D8 SDK headers are not required: the first build disables the separate D3D8, D3D9, and D3D10 DLL targets.')
$notes.Add('D3D11 still compiles DXVK internal D3D10 interface sources, as required by its own meson.build.')
$notes.Add('The builder exports exact committed root and submodule trees; local source-mirror edits are never staged.')
$notes.Add('The builder accepts only the workspace-staged Meson/glslang toolchain whose hashes match the reviewed input and staging manifests.')
$notes.Add('This audit does not download, install, build, or copy anything into a game directory.')

$result = [pscustomobject]@{
    Ready = $missing.Count -eq 0
    PinnedRevision = $revision
    SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
    SourceRevision = $sourceRevision
    SourceWorkingTreeClean = $sourceWorkingTreeClean
    SubmodulesReady = $submodulesReady
    PatchPath = [IO.Path]::GetFullPath($PatchPath)
    GitPath = $gitPath
    PythonPath = $pythonPath
    PythonVersion = $pythonVersion
    MesonPath = $mesonPath
    MesonMode = $mesonMode
    MesonModuleRoot = $mesonModuleRoot
    MesonVersion = $mesonVersion
    GlslangPath = $glslangPath
    GlslangVersion = $glslangVersion
    ToolchainProvenanceReady = $toolchainProvenanceReady
    ToolchainInputManifestPath = $toolchainInputManifestPath
    StagedToolchainManifestPath = $stagedToolchainManifestPath
    StagedToolchainManifest = $stagedToolchain
    VsDevCmd = $vsDevCmd
    MsBuildPath = $msBuildPath
    Missing = @($missing)
    Notes = @($notes)
}

if ($RequireReady -and -not $result.Ready) {
    throw ('DXVK MSVC build prerequisites are incomplete: ' + ($result.Missing -join ', '))
}

$result
