[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\agent2-r3d-ssgi-live-reload-checker-test.json'),
    [string]$LiveModsDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\Mods'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$stager = Join-Path $root 'tools\Stage-IntergradeR3DSSGIF2Standalone.ps1'
$baselineTool = Join-Path $root 'tools\New-IntergradeR3DSSGIF2StandaloneReloadBaseline.ps1'
$statusTool = Join-Path $root 'tools\Get-IntergradeR3DSSGIF2StandaloneReloadStatus.ps1'
$packRoot = Join-Path $root 'artifacts\agent2-r3d-ssgi-f2-standalone-pack'
$manifest = Join-Path $packRoot 'manifest.json'
$owner = Join-Path $root 'runtime\Intergrade\Mods\RebirthEffectsDX11.ini'
$testBase = Join-Path $root 'artifacts\agent2-r3d-ssgi-reload-checker-test'
$runRoot = Join-Path $testBase ([Guid]::NewGuid().ToString('N'))
$win64 = Join-Path $runRoot 'Game\End\Binaries\Win64'
$mods = Join-Path $win64 'Mods'
$backups = Join-Path $runRoot 'backups'
$statePath = Join-Path $backups 'active-state.json'
$baselinePath = Join-Path $runRoot 'baseline.json'
$statusPath = Join-Path $runRoot 'status.json'
$logPath = Join-Path $win64 'd3d11_log.txt'
[IO.Directory]::CreateDirectory($mods) | Out-Null

function Get-TreeHashes([string]$Path) {
    $map = [ordered]@{}
    foreach ($file in Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName) {
        $map[[IO.Path]::GetRelativePath($Path,$file.FullName)] = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
    }
    $map
}

function Assert-MapsEqual([Collections.IDictionary]$Expected,[Collections.IDictionary]$Actual,[string]$Label) {
    if ([string]::Join([Environment]::NewLine,$Expected.Keys) -cne [string]::Join([Environment]::NewLine,$Actual.Keys)) {
        throw "$Label inventory changed."
    }
    foreach ($key in $Expected.Keys) {
        if ($Expected[$key] -ne $Actual[$key]) { throw "$Label changed: $key" }
    }
}

function Reset-Log() {
    [IO.File]::WriteAllText($logPath,('startup'+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
}

function Append-Lines([string[]]$Lines) {
    $text = [string]::Join([Environment]::NewLine,$Lines) + [Environment]::NewLine
    [IO.File]::AppendAllText($logPath,$text,[Text.UTF8Encoding]::new($false))
}

[IO.File]::Copy($owner,(Join-Path $mods 'RebirthEffectsDX11.ini.disabled'),$false)
$lf = [char]10
$generated = '; Obsolete final-scene/fog comparison removed.' + $lf +
    '; Page Down is reserved for the generated per-shader injected-code master A/B.' + $lf +
    '; No runtime binding is intentionally declared here.' + $lf
[IO.File]::WriteAllText((Join-Path $mods 'UE4EffectsGenerated.ini'),$generated,[Text.UTF8Encoding]::new($false))
Reset-Log

$liveAvailable = Test-Path -LiteralPath $LiveModsDirectory -PathType Container
$liveBefore = if ($liveAvailable) { Get-TreeHashes $LiveModsDirectory } else { $null }
$hostPath = (Get-Process -Id $PID).Path
$child = Start-Process -FilePath $hostPath -ArgumentList @('-NoProfile','-Command','Start-Sleep -Seconds 60') -PassThru -WindowStyle Hidden
$classifications = [Collections.Generic.List[string]]::new()
try {
    $stage = & $stager -Action Stage -PackManifest $manifest -TargetModsDirectory $mods -BackupRoot $backups -AcknowledgeOfflineCandidate -Confirm:$false
    if ($stage.Status -ne 'staged' -or $stage.Files -ne 7) { throw 'Reload-checker fixture did not stage.' }

    $baseline = & $baselineTool -TargetModsDirectory $mods -StageStatePath $statePath -PackManifest $manifest -OutputPath $baselinePath -ProcessId $child.Id
    if ($baseline.Result -ne 'captured-before-F10-reload' -or $baseline.InstalledFiles -ne 7 -or $baseline.ByteOffset -le 0) {
        throw 'Reload baseline did not bind the exact staged fixture.'
    }
    $pending = & $statusTool -BaselinePath $baselinePath -OutputPath $statusPath
    if ($pending.Classification -ne 'pending-F10' -or $pending.AppendedBytes -ne 0) { throw 'Reload checker did not remain pending before F10.' }
    $classifications.Add([string]$pending.Classification)

    $customSections = @(
        'Agent2R3DSSGITrace','Agent2R3DSSGIDenoise16','Agent2R3DSSGIDenoise8',
        'Agent2R3DSSGIDenoise4','Agent2R3DSSGIDenoise2','Agent2R3DSSGIComposite'
    )
    $shaderFiles = @(
        'Agent2R3DSSGITraceE2AA_ps.hlsl','Agent2R3DSSGIDenoise16_ps.hlsl',
        'Agent2R3DSSGIDenoise8_ps.hlsl','Agent2R3DSSGIDenoise4_ps.hlsl',
        'Agent2R3DSSGIDenoise2_ps.hlsl','Agent2R3DSSGICompositeE2AA_ps.hlsl'
    )
    $completeLines = [Collections.Generic.List[string]]::new()
    $completeLines.Add('> d3dx.ini reloaded')
    $completeLines.Add('[Key\Mods\Agent2R3DSSGITest.ini\Agent2R3DSSGITest]')
    foreach ($name in $customSections) { $completeLines.Add("[CustomShader\Mods\Agent2R3DSSGITest.ini\$name]") }
    foreach ($name in $shaderFiles) { $completeLines.Add("  ps=$name") }
    $completeLines.Add('[ShaderOverride\Mods\Agent2R3DSSGITest.ini\Agent2R3DSSGIF2Test]')
    $completeLines.Add('Hash = e2aa1c8cb39e0a55')
    $completeLines.Add('> successfully reloaded shaders from ShaderFixes')
    Append-Lines @($completeLines)
    $pass = & $statusTool -BaselinePath $baselinePath -OutputPath $statusPath
    if ($pass.Classification -ne 'passed-parser-and-six-custom-HLSL-compile-clean' -or
        $pass.CustomSections -ne 6 -or $pass.ShaderEntries -ne 6 -or
        -not $pass.KeyParsed -or -not $pass.OverrideParsed -or $pass.ErrorLines -ne 0) {
        throw 'Reload checker did not accept the complete clean six-pass fixture.'
    }
    $classifications.Add([string]$pass.Classification)

    $trace = Join-Path $mods 'Agent2R3DSSGITraceE2AA_ps.hlsl'
    [IO.File]::AppendAllText($trace,'// drift',[Text.UTF8Encoding]::new($false))
    $drift = & $statusTool -BaselinePath $baselinePath -OutputPath $statusPath
    if ($drift.Classification -ne 'failed-live-or-receipt-hash-drift') { throw 'Reload checker accepted payload drift.' }
    $classifications.Add([string]$drift.Classification)
    [IO.File]::Copy((Join-Path $packRoot 'Mods\Agent2R3DSSGITraceE2AA_ps.hlsl'),$trace,$true)

    Reset-Log
    Append-Lines @('> d3dx.ini reloaded','[ShaderOverride\Mods\Agent2R3DSSGITest.ini\Agent2R3DSSGIF2Test]','Hash = e2aa1c8cb39e0a55','> successfully reloaded shaders from ShaderFixes')
    $missingKey = & $statusTool -BaselinePath $baselinePath -OutputPath $statusPath
    if ($missingKey.Classification -ne 'failed-F2-key-not-parsed') { throw 'Reload checker accepted a missing F2 key.' }
    $classifications.Add([string]$missingKey.Classification)

    Reset-Log
    $missingCustomLines = @('> d3dx.ini reloaded','[Key\Mods\Agent2R3DSSGITest.ini\Agent2R3DSSGITest]','[ShaderOverride\Mods\Agent2R3DSSGITest.ini\Agent2R3DSSGIF2Test]','Hash = e2aa1c8cb39e0a55','> successfully reloaded shaders from ShaderFixes')
    Append-Lines $missingCustomLines
    $missingCustom = & $statusTool -BaselinePath $baselinePath -OutputPath $statusPath
    if ($missingCustom.Classification -ne 'failed-six-custom-sections-incomplete') { throw 'Reload checker accepted missing CustomShader sections.' }
    $classifications.Add([string]$missingCustom.Classification)

    Reset-Log
    $missingShaderLines = [Collections.Generic.List[string]]::new()
    $missingShaderLines.Add('> d3dx.ini reloaded')
    $missingShaderLines.Add('[Key\Mods\Agent2R3DSSGITest.ini\Agent2R3DSSGITest]')
    foreach ($name in $customSections) { $missingShaderLines.Add("[CustomShader\Mods\Agent2R3DSSGITest.ini\$name]") }
    $missingShaderLines.Add('[ShaderOverride\Mods\Agent2R3DSSGITest.ini\Agent2R3DSSGIF2Test]')
    $missingShaderLines.Add('Hash = e2aa1c8cb39e0a55')
    $missingShaderLines.Add('> successfully reloaded shaders from ShaderFixes')
    Append-Lines @($missingShaderLines)
    $missingShader = & $statusTool -BaselinePath $baselinePath -OutputPath $statusPath
    if ($missingShader.Classification -ne 'failed-six-custom-HLSL-entries-incomplete') { throw 'Reload checker accepted missing custom HLSL entries.' }
    $classifications.Add([string]$missingShader.Classification)

    Reset-Log
    Append-Lines @($completeLines)
    Append-Lines @('Error compiling custom shader')
    $compileError = & $statusTool -BaselinePath $baselinePath -OutputPath $statusPath
    if ($compileError.Classification -ne 'failed-parser-or-custom-shader-compile' -or $compileError.ErrorLines -lt 1) {
        throw 'Reload checker accepted a custom shader compiler error.'
    }
    $classifications.Add([string]$compileError.Classification)

    [IO.File]::WriteAllText($logPath,'x',[Text.UTF8Encoding]::new($false))
    $truncated = & $statusTool -BaselinePath $baselinePath -OutputPath $statusPath
    if ($truncated.Classification -ne 'process-or-log-restarted-rebaseline-required') { throw 'Reload checker accepted a truncated log.' }
    $classifications.Add([string]$truncated.Classification)

    if ($liveAvailable) { Assert-MapsEqual $liveBefore (Get-TreeHashes $LiveModsDirectory) 'Live Mods directory' }
    $report = [ordered]@{
        schemaVersion = 1
        result = 'pass'
        packageId = 'agent2-r3d-ssgi-f2-standalone'
        testedClassifications = @($classifications)
        expectedCustomSections = 6
        expectedShaderEntries = 6
        exactPayloadAndReceiptHashGate = $true
        processAndAppendOnlyLogGate = $true
        compilerErrorGate = $true
        liveDirectoryHashChecked = $liveAvailable
        liveGameDirectoryTouched = $false
        visualResult = 'not inferred from parser status'
        performanceVerified = $false
        runtimeEligible = $false
    }
    $outputFull = [IO.Path]::GetFullPath($OutputPath)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull)) | Out-Null
    [IO.File]::WriteAllText($outputFull,(($report|ConvertTo-Json -Depth 10)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
    [pscustomobject]@{Result='pass';Classifications=$classifications.Count;CustomSections=6;ShaderEntries=6;LiveDirectoryHashChecked=$liveAvailable;LiveGameDirectoryTouched=$false;RuntimeEligible=$false;Output=$outputFull}
}
finally {
    if (-not $child.HasExited) { Stop-Process -Id $child.Id -Force }
    if (Test-Path -LiteralPath $runRoot -PathType Container) {
        [IO.Directory]::Delete([IO.Path]::GetFullPath($runRoot),$true)
    }
}
