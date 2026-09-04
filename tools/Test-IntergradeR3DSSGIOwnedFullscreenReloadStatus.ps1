[CmdletBinding()]
param(
    [string]$PackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-zero-pack'),
    [string]$NativeWin64 = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = Join-Path $workspace 'artifacts'
$fixture = Join-Path $artifacts ('.agent2-r3d-ssgi-owned-reload-' + [Guid]::NewGuid().ToString('N'))
$mods = Join-Path $fixture 'Mods'; $baseline = Join-Path $fixture 'baseline.json'; $status = Join-Path $fixture 'status.json'; $log = Join-Path $fixture 'd3d11_log.txt'; $contactReport = Join-Path $fixture 'contact-install-report.json'
$passed=$false
try {
    [IO.Directory]::CreateDirectory($mods)|Out-Null
    Get-ChildItem -LiteralPath (Join-Path $PackRoot 'Mods') -File | ForEach-Object { [IO.File]::Copy($_.FullName,(Join-Path $mods $_.Name),$false) }
    foreach ($relative in @('Mods\ContactShadows.ini')) {
        $source=Join-Path $NativeWin64 $relative; $destination=Join-Path $fixture $relative
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))|Out-Null
        [IO.File]::Copy($source,$destination,$false)
    }
    $contactSha=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $mods 'ContactShadows.ini')).Hash
    $backupFiles=@('08bb8764f1840179','0e97888f9a8767da','5a9fbefe0ab6f815','62b33a2d1e505241','c30cdc8365df9840')|ForEach-Object{[ordered]@{path="ShaderFixes/$($_)-cs.txt";sha256=('A'*64)}}
    [IO.File]::WriteAllText($contactReport,(([ordered]@{schemaVersion=2;kind='ff7-remake-accepted-contact-family-live-install';installed=$true;liveIni=(Join-Path $mods 'ContactShadows.ini');liveIniSha256=$contactSha;backupFiles=@($backupFiles);failures=@()}|ConvertTo-Json -Depth 6)+"`r`n"),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($log,'',[Text.UTF8Encoding]::new($false))
    function Get-Process { [CmdletBinding(DefaultParameterSetName='Name')]param([Parameter(ParameterSetName='Name')][string]$Name,[Parameter(ParameterSetName='Id')][int]$Id)[pscustomobject]@{Id=4242;Path='C:\fixture\ff7remake_.exe';Responding=$true} }
    $capture=& (Join-Path $PSScriptRoot 'New-IntergradeR3DSSGIOwnedFullscreenReloadBaseline.ps1') -TargetModsDirectory $mods -PackRoot $PackRoot -OutputPath $baseline -ContactInstallReportPath $contactReport
    if($capture.Status-ne'captured-before-F10'-or$capture.LiveFiles-ne8-or$capture.ProtectedFiles-ne1-or$capture.ProtectedAbsentFiles-ne5-or$capture.ModF10Claims-ne0){throw'Owned fixture baseline capture failed.'}
    $pending=& (Join-Path $PSScriptRoot 'Get-IntergradeR3DSSGIOwnedFullscreenReloadStatus.ps1') -BaselinePath $baseline -OutputPath $status
    if($pending.Classification-ne'pending-F10'-or$pending.LiveFileDrift-ne0-or$pending.ErrorLines-ne0){throw'Owned fixture pending classification failed.'}
    $custom=@('Agent2R3DSSGITrace','Agent2R3DSSGIDenoise16','Agent2R3DSSGIDenoise8','Agent2R3DSSGIDenoise4','Agent2R3DSSGIDenoise2','Agent2R3DSSGIComposite')
    $shaders=@(
        @{stage='ps';name='Agent2R3DSSGITraceE2AA_ps.hlsl'},@{stage='ps';name='Agent2R3DSSGIDenoise16_ps.hlsl'},
        @{stage='ps';name='Agent2R3DSSGIDenoise8_ps.hlsl'},@{stage='ps';name='Agent2R3DSSGIDenoise4_ps.hlsl'},
        @{stage='ps';name='Agent2R3DSSGIDenoise2_ps.hlsl'},@{stage='ps';name='Agent2R3DSSGICompositeE2AA_ps.hlsl'},
        @{stage='vs';name='Agent2R3DSSGIFullscreen_vs.hlsl'})
    $lines=[Collections.Generic.List[string]]::new();$lines.Add('> d3dx.ini reloaded');$lines.Add('[Key\Mods\Agent2R3DSSGITest.ini\Agent2R3DSSGITest]')
    foreach($name in $custom){$lines.Add("[CustomShader\Mods\Agent2R3DSSGITest.ini\$name]")}
    foreach($shader in $shaders){$lines.Add("$($shader.stage) = $($shader.name)")}
    $lines.Add('[ShaderOverride\Mods\Agent2R3DSSGITest.ini\Agent2R3DSSGIF2Test]');$lines.Add('Hash = e2aa1c8cb39e0a55');$lines.Add('> successfully reloaded shaders from ShaderFixes')
    [IO.File]::AppendAllText($log,(($lines-join"`r`n")+"`r`n"),[Text.UTF8Encoding]::new($false))
    $clean=& (Join-Path $PSScriptRoot 'Get-IntergradeR3DSSGIOwnedFullscreenReloadStatus.ps1') -BaselinePath $baseline -OutputPath $status
    if($clean.Classification-ne'passed-parser-and-seven-custom-HLSL-compile-clean'-or$clean.CustomSections-ne6-or$clean.ShaderEntries-ne7-or$clean.ErrorLines-ne0){throw'Owned fixture clean reload failed.'}
    [IO.Directory]::CreateDirectory((Join-Path $fixture 'ShaderFixes'))|Out-Null
    [IO.File]::WriteAllText((Join-Path $fixture 'ShaderFixes\08bb8764f1840179-cs.txt'),'unexpected explicit replacement',[Text.UTF8Encoding]::new($false))
    $returnedExplicit=& (Join-Path $PSScriptRoot 'Get-IntergradeR3DSSGIOwnedFullscreenReloadStatus.ps1') -BaselinePath $baseline -OutputPath $status
    if($returnedExplicit.Classification-ne'failed-file-hash-drift'-or$returnedExplicit.UnexpectedPresentFiles-ne1){throw'Owned fixture did not reject a returned explicit contact replacement.'}
    Remove-Item -LiteralPath (Join-Path $fixture 'ShaderFixes\08bb8764f1840179-cs.txt') -Force
    [IO.File]::AppendAllText($log,"error compiling custom shader Agent2R3DSSGIFullscreen`r`n",[Text.UTF8Encoding]::new($false))
    $compileFailure=& (Join-Path $PSScriptRoot 'Get-IntergradeR3DSSGIOwnedFullscreenReloadStatus.ps1') -BaselinePath $baseline -OutputPath $status
    if($compileFailure.Classification-ne'failed-parser-or-custom-shader-compile'-or$compileFailure.ErrorLines-lt1){throw'Owned fixture compile error was not rejected.'}
    [IO.File]::AppendAllText((Join-Path $mods 'Agent2R3DSSGIFullscreen_vs.hlsl'),"// drift`r`n",[Text.UTF8Encoding]::new($false))
    $drift=& (Join-Path $PSScriptRoot 'Get-IntergradeR3DSSGIOwnedFullscreenReloadStatus.ps1') -BaselinePath $baseline -OutputPath $status
    if($drift.Classification-ne'failed-file-hash-drift'-or$drift.LiveFileDrift-ne1){throw'Owned fixture VS drift was not rejected.'}
    $passed=$true
    [pscustomobject]@{Result='pass';PendingF10=$true;CleanSixSectionsSevenShaders=$true;ReturnedExplicitContactRejected=$true;CompileErrorRejected=$true;VertexShaderDriftRejected=$true;F10='unbound';RealGameFilesModified=$false}
} finally {
    if(Test-Path -LiteralPath $fixture -PathType Container){$resolved=[IO.Path]::GetFullPath($fixture).TrimEnd('\');if(-not $resolved.StartsWith($artifacts.TrimEnd('\')+'\.agent2-r3d-ssgi-owned-reload-',[StringComparison]::OrdinalIgnoreCase)){throw"Unsafe fixture cleanup: $resolved"};Remove-Item -LiteralPath $resolved -Recurse -Force}
    if(-not$passed-and$Error.Count-eq0){throw'Owned reload-status fixture did not complete.'}
}
