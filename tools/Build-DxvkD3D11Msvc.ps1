[CmdletBinding()]
param(
    [string]$SourceRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'reference\external\dxvk-source-official'),
    [string]$OutputParent = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\dxvk-d3d11-msvc-builds')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $root 'artifacts'))
$resolvedOutputParent = [IO.Path]::GetFullPath($OutputParent)
$patchPath = Join-Path $root 'src\Backends\DxvkD3D11\patches\dxvk-adeda663-d3d11-shader-overrides.patch'
$prerequisiteScript = Join-Path $PSScriptRoot 'Test-DxvkMsvcBuildPrerequisites.ps1'
$revision = 'adeda6639a09ad1b6a1b7c4158a781ffaf68947d'

if (-not $resolvedOutputParent.StartsWith($artifactsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing output outside the workspace artifacts directory: $resolvedOutputParent"
}

$prerequisites = & $prerequisiteScript -SourceRoot $SourceRoot -PatchPath $patchPath
if (-not $prerequisites.Ready) {
    throw ('DXVK MSVC build prerequisites are incomplete: ' + ($prerequisites.Missing -join ', '))
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$buildRoot = Join-Path $resolvedOutputParent ("dxvk-$($revision.Substring(0, 9))-x64-$stamp")
$stagedSource = Join-Path $buildRoot 'source'
$mesonBuild = Join-Path $buildRoot 'build-msvc-x64'
$publishRoot = Join-Path $buildRoot 'output\x64'

if (Test-Path -LiteralPath $buildRoot) {
    throw "Refusing to overwrite an existing build directory: $buildRoot"
}

New-Item -ItemType Directory -Force -Path $stagedSource, $publishRoot | Out-Null

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$FailureMessage
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage (exit code $LASTEXITCODE)"
    }
}

