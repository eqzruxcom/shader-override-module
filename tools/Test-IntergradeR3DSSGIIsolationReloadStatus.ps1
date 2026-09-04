[CmdletBinding()]
param(
    [string]$MatrixRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-isolation-matrix'),
    [string]$NativeWin64 = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = Join-Path $workspace 'artifacts'
$fixture = Join-Path $artifacts ('.agent2-r3d-ssgi-isolation-reload-' + [Guid]::NewGuid().ToString('N'))
$mods = Join-Path $fixture 'Mods'
$baseline = Join-Path $fixture 'baseline.json'
$status = Join-Path $fixture 'status.json'
$log = Join-Path $fixture 'd3d11_log.txt'
$variant = '02-scene-copy-only'
$passed = $false

try {
    $sourceMods = Join-Path ([IO.Path]::GetFullPath($MatrixRoot)) "$variant\Mods"
    if (-not (Test-Path -LiteralPath $sourceMods -PathType Container)) { throw 'Isolation matrix fixture source is missing.' }
    [IO.Directory]::CreateDirectory($mods) | Out-Null
    Get-ChildItem -LiteralPath $sourceMods -File | ForEach-Object {
        [IO.File]::Copy($_.FullName,(Join-Path $mods $_.Name),$false)
    }

    $protected = @(
        'Mods\ContactShadows.ini',
        'ShaderFixes\08bb8764f1840179-cs.txt',
        'ShaderFixes\0e97888f9a8767da-cs.txt',
        'ShaderFixes\5a9fbefe0ab6f815-cs.txt',
        'ShaderFixes\62b33a2d1e505241-cs.txt',
        'ShaderFixes\c30cdc8365df9840-cs.txt'
    )
    foreach ($relative in $protected) {
        $source = Join-Path $NativeWin64 $relative
        $destination = Join-Path $fixture $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Native fixture input is missing: $relative" }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
        [IO.File]::Copy($source,$destination,$false)
    }
    [IO.File]::WriteAllText($log,'',[Text.UTF8Encoding]::new($false))

    function Get-Process {
        [CmdletBinding(DefaultParameterSetName='Name')]
        param(
            [Parameter(ParameterSetName='Name')][string]$Name,
            [Parameter(ParameterSetName='Id')][int]$Id
        )
        [pscustomobject]@{Id=4242;Path='C:\fixture\ff7remake_.exe';Responding=$true}
    }

    $capture = & (Join-Path $PSScriptRoot 'New-IntergradeR3DSSGIIsolationReloadBaseline.ps1') `
        -Variant $variant -TargetModsDirectory $mods -MatrixRoot $MatrixRoot -OutputPath $baseline
    if ($capture.Status -ne 'captured-before-F10' -or $capture.LiveFiles -ne 7 -or $capture.ProtectedFiles -ne 6) {
        throw 'Fixture baseline capture failed.'
    }
    $pending = & (Join-Path $PSScriptRoot 'Get-IntergradeR3DSSGIIsolationReloadStatus.ps1') `
        -BaselinePath $baseline -OutputPath $status
    if ($pending.Classification -ne 'pending-F10' -or $pending.LiveFileDrift -ne 0 -or
        $pending.ProtectedFileDrift -ne 0 -or $pending.ErrorLines -ne 0) {
        throw 'Fixture did not classify the untouched baseline as pending-F10.'
    }

    $custom = @('Agent2R3DSSGITrace','Agent2R3DSSGIDenoise16','Agent2R3DSSGIDenoise8','Agent2R3DSSGIDenoise4','Agent2R3DSSGIDenoise2','Agent2R3DSSGIComposite')
    $shaders = @('Agent2R3DSSGITraceE2AA_ps.hlsl','Agent2R3DSSGIDenoise16_ps.hlsl','Agent2R3DSSGIDenoise8_ps.hlsl','Agent2R3DSSGIDenoise4_ps.hlsl','Agent2R3DSSGIDenoise2_ps.hlsl','Agent2R3DSSGICompositeE2AA_ps.hlsl')
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('> d3dx.ini reloaded')
    $lines.Add('[Key\Mods\Agent2R3DSSGITest.ini\Agent2R3DSSGITest]')
    for ($i=0; $i -lt $custom.Count; $i++) {
        $lines.Add("[CustomShader\Mods\Agent2R3DSSGITest.ini\$($custom[$i])]")
        $lines.Add("ps = $($shaders[$i])")
    }
    $lines.Add('[ShaderOverride\Mods\Agent2R3DSSGITest.ini\Agent2R3DSSGIF2Test]')
    $lines.Add('Hash = e2aa1c8cb39e0a55')
    $lines.Add('> successfully reloaded shaders from ShaderFixes')
    [IO.File]::AppendAllText($log,(($lines -join "`r`n") + "`r`n"),[Text.UTF8Encoding]::new($false))

    $clean = & (Join-Path $PSScriptRoot 'Get-IntergradeR3DSSGIIsolationReloadStatus.ps1') `
        -BaselinePath $baseline -OutputPath $status
    if ($clean.Classification -ne 'passed-parser-and-custom-HLSL-compile-clean' -or
        $clean.CustomSections -ne 6 -or $clean.ShaderEntries -ne 6 -or $clean.ErrorLines -ne 0) {
        throw 'Fixture clean reload was not classified as passing.'
    }

    [IO.File]::AppendAllText($log,"error compiling custom shader Agent2R3DSSGITrace`r`n",[Text.UTF8Encoding]::new($false))
    $compileFailure = & (Join-Path $PSScriptRoot 'Get-IntergradeR3DSSGIIsolationReloadStatus.ps1') `
        -BaselinePath $baseline -OutputPath $status
    if ($compileFailure.Classification -ne 'failed-parser-or-custom-shader-compile' -or
        $compileFailure.ErrorLines -lt 1) { throw 'Fixture compile error was not rejected.' }

    $liveIni = Join-Path $mods 'Agent2R3DSSGITest.ini'
    [IO.File]::AppendAllText($liveIni,"; deliberate drift`r`n",[Text.UTF8Encoding]::new($false))
    $driftFailure = & (Join-Path $PSScriptRoot 'Get-IntergradeR3DSSGIIsolationReloadStatus.ps1') `
        -BaselinePath $baseline -OutputPath $status
    if ($driftFailure.Classification -ne 'failed-file-hash-drift' -or $driftFailure.LiveFileDrift -ne 1) {
        throw 'Fixture live-file drift was not rejected.'
    }

    $passed = $true
    [pscustomobject]@{
        Passed=$true
        PendingF10Classified=$true
        CleanReloadClassified=$true
        CompileErrorRejected=$true
        LiveFileDriftRejected=$true
        RealGameFilesModified=$false
    }
} finally {
    if (Test-Path -LiteralPath $fixture -PathType Container) {
        $resolved = [IO.Path]::GetFullPath($fixture).TrimEnd('\')
        if (-not $resolved.StartsWith($artifacts.TrimEnd('\') + '\.agent2-r3d-ssgi-isolation-reload-',
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing unsafe fixture cleanup: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    if (-not $passed -and $Error.Count -eq 0) { throw 'Reload-status fixture did not complete.' }
}
