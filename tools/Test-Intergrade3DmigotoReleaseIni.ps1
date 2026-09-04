[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$generator = Join-Path $root 'tools\New-Intergrade3DmigotoReleaseIni.ps1'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$work = Join-Path $tempRoot ('ue4fx-release-ini-test-' + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $source = Join-Path $work 'source.ini'
    $output = Join-Path $work 'output'
    $fixture = @"
[System]
calls = 1
debug = 0
hunting = 2
verbose_overlay = 1
force_stereo = 0
automatic_mode = 0
allow_check_interface = 1
dump_usage = 1

[ShaderOverrideKeepMe]
hash = 8b1f6ebe443b5615
run = CommandListKeepMe
"@
    [IO.File]::WriteAllText($source, $fixture, [Text.UTF8Encoding]::new($false))

    & $generator -SourcePath $source -OutputDirectory $output
    if (-not $?) {
        throw 'Release INI generator failed'
    }

    $candidate = [IO.File]::ReadAllText((Join-Path $output 'd3dx.ini'))
    foreach ($key in @('calls', 'hunting', 'verbose_overlay', 'dump_usage')) {
        if ($candidate -notmatch "(?im)^$key[ \t]*=[ \t]*0[ \t]*$") {
            throw "Release candidate did not disable $key"
        }
    }
    foreach ($setting in @('force_stereo = 0', 'automatic_mode = 0', 'allow_check_interface = 1')) {
        if ($candidate -notmatch "(?im)^$([regex]::Escape($setting))[ \t]*$") {
            throw "Release candidate did not preserve $setting"
        }
    }
    foreach ($line in @('[ShaderOverrideKeepMe]', 'hash = 8b1f6ebe443b5615', 'run = CommandListKeepMe')) {
        if (-not $candidate.Contains($line)) {
            throw "Release candidate lost mod content: $line"
        }
    }

    $manifest = Get-Content -Raw -LiteralPath (Join-Path $output 'manifest.json') | ConvertFrom-Json
    if ($manifest.installed -ne $false -or $manifest.changedSettings.Count -ne 4) {
        throw 'Release candidate manifest does not record an offline four-setting change'
    }

    Write-Host 'PASS: release candidate changes only runtime diagnostics and preserves mod/stereo/interface settings.'
}
finally {
    if (Test-Path -LiteralPath $work) {
        $resolvedWork = [IO.Path]::GetFullPath($work)
        $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
        $leaf = Split-Path -Leaf $resolvedWork
        if (-not $resolvedWork.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -or
            -not $leaf.StartsWith('ue4fx-release-ini-test-', [StringComparison]::Ordinal)) {
            throw "Refusing to remove unexpected test path: $resolvedWork"
        }
        Remove-Item -LiteralPath $resolvedWork -Recurse -Force
    }
}