function Import-VsEnvironment {
    param([Parameter(Mandatory)][string]$VsDevCmd)

    $lines = @(& $env:ComSpec /d /s /c "`"$VsDevCmd`" -arch=x64 -host_arch=x64 -no_logo && set")
    if ($LASTEXITCODE -ne 0) {
        throw "Visual Studio environment initialization failed (exit code $LASTEXITCODE)"
    }
    foreach ($line in $lines) {
        $pair = $line -split '=', 2
        if ($pair.Count -eq 2) {
            [Environment]::SetEnvironmentVariable($pair[0], $pair[1], 'Process')
        }
    }
}

function Export-GitTree {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Label
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $archive = Join-Path $buildRoot ("_git-archive-$([guid]::NewGuid().ToString('N')).zip")
    try {
        Invoke-NativeChecked $prerequisites.GitPath @('-C', $Repository, 'archive', '--format=zip', "--output=$archive", $Commit) "Archiving $Label failed"
        Expand-Archive -LiteralPath $archive -DestinationPath $Destination -Force
    }
    finally {
        if (Test-Path -LiteralPath $archive -PathType Leaf) {
            Remove-Item -LiteralPath $archive -Force
        }
    }
}

try {
    Export-GitTree $SourceRoot $revision $stagedSource 'pinned DXVK root'

    $foreachProgram = 'printf "%s\t%s\n" "$displaypath" "$sha1"'
    $submoduleLines = @(& $prerequisites.GitPath -C $SourceRoot submodule foreach --recursive --quiet $foreachProgram)
    if ($LASTEXITCODE -ne 0) {
        throw "Enumerating pinned DXVK submodules failed (exit code $LASTEXITCODE)"
    }
    foreach ($line in $submoduleLines) {
        $fields = $line -split "`t", 2
        if ($fields.Count -ne 2 -or $fields[1] -notmatch '^[0-9a-fA-F]{40}$') {
            throw "Unexpected submodule identity line: $line"
        }
        $relativePath = $fields[0]
        $submoduleCommit = $fields[1].ToLowerInvariant()
        $submoduleSource = Join-Path $SourceRoot $relativePath
        $submoduleDestination = Join-Path $stagedSource $relativePath
        Export-GitTree $submoduleSource $submoduleCommit $submoduleDestination "submodule $relativePath"
    }

    # The exported source lives below this workspace repository, so git still
    # discovers the parent worktree even when a native current directory is set.
    # Target the exported tree explicitly with apply --directory.
    $stagedSourceRelative = [IO.Path]::GetRelativePath($root, $stagedSource).Replace('\', '/')
    $patchDirectoryArgument = "--directory=$stagedSourceRelative"
    Invoke-NativeChecked $prerequisites.GitPath @('-C', $root, 'apply', '--check', '--no-index', $patchDirectoryArgument, $patchPath) 'DXVK patch does not apply to staged source'
    Invoke-NativeChecked $prerequisites.GitPath @('-C', $root, 'apply', '--no-index', $patchDirectoryArgument, $patchPath) 'DXVK patch application failed'
    $overrideImplementation = Join-Path $stagedSource 'src\d3d11\d3d11_shader_override.cpp'
    if (-not (Test-Path -LiteralPath $overrideImplementation -PathType Leaf)) {
        throw "DXVK patch application did not publish the staged override implementation: $overrideImplementation"
    }

    Import-VsEnvironment $prerequisites.VsDevCmd
    # VS 17.14 omits the desktop Windows SDK from INCLUDE when the optional
    # UAP.props package is absent. Meson snapshots this environment for its
    # custom rc.exe command, so restore the validated desktop include paths
    # before Meson configuration as well as in Directory.Build.targets below.
    $windowsSdkDirectory = [IO.Path]::GetFullPath($env:WindowsSdkDir)
    $windowsSdkVersion = $env:WindowsSDKVersion.TrimEnd('\')
    $desktopSdkInputs = @(
        (Join-Path $windowsSdkDirectory "Include\$windowsSdkVersion\shared\sdkddkver.h"),
        (Join-Path $windowsSdkDirectory "Lib\$windowsSdkVersion\um\x64\gdi32.lib")
    )
    $missingDesktopSdkInputs = @($desktopSdkInputs | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missingDesktopSdkInputs.Count -ne 0) {
        throw ('Windows desktop SDK validation failed: ' + ($missingDesktopSdkInputs -join ', '))
    }
    $desktopSdkIncludePaths = @(
        (Join-Path $windowsSdkDirectory "Include\$windowsSdkVersion\ucrt"),
        (Join-Path $windowsSdkDirectory "Include\$windowsSdkVersion\um"),
        (Join-Path $windowsSdkDirectory "Include\$windowsSdkVersion\shared")
    )
    $env:INCLUDE = (($desktopSdkIncludePaths + @($env:INCLUDE)) | Where-Object { $_ }) -join ';'
    if ($prerequisites.MesonMode -eq 'workspace-python-module') {
        $env:PYTHONPATH = if ($env:PYTHONPATH) {
            "$($prerequisites.MesonModuleRoot);$($env:PYTHONPATH)"
        }
        else {
            $prerequisites.MesonModuleRoot
        }
    }
    $env:PATH = "$(Split-Path -Parent $prerequisites.GlslangPath);$($env:PATH)"
    $mesonArgs = @(
        'setup',
        '--buildtype', 'release',
        '--backend', 'vs2022',
        '-Denable_dxgi=true',
        '-Denable_d3d11=true',
        '-Denable_d3d10=false',
        '-Denable_d3d9=false',
        '-Denable_d3d8=false',
        $mesonBuild,
        $stagedSource
    )
    if ($prerequisites.MesonMode -in @('python-module', 'workspace-python-module')) {
        Invoke-NativeChecked $prerequisites.MesonPath (@('-m', 'mesonbuild.mesonmain') + $mesonArgs) 'Meson configuration failed'
    }
    else {
        Invoke-NativeChecked $prerequisites.MesonPath $mesonArgs 'Meson configuration failed'
    }

    $solutionPath = Join-Path $mesonBuild 'dxvk.sln'
    $sdkTargetsPath = Join-Path $mesonBuild 'Directory.Build.targets'
    $sdkTargets = @'
<Project>
  <PropertyGroup>
    <IncludePath>$(WindowsSdkDir)Include\$(TargetPlatformVersion)\ucrt;$(WindowsSdkDir)Include\$(TargetPlatformVersion)\um;$(WindowsSdkDir)Include\$(TargetPlatformVersion)\shared;$(WindowsSdkDir)Include\$(TargetPlatformVersion)\winrt;$(WindowsSdkDir)Include\$(TargetPlatformVersion)\cppwinrt;$(IncludePath)</IncludePath>
    <LibraryPath>$(WindowsSdkDir)Lib\$(TargetPlatformVersion)\ucrt\x64;$(WindowsSdkDir)Lib\$(TargetPlatformVersion)\um\x64;$(LibraryPath)</LibraryPath>
  </PropertyGroup>
  <Target Name="DxvkValidateDesktopSdk" BeforeTargets="_CheckWindowsSDKInstalled">
    <PropertyGroup>
      <WindowsSDKInstalled>true</WindowsSDKInstalled>
      <WindowsSDK_Desktop_Support>true</WindowsSDK_Desktop_Support>
    </PropertyGroup>
  </Target>
  <ItemDefinitionGroup>
    <ClCompile>
      <AdditionalIncludeDirectories>$(WindowsSdkDir)Include\$(TargetPlatformVersion)\ucrt;$(WindowsSdkDir)Include\$(TargetPlatformVersion)\um;$(WindowsSdkDir)Include\$(TargetPlatformVersion)\shared;$(WindowsSdkDir)Include\$(TargetPlatformVersion)\winrt;$(WindowsSdkDir)Include\$(TargetPlatformVersion)\cppwinrt;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>
    </ClCompile>
    <ResourceCompile>
      <AdditionalIncludeDirectories>$(WindowsSdkDir)Include\$(TargetPlatformVersion)\ucrt;$(WindowsSdkDir)Include\$(TargetPlatformVersion)\um;$(WindowsSdkDir)Include\$(TargetPlatformVersion)\shared;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>
    </ResourceCompile>
    <Link>
      <AdditionalLibraryDirectories>$(WindowsSdkDir)Lib\$(TargetPlatformVersion)\ucrt\x64;$(WindowsSdkDir)Lib\$(TargetPlatformVersion)\um\x64;%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>
    </Link>
    <Lib>
      <AdditionalLibraryDirectories>$(WindowsSdkDir)Lib\$(TargetPlatformVersion)\ucrt\x64;$(WindowsSdkDir)Lib\$(TargetPlatformVersion)\um\x64;%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>
    </Lib>
  </ItemDefinitionGroup>
</Project>
'@
    [IO.File]::WriteAllText($sdkTargetsPath, $sdkTargets, [Text.UTF8Encoding]::new($false))
    Invoke-NativeChecked $prerequisites.MsBuildPath @('-m', $solutionPath) 'DXVK MSVC build failed'

    $requiredDlls = @('d3d11.dll', 'dxgi.dll')
    $published = [Collections.Generic.List[object]]::new()
    foreach ($name in $requiredDlls) {
        $matches = @(Get-ChildItem -LiteralPath (Join-Path $mesonBuild 'src') -Recurse -File -Filter $name)
        if ($matches.Count -ne 1) {
            throw "Expected exactly one $name build output, found $($matches.Count)"
        }
        $destination = Join-Path $publishRoot $name
        Copy-Item -LiteralPath $matches[0].FullName -Destination $destination
        $published.Add([pscustomobject]@{
            Name = $name
            Source = $matches[0].FullName
            Path = $destination
            Sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        })

        $pdbMatches = @(Get-ChildItem -LiteralPath (Join-Path $mesonBuild 'src') -Recurse -File -Filter ([IO.Path]::ChangeExtension($name, '.pdb')))
        if ($pdbMatches.Count -eq 1) {
            Copy-Item -LiteralPath $pdbMatches[0].FullName -Destination (Join-Path $publishRoot $pdbMatches[0].Name)
        }
    }

    $manifest = [ordered]@{
        Schema = 1
        Backend = 'DXVK D3D11 shader replacement'
        Architecture = 'x64'
        SourceRevision = $revision
        PatchPath = $patchPath
        PatchSha256 = (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash
        MesonVersion = $prerequisites.MesonVersion
        MesonWheelSha256 = $prerequisites.StagedToolchainManifest.MesonWheelSha256
        GlslangVersion = $prerequisites.GlslangVersion
        GlslangArchiveSha256 = $prerequisites.StagedToolchainManifest.GlslangArchiveSha256
        GlslangExecutableSha256 = $prerequisites.StagedToolchainManifest.GlslangExecutableSha256
        WindowsSdkVersion = $windowsSdkVersion
        WindowsDesktopSdkValidated = $true
        WindowsDesktopSdkTargetsSha256 = (Get-FileHash -LiteralPath $sdkTargetsPath -Algorithm SHA256).Hash
        ToolchainInputManifest = $prerequisites.ToolchainInputManifestPath
        ToolchainInputManifestSha256 = (Get-FileHash -LiteralPath $prerequisites.ToolchainInputManifestPath -Algorithm SHA256).Hash
        StagedToolchainManifest = $prerequisites.StagedToolchainManifestPath
        StagedToolchainManifestSha256 = (Get-FileHash -LiteralPath $prerequisites.StagedToolchainManifestPath -Algorithm SHA256).Hash
        VisualStudioDevCmd = $prerequisites.VsDevCmd
        Files = @($published)
        Installed = $false
        RuntimeEligible = $false
        Note = 'Offline build artifact only. Isolated D3D11 smoke testing and native/DXVK parity validation are still required.'
    }
    $manifestPath = Join-Path $buildRoot 'manifest.json'
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8

    [pscustomobject]@{
        BuildRoot = $buildRoot
        OutputRoot = $publishRoot
        ManifestPath = $manifestPath
        Installed = $false
        RuntimeEligible = $false
    }
}
catch {
    $failurePath = Join-Path $buildRoot 'BUILD-FAILED.txt'
    if (Test-Path -LiteralPath $buildRoot -PathType Container) {
        $_.Exception.ToString() | Set-Content -LiteralPath $failurePath -Encoding utf8
    }
    throw
}
