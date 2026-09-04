[CmdletBinding()]
param(
    [string]$SourceRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'reference\external\dxvk-source-official')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$patchPath = Join-Path $root 'src\Backends\DxvkD3D11\patches\dxvk-adeda663-d3d11-shader-overrides.patch'
$revision = 'adeda6639a09ad1b6a1b7c4158a781ffaf68947d'
$vsDevCmd = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$workName = 'ue4fx-dxvk-patch-test-' + [guid]::NewGuid().ToString('N')
$work = Join-Path $tempRoot $workName

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

if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "Pinned DXVK source mirror was not found: $SourceRoot"
}
if (-not (Test-Path -LiteralPath $patchPath -PathType Leaf)) {
    throw "DXVK patch was not found: $patchPath"
}
if (-not (Test-Path -LiteralPath $vsDevCmd -PathType Leaf)) {
    throw "Visual Studio Build Tools were not found at $vsDevCmd"
}

$sourceRevision = (& git -C $SourceRoot rev-parse $revision).Trim()
if ($LASTEXITCODE -ne 0 -or $sourceRevision -ne $revision) {
    throw "Pinned DXVK revision $revision is unavailable in $SourceRoot"
}

$dependencyPaths = @(
    (Join-Path $SourceRoot 'include\vulkan\include'),
    (Join-Path $SourceRoot 'include\spirv\include'),
    (Join-Path $SourceRoot 'subprojects\dxbc-spirv')
)
foreach ($path in $dependencyPaths) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        throw "Initialized DXVK dependency is missing: $path"
    }
}

