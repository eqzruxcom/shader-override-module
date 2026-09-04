[CmdletBinding()]
param(
    [ValidateSet('reload', 'clearhunt', 'frameanalysis')]
    [string]$Command = 'reload'
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$forkRoot = Join-Path $repositoryRoot 'src\Backends\3DmigotoFork'
$proxyPath = Join-Path $forkRoot 'builds\x64\Release\d3d11.dll'
$compilerPath = Join-Path $forkRoot 'builds\x64\Release\d3dcompiler_47.dll'
$nvapiPath = Join-Path $forkRoot 'builds\x64\Release\nvapi64.dll'
$sourcePath = Join-Path $PSScriptRoot 'RemoteInputHost.cpp'
$controllerPath = Join-Path $repositoryRoot 'tools\FF7-InputController.ahk'
$ahkPath = Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'
$vsDevCmd = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat'
$runRoot = Join-Path $repositoryRoot ('artifacts\remote-input-tests\' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
$hostPath = Join-Path $runRoot 'RemoteInputHost.exe'
$receiptPath = Join-Path $runRoot 'remote-input-receipt.json'
$bindingVirtualKey = switch ($Command) {
    'clearhunt' { 'VK_ADD' }
    'frameanalysis' { 'VK_F8' }
    default { 'VK_F10' }
}
$bindingLine = switch ($Command) {
    'clearhunt' { 'done_hunting = no_modifiers VK_ADD' }
    'frameanalysis' { "analyse_frame = no_modifiers VK_F8`nanalyse_options = mono" }
    default { 'reload_fixes = no_modifiers VK_F10' }
}
$expectedLogMarker = switch ($Command) {
    'clearhunt' { '> Hunting selections cleared' }
    'frameanalysis' { $null }
    default { '> reloading *_replace.txt fixes from ShaderFixes' }
}

foreach ($requiredPath in @($proxyPath, $compilerPath, $nvapiPath, $sourcePath, $controllerPath, $ahkPath, $vsDevCmd)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required path is missing: $requiredPath"
    }
}

New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $runRoot 'ShaderFixes') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $runRoot 'ShaderCache') -Force | Out-Null

$compileLine = 'call "{0}" -arch=x64 -host_arch=x64 -winsdk=10.0.26100.0 >nul && cl /nologo /EHsc /std:c++17 /O2 /FIcwchar "{1}" /Fe:"{2}" d3d11.lib user32.lib' -f $vsDevCmd, $sourcePath, $hostPath
& $env:ComSpec /d /s /c $compileLine
if ($LASTEXITCODE -ne 0) {
    throw "Remote input host compile failed with exit code $LASTEXITCODE"
}

Copy-Item -LiteralPath $proxyPath -Destination $runRoot
Copy-Item -LiteralPath $compilerPath -Destination $runRoot
Copy-Item -LiteralPath $nvapiPath -Destination $runRoot

$configuration = @'
[Logging]
calls = 1
input = 1
debug = 0
unbuffered = 1
crash = 0

[System]
load_library_redirect = 0
check_foreground_window = 1
allow_check_interface = 1
allow_create_device = 1
allow_platform_update = 1

[Device]
upscaling = 0
full_screen = 0
force_stereo = 0

[Stereo]
automatic_mode = 0
create_profile = 0
force_no_nvapi = 1

[Rendering]
shader_hash = 3dmigoto
override_directory = ShaderFixes
cache_directory = ShaderCache
cache_shaders = 0
export_fixed = 0
export_shaders = 0
export_hlsl = 0

[Hunting]
hunting = 2
__REMOTE_INPUT_BINDING__
'@
$configuration = $configuration.Replace('__REMOTE_INPUT_BINDING__', $bindingLine)
[IO.File]::WriteAllText((Join-Path $runRoot 'd3dx.ini'), $configuration, [Text.UTF8Encoding]::new($false))

