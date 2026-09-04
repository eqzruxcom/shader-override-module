[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$caseRoot = Join-Path $repoRoot 'artifacts\scene-post-diagnostic-reload-test'
$gameRoot = Join-Path $caseRoot 'Game'
$liveRoot = Join-Path $gameRoot 'End\Binaries\Win64'
$modsRoot = Join-Path $liveRoot 'Mods'
$generatedRoot = Join-Path $repoRoot 'artifacts\generated-runtime\FF7RemakeIntergradeScenePostReloadTest'
$installPath = Join-Path $caseRoot 'installed.json'
$utf8 = [Text.UTF8Encoding]::new($false)
foreach ($path in @($caseRoot,$generatedRoot)) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
}
[IO.Directory]::CreateDirectory($modsRoot) | Out-Null
[IO.Directory]::CreateDirectory($generatedRoot) | Out-Null
$logPath = Join-Path $liveRoot 'd3d11_log.txt'
$iniPath = Join-Path $modsRoot 'UE4EffectsGenerated.ini'
$shaderPath = Join-Path $modsRoot 'RebirthPostSceneControls_ps.hlsl'
[IO.File]::WriteAllText($logPath, "startup`r`n", $utf8)
[IO.File]::WriteAllText($iniPath, "[Constants]`r`nx101 = 1.0`r`nw101 = 0.0`r`n", $utf8)
[IO.File]::WriteAllText($shaderPath, "float4 main() : SV_Target { return 0; }`r`n", $utf8)
$adapterId = 'FF7RemakeIntergradeScenePostDiagnostic'
$generated = [ordered]@{
    schemaVersion=1;adapterId=$adapterId;diagnosticOnly=$true;failClosed=$true
    status='neutral-live-parity-pending';licensedRegexDependency=$false
}
[IO.File]::WriteAllText((Join-Path $generatedRoot 'runtime-manifest.json'), ($generated|ConvertTo-Json -Depth 5)+[Environment]::NewLine, $utf8)
$records = foreach ($pair in @(
    [pscustomobject]@{relativePath='Mods/UE4EffectsGenerated.ini';path=$iniPath},
    [pscustomobject]@{relativePath='Mods/RebirthPostSceneControls_ps.hlsl';path=$shaderPath}
)) {
    [ordered]@{relativePath=$pair.relativePath;installedSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $pair.path).Hash;hadOriginal=$false;originalSha256=$null}
}
$installed = [ordered]@{schemaVersion=1;adapterId=$adapterId;targetRoot=$liveRoot;files=@($records)}
[IO.File]::WriteAllText($installPath, ($installed|ConvertTo-Json -Depth 6)+[Environment]::NewLine, $utf8)

$hostPath = (Get-Process -Id $PID).Path
$child = Start-Process -FilePath $hostPath -ArgumentList @('-NoProfile','-Command','Start-Sleep -Seconds 60') -PassThru -WindowStyle Hidden
try {
    $baseline = & (Join-Path $repoRoot 'tools\New-IntergradeScenePostDiagnosticReloadBaseline.ps1') `
        -GeneratedRuntimeDirectory $generatedRoot `
        -InstallManifestPath $installPath `
        -GameRoot $gameRoot `
        -ProcessId $child.Id
    if ($baseline.Result -ne 'captured-before-diagnostic-reload' -or [int]$baseline.ProcessId -ne $child.Id) {
        throw 'Diagnostic reload baseline did not bind the exact target process.'
    }
    $reload = @'
> d3dx.ini reloaded
[Key\Mods\UE4EffectsGenerated.ini\UE4FXFF7RemakeIntergradeTemporalVolume]
[Key\Mods\UE4EffectsGenerated.ini\UE4FXFF7RemakeIntergradeSceneSaturation]
[Key\Mods\UE4EffectsGenerated.ini\UE4FXFF7RemakeIntergradeAmbientOcclusion]
[Key\Mods\UE4EffectsGenerated.ini\UE4FXFF7RemakeIntergradeTonemapAB]
[ShaderOverride\Mods\UE4EffectsGenerated.ini\TemporalVolume]
Hash = ef7fe8d9c4e9ad15
[ShaderOverride\Mods\UE4EffectsGenerated.ini\ScenePost]
Hash = af6cd28a0108a18a
[ShaderOverride\Mods\UE4EffectsGenerated.ini\AmbientOcclusion]
Hash = a77b589dce5822d6
'@ -replace "`n", "`r`n"
    [IO.File]::AppendAllText($logPath, $reload + "`r`n", $utf8)
    $pass = & (Join-Path $repoRoot 'tools\Get-UE4GeneratedRuntimeLiveReloadStatus.ps1') -GeneratedRuntimeDirectory $generatedRoot
    if ($pass.Classification -ne 'passed-live-parser-reload' -or -not $pass.ProcessAlive -or -not $pass.ProcessResponding) {
        throw 'Diagnostic reload verifier did not accept the complete clean reload fixture.'
    }
    [IO.File]::AppendAllText($logPath, "ERROR UE4EffectsGenerated syntax error`r`n", $utf8)
    $failed = & (Join-Path $repoRoot 'tools\Get-UE4GeneratedRuntimeLiveReloadStatus.ps1') -GeneratedRuntimeDirectory $generatedRoot
    if ($failed.Classification -ne 'failed-parser-or-compile-error' -or [int]$failed.ErrorLines -lt 1) {
        throw 'Diagnostic reload verifier accepted a parser-error fixture.'
    }
} finally {
    if (-not $child.HasExited) { Stop-Process -Id $child.Id -Force }
}

Write-Output 'Intergrade scene-post diagnostic reload verifier tests passed.'
