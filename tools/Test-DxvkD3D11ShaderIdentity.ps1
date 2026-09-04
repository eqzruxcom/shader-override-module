[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $root 'src\Backends\DxvkD3D11'
$build = Join-Path $root 'artifacts\dxvk-d3d11-shader-identity-test'
$replacementRoot = Join-Path $build ('replacement-fixture-' + [guid]::NewGuid().ToString('N'))
$vsDevCmd = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat'

if (-not (Test-Path -LiteralPath $vsDevCmd -PathType Leaf)) {
    throw "Visual Studio Build Tools were not found at $vsDevCmd"
}

New-Item -ItemType Directory -Force -Path $build | Out-Null
New-Item -ItemType Directory -Force -Path $replacementRoot | Out-Null

$sourceFiles = @(
    (Join-Path $backend 'ShaderIdentity.cpp'),
    (Join-Path $backend 'ShaderReplacementResolver.cpp'),
    (Join-Path $root 'tools\Test-DxvkD3D11ShaderIdentity.cpp')
)
$exe = Join-Path $build 'Test-DxvkD3D11ShaderIdentity.exe'

$compileArgs = @(
    'call', ('"{0}"' -f $vsDevCmd), '-arch=amd64', '-host_arch=amd64', '>', 'nul', '&&',
    'cl.exe', '/nologo', '/std:c++17', '/EHsc', '/W4', '/WX',
    ('/I"{0}"' -f $backend)
)
$compileArgs += $sourceFiles | ForEach-Object { '"{0}"' -f $_ }
$compileArgs += ('/Fe:"{0}"' -f $exe)

$compileCommand = $compileArgs -join ' '
& $env:ComSpec /d /s /c $compileCommand
if ($LASTEXITCODE -ne 0) {
    throw "C++ compilation failed with exit code $LASTEXITCODE"
}

$fixtures = @(
    @(
        (Join-Path $root 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\dxbc\0fcd2a51d59b6599-vs.bin'),
        'vs',
        '0fcd2a51d59b6599'
    ),
    @(
        (Join-Path $root 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\dxbc\8b1f6ebe443b5615-ps.bin'),
        'ps',
        '8b1f6ebe443b5615'
    ),
    @(
        (Join-Path $root 'artifacts\contact-edge-fade-development-20260831-v1\artifacts\surface-lighting-study-20260830-v3\62b33a2d1e505241-cs.bin'),
        'cs',
        '62b33a2d1e505241'
    )
)

foreach ($fixture in $fixtures) {
    if (-not (Test-Path -LiteralPath $fixture[0] -PathType Leaf)) {
        throw "Missing DXBC fixture: $($fixture[0])"
    }
}

try {
    & $exe @($fixtures[0] + $fixtures[1] + $fixtures[2] + $replacementRoot)
    if ($LASTEXITCODE -ne 0) {
        throw "Shader identity test failed with exit code $LASTEXITCODE"
    }
}
finally {
    if (Test-Path -LiteralPath $replacementRoot) {
        $resolved = [IO.Path]::GetFullPath($replacementRoot)
        $resolvedBuild = [IO.Path]::GetFullPath($build)
        $leaf = Split-Path -Leaf $resolved
        if (-not $resolved.StartsWith($resolvedBuild, [StringComparison]::OrdinalIgnoreCase) -or
            -not $leaf.StartsWith('replacement-fixture-', [StringComparison]::Ordinal)) {
            throw "Refusing to remove unexpected resolver fixture: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

Write-Host 'PASS: exact 3Dmigoto DXBC identity is ready for DXVK D3D11 integration.'