$startInfo = [Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $hostPath
$startInfo.WorkingDirectory = $runRoot
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$hostProcess = [Diagnostics.Process]::Start($startInfo)

try {
    $readyPath = Join-Path $runRoot 'ready.flag'
    $deadline = [datetime]::UtcNow.AddSeconds(5)
    while (-not (Test-Path -LiteralPath $readyPath)) {
        if ($hostProcess.HasExited) {
            throw "Remote input host exited before ready with code $($hostProcess.ExitCode): $($hostProcess.StandardError.ReadToEnd())"
        }
        if ([datetime]::UtcNow -gt $deadline) {
            throw 'Remote input host did not become ready within five seconds.'
        }
        Start-Sleep -Milliseconds 50
    }

    $ahkArguments = @(
        $controllerPath,
        $Command,
        '--expected-exe', 'RemoteInputHost.exe',
        '--receipt', $receiptPath,
        '--require-ipc'
    )
    $senderInfo = [Diagnostics.ProcessStartInfo]::new()
    $senderInfo.FileName = $ahkPath
    $senderInfo.UseShellExecute = $false
    $senderInfo.CreateNoWindow = $true
    $senderInfo.RedirectStandardOutput = $true
    $senderInfo.RedirectStandardError = $true
    foreach ($argument in $ahkArguments) { [void]$senderInfo.ArgumentList.Add($argument) }

    $sender = [Diagnostics.Process]::Start($senderInfo)
    $senderOutput = $sender.StandardOutput.ReadToEnd()
    $senderError = $sender.StandardError.ReadToEnd()
    $sender.WaitForExit()
    if ($sender.ExitCode -ne 0) {
        throw "Remote input sender failed with code $($sender.ExitCode): $senderError $senderOutput"
    }

    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw 'Remote input sender did not write a receipt.'
    }
    $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json
    if ($receipt.status -ne 'sent' -or $receipt.method -ne 'engine-ipc' -or -not $receipt.acknowledged) {
        throw "Remote input receipt did not prove acknowledged engine IPC: $($receipt | ConvertTo-Json -Compress)"
    }

    $logPath = Join-Path $runRoot 'd3d11_log.txt'
    $deadline = [datetime]::UtcNow.AddSeconds(3)
    do {
        $log = ''
        if (Test-Path -LiteralPath $logPath) {
            $stream = [IO.FileStream]::new($logPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try {
                $reader = [IO.StreamReader]::new($stream)
                try { $log = $reader.ReadToEnd() }
                finally { $reader.Dispose() }
            }
            finally { $stream.Dispose() }
        }
        $frameAnalysisCreated = @(Get-ChildItem -LiteralPath $runRoot -Directory -Filter 'FrameAnalysis-*' -ErrorAction SilentlyContinue).Count -gt 0
        if (($expectedLogMarker -and $log.Contains($expectedLogMarker)) -or (-not $expectedLogMarker -and $frameAnalysisCreated)) { break }
        Start-Sleep -Milliseconds 50
    } while ([datetime]::UtcNow -lt $deadline)

    $frameAnalysisCreated = @(Get-ChildItem -LiteralPath $runRoot -Directory -Filter 'FrameAnalysis-*' -ErrorAction SilentlyContinue).Count -gt 0
    $boundActionObserved = if ($expectedLogMarker) {
        $log.Contains($expectedLogMarker)
    }
    else {
        $frameAnalysisCreated
    }
    if (-not $boundActionObserved) {
        throw "3Dmigoto acknowledged IPC but the $Command callback did not execute."
    }

    [pscustomobject]@{
        Result = 'pass'
        TestedCommand = $Command
        TestedVirtualKey = $bindingVirtualKey
        Delivery = $receipt.method
        AcknowledgedBy3Dmigoto = [bool]$receipt.acknowledged
        BoundActionObserved = [bool]$boundActionObserved
        ForegroundActivationRequired = $false
        WarningDelayMilliseconds = [int]$receipt.warningDelayMilliseconds
        Directory = $runRoot
        Receipt = $receiptPath
        ProxySha256 = (Get-FileHash -LiteralPath (Join-Path $runRoot 'd3d11.dll') -Algorithm SHA256).Hash
    }
}
finally {
    if ($hostProcess -and -not $hostProcess.HasExited) {
        $hostProcess.Kill()
        $hostProcess.WaitForExit()
    }
}
