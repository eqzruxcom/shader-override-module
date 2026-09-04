[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ForkRoot
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$forkRoot = (Resolve-Path -LiteralPath $ForkRoot).Path
$proxyPath = Join-Path $forkRoot 'builds\x64\Release\d3d11.dll'
$compilerPath = Join-Path $forkRoot 'builds\x64\Release\d3dcompiler_47.dll'
$nvapiPath = Join-Path $forkRoot 'builds\x64\Release\nvapi64.dll'
$sourcePath = Join-Path $PSScriptRoot 'RemoteInputHost.cpp'
$configurationPath = Join-Path $PSScriptRoot 'd3dx-baseline.ini'
$senderPath = Join-Path $repositoryRoot 'tools\Send-3DMigotoStatus.ps1'
$vsDevCmd = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat'
$runRoot = Join-Path $repositoryRoot ('artifacts\remote-status-tests\' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
$hostPath = Join-Path $runRoot 'RemoteInputHost.exe'
$statusMessage = 'Offline OSD status channel verified'

foreach ($requiredPath in @(
    $proxyPath,
    $compilerPath,
    $nvapiPath,
    $sourcePath,
    $configurationPath,
    $senderPath,
    $vsDevCmd
)) {
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
Copy-Item -LiteralPath $configurationPath -Destination (Join-Path $runRoot 'd3dx.ini')

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

    $receipt = & $senderPath -Message $statusMessage -ProcessId $hostProcess.Id
    if (-not $receipt.Acknowledged) {
        throw 'The status sender did not receive the wrapper acknowledgement.'
    }

    $logPath = Join-Path $runRoot 'd3d11_log.txt'
    $expectedLogMarker = "Codex: $statusMessage"
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
        if ($log.Contains($expectedLogMarker)) { break }
        Start-Sleep -Milliseconds 50
    } while ([datetime]::UtcNow -lt $deadline)

    if (-not $log.Contains($expectedLogMarker)) {
        throw '3Dmigoto acknowledged the status request but did not emit the expected overlay/log notice.'
    }

    [pscustomobject]@{
        Result = 'pass'
        Message = $statusMessage
        AcknowledgedBy3Dmigoto = $true
        OverlayNoticeObservedInLog = $true
        ForegroundActivationRequired = $false
        Directory = $runRoot
        ProxySha256 = (Get-FileHash -LiteralPath (Join-Path $runRoot 'd3d11.dll') -Algorithm SHA256).Hash
    }
}
finally {
    if ($hostProcess -and -not $hostProcess.HasExited) {
        $hostProcess.Kill()
        $hostProcess.WaitForExit()
    }
}
