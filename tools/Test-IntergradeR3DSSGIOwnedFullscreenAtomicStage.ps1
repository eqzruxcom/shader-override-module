[CmdletBinding()]
param(
    [string]$MatrixRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-isolation-matrix'),
    [string]$NativeWin64 = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$workspace=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$root=Join-Path $workspace ('artifacts\.agent2-r3d-ssgi-owned-atomic-'+[Guid]::NewGuid().ToString('N'))
$mods=Join-Path $root 'Mods';$backup=Join-Path $root 'Backups';$baseline=Join-Path $root 'baseline.json';$log=Join-Path $root 'd3d11_log.txt';$passed=$false
try {
    [IO.Directory]::CreateDirectory($mods)|Out-Null
    Get-ChildItem -LiteralPath (Join-Path $MatrixRoot '06-zero-composite-no-depth\Mods') -File | ForEach-Object {[IO.File]::Copy($_.FullName,(Join-Path $mods $_.Name),$false)}
    foreach($relative in @('Mods\ContactShadows.ini','ShaderFixes\08bb8764f1840179-cs.txt','ShaderFixes\0e97888f9a8767da-cs.txt','ShaderFixes\5a9fbefe0ab6f815-cs.txt','ShaderFixes\62b33a2d1e505241-cs.txt','ShaderFixes\c30cdc8365df9840-cs.txt')){
        $destination=Join-Path $root $relative;[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))|Out-Null;[IO.File]::Copy((Join-Path $NativeWin64 $relative),$destination,$false)
    }
    [IO.File]::WriteAllText($log,'',[Text.UTF8Encoding]::new($false))
    $before=@(Get-ChildItem -LiteralPath $mods -File|Sort-Object Name|ForEach-Object{[ordered]@{name=$_.Name;hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash}})
    function Get-Process{[CmdletBinding(DefaultParameterSetName='Name')]param([Parameter(ParameterSetName='Name')][string]$Name,[Parameter(ParameterSetName='Id')][int]$Id)[pscustomobject]@{Id=4242;Path='C:\fixture\ff7remake_.exe';Responding=$true}}
    $stage=& (Join-Path $PSScriptRoot 'Stage-IntergradeR3DSSGIOwnedFullscreenZeroWithBaseline.ps1') -TargetModsDirectory $mods -BackupRoot $backup -BaselineOutputPath $baseline -AcknowledgeDiagnosticOnly -Confirm:$false
    if($stage.Status-ne'staged-and-baselined'-or$stage.LiveFiles-ne8-or$stage.ProtectedFiles-ne6-or-not(Test-Path -LiteralPath $baseline)){throw'Atomic stage/baseline success path failed.'}
    $captured=Get-Content -Raw -LiteralPath $baseline|ConvertFrom-Json
    if($captured.log.byteOffset-ne0-or@($captured.liveFiles).Count-ne8){throw'Atomic baseline content is invalid.'}
    $null=& (Join-Path $PSScriptRoot 'Restore-IntergradeR3DSSGIOwnedFullscreenZero.ps1') -ReceiptPath $stage.Receipt -Confirm:$false
    $restored=@(Get-ChildItem -LiteralPath $mods -File|Sort-Object Name|ForEach-Object{[ordered]@{name=$_.Name;hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash}})
    if(($before|ConvertTo-Json -Compress)-ne($restored|ConvertTo-Json -Compress)){throw'Success-path rollback was not exact.'}

    Remove-Item -LiteralPath $log -Force
    $failedAsExpected=$false
    try{$null=& (Join-Path $PSScriptRoot 'Stage-IntergradeR3DSSGIOwnedFullscreenZeroWithBaseline.ps1') -TargetModsDirectory $mods -BackupRoot $backup -BaselineOutputPath $baseline -AcknowledgeDiagnosticOnly -Confirm:$false}
    catch{if($_.Exception.Message -match 'restored automatically'){$failedAsExpected=$true}else{throw}}
    if(-not$failedAsExpected){throw'Missing-log baseline failure did not trigger automatic rollback.'}
    $afterFailure=@(Get-ChildItem -LiteralPath $mods -File|Sort-Object Name|ForEach-Object{[ordered]@{name=$_.Name;hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash}})
    if(($before|ConvertTo-Json -Compress)-ne($afterFailure|ConvertTo-Json -Compress)){throw'Baseline-failure rollback was not exact.'}
    $passed=$true
    [pscustomobject]@{Result='pass';AtomicStageAndBaseline=$true;SuccessRollbackExact=$true;BaselineFailureAutoRollback=$true;FilesRestored=$afterFailure.Count;F10='unbound';RealGameFilesModified=$false}
}finally{
    if(Test-Path -LiteralPath $root -PathType Container){$resolved=[IO.Path]::GetFullPath($root).TrimEnd('\');if(-not$resolved.StartsWith((Join-Path $workspace 'artifacts\.agent2-r3d-ssgi-owned-atomic-'),[StringComparison]::OrdinalIgnoreCase)){throw"Unsafe fixture cleanup: $resolved"};Remove-Item -LiteralPath $resolved -Recurse -Force}
    if(-not$passed-and$Error.Count-eq0){throw'Atomic-stage fixture did not complete.'}
}