try {
    Invoke-NativeChecked git @('clone', '--shared', '--no-checkout', $SourceRoot, $work) 'DXVK test clone failed'
    Invoke-NativeChecked git @('-C', $work, 'checkout', '--detach', $revision) 'DXVK revision checkout failed'
    Invoke-NativeChecked git @('-C', $work, 'apply', '--check', $patchPath) 'DXVK patch does not apply cleanly'
    Invoke-NativeChecked git @('-C', $work, 'apply', $patchPath) 'DXVK patch application failed'

    $expectedFiles = @(
        'src\d3d11\d3d11_shader_override.h',
        'src\d3d11\d3d11_shader_override.cpp',
        'src\d3d11\d3d11_device.cpp',
        'src\d3d11\d3d11_device.h',
        'src\d3d11\d3d11_options.cpp',
        'src\d3d11\d3d11_options.h',
        'src\d3d11\meson.build'
    )
    foreach ($relativePath in $expectedFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $work $relativePath) -PathType Leaf)) {
            throw "Patched file is missing: $relativePath"
        }
    }

    $optionsText = [IO.File]::ReadAllText((Join-Path $work 'src\d3d11\d3d11_options.cpp'))
    if ($optionsText -notmatch 'd3d11\.shaderOverridePath') {
        throw 'Patched DXVK source does not expose d3d11.shaderOverridePath'
    }

    $overrideText = [IO.File]::ReadAllText((Join-Path $work 'src\d3d11\d3d11_shader_override.cpp'))
    if ($overrideText -notmatch 'MaxReplacementSize = 64ull \* 1024ull \* 1024ull') {
        throw 'Patched DXVK source is missing the bounded replacement-size guard'
    }
    if ($overrideText -notmatch 'MaxReplacementCacheSize = 64ull \* 1024ull \* 1024ull' -or
        $overrideText -notmatch 'Shader replacement changed while reading') {
        throw 'Patched DXVK source is missing bounded stable-snapshot cache evidence'
    }

    $deviceText = [IO.File]::ReadAllText((Join-Path $work 'src\d3d11\d3d11_device.cpp'))
    $requiredGateEvidence = @(
        'resource or thread-group declaration mismatch',
        'DclConstantBuffer',
        'DclResource',
        'DclUav',
        'DclThreadGroup'
    )
    foreach ($evidence in $requiredGateEvidence) {
        if ($deviceText -notmatch [regex]::Escape($evidence)) {
            throw "Patched DXVK source is missing compatibility-gate evidence: $evidence"
        }
    }

    $objectRoot = Join-Path $work 'test-objects'
    New-Item -ItemType Directory -Force -Path $objectRoot | Out-Null

    $includeArgs = @(
        ('/I"{0}"' -f (Join-Path $work 'src')),
        ('/I"{0}"' -f (Join-Path $work 'include')),
        ('/I"{0}"' -f $dependencyPaths[0]),
        ('/I"{0}"' -f $dependencyPaths[1]),
        ('/I"{0}"' -f $dependencyPaths[2])
    )
    $common = @(
        'cl.exe', '/nologo', '/std:c++17', '/EHsc', '/W4',
        '/DNOMINMAX', '/D_CRT_SECURE_NO_WARNINGS', '/wd4457', '/c'
    ) + $includeArgs

    $overrideCommand = @(
        'call', ('"{0}"' -f $vsDevCmd), '-arch=amd64', '-host_arch=amd64', '>', 'nul', '&&'
    ) + $common + @(
        '/WX',
        ('/Fo"{0}"' -f (Join-Path $objectRoot 'd3d11_shader_override.obj')),
        ('"{0}"' -f (Join-Path $work 'src\d3d11\d3d11_shader_override.cpp'))
    )
    & $env:ComSpec /d /s /c ($overrideCommand -join ' ')
    if ($LASTEXITCODE -ne 0) {
        throw "Patched override source failed strict MSVC compilation (exit code $LASTEXITCODE)"
    }

    $deviceCommand = @(
        'call', ('"{0}"' -f $vsDevCmd), '-arch=amd64', '-host_arch=amd64', '>', 'nul', '&&'
    ) + $common + @(
        ('/Fo"{0}"' -f (Join-Path $objectRoot 'd3d11_device.obj')),
        ('"{0}"' -f (Join-Path $work 'src\d3d11\d3d11_device.cpp'))
    )
    & $env:ComSpec /d /s /c ($deviceCommand -join ' ')
    if ($LASTEXITCODE -ne 0) {
        throw "Patched D3D11 device source failed MSVC syntax compilation (exit code $LASTEXITCODE)"
    }

    $loaderTestSource = Join-Path $root 'tools\Test-DxvkD3D11OverrideLoader.cpp'
    $loaderTestExe = Join-Path $objectRoot 'Test-DxvkD3D11OverrideLoader.exe'
    $loaderFixture = Join-Path $work 'test-loader-fixture'
    $loaderTestCommand = @(
        'call', ('"{0}"' -f $vsDevCmd), '-arch=amd64', '-host_arch=amd64', '>', 'nul', '&&',
        'cl.exe', '/nologo', '/std:c++17', '/EHsc', '/W4', '/WX',
        '/DNOMINMAX', '/D_CRT_SECURE_NO_WARNINGS'
    ) + $includeArgs + @(
        ('"{0}"' -f $loaderTestSource),
        ('"{0}"' -f (Join-Path $objectRoot 'd3d11_shader_override.obj')),
        ('/Fe:"{0}"' -f $loaderTestExe)
    )
    & $env:ComSpec /d /s /c ($loaderTestCommand -join ' ')
    if ($LASTEXITCODE -ne 0) {
        throw "Patched override loader runtime test failed to compile (exit code $LASTEXITCODE)"
    }

    & $loaderTestExe $loaderFixture
    if ($LASTEXITCODE -ne 0) {
        throw "Patched override loader runtime test failed (exit code $LASTEXITCODE)"
    }

    Write-Host "PASS: DXVK patch cleanly applies to $revision."
    Write-Host 'PASS: override loader compiles with strict warnings, passes concurrent cache tests, and patched D3D11 device compiles.'
}
finally {
    if (Test-Path -LiteralPath $work) {
        $resolvedWork = [IO.Path]::GetFullPath($work)
        $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
        $leaf = Split-Path -Leaf $resolvedWork
        if (-not $resolvedWork.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -or
            -not $leaf.StartsWith('ue4fx-dxvk-patch-test-', [StringComparison]::Ordinal)) {
            throw "Refusing to remove unexpected test path: $resolvedWork"
        }
        Remove-Item -LiteralPath $resolvedWork -Recurse -Force
    }
}
