[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ForkRoot
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$forkRoot = (Resolve-Path -LiteralPath $ForkRoot).Path
$sourcePath = Join-Path $PSScriptRoot 'RemoteInputHost.cpp'
$senderPath = Join-Path $repositoryRoot 'tools\Send-3DMigotoStatus.ps1'
$vsDevCmd = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat'
$runRoot = Join-Path $repositoryRoot ('artifacts\remote-status-tests\' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
$hostPath = Join-Path $runRoot 'RemoteInputHost.exe'
$beforePath = Join-Path $runRoot 'before-status.png'
$afterPath = Join-Path $runRoot 'after-status.png'
$statusMessage = 'Offline OSD status channel verified'

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class RemoteStatusWindowBounds
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(
        IntPtr hwnd,
        int attribute,
        out RECT value,
        int size);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(
        IntPtr hwnd,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool PrintWindow(IntPtr hwnd, IntPtr deviceContext, uint flags);
}
'@

function Save-WindowScreenshot {
    param([IntPtr]$WindowHandle, [string]$Path)

    $rect = [RemoteStatusWindowBounds+RECT]::new()
    $size = [Runtime.InteropServices.Marshal]::SizeOf($rect)
    $result = [RemoteStatusWindowBounds]::DwmGetWindowAttribute($WindowHandle, 9, [ref]$rect, $size)
    if ($result -ne 0) {
        throw "DwmGetWindowAttribute failed with HRESULT 0x$($result.ToString('X8'))."
    }

    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    $bitmap = [Drawing.Bitmap]::new($width, $height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $deviceContext = $graphics.GetHdc()
    try {
        $rendered = [RemoteStatusWindowBounds]::PrintWindow($WindowHandle, $deviceContext, 2)
        if (-not $rendered) {
            throw "PrintWindow failed with Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())."
        }
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.ReleaseHdc($deviceContext)
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$required = @(
    (Join-Path $forkRoot 'builds\x64\Release\d3d11.dll'),
    (Join-Path $forkRoot 'builds\x64\Release\d3dcompiler_47.dll'),
    (Join-Path $forkRoot 'builds\x64\Release\nvapi64.dll'),
    $sourcePath,
    $senderPath,
    $vsDevCmd
)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required path is missing: $path"
    }
}

New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $runRoot 'ShaderFixes') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $runRoot 'ShaderCache') -Force | Out-Null

$compileLine = 'call "{0}" -arch=x64 -host_arch=x64 -winsdk=10.0.26100.0 >nul && cl /nologo /EHsc /std:c++17 /O2 /FIcwchar "{1}" /Fe:"{2}" d3d11.lib user32.lib' -f $vsDevCmd, $sourcePath, $hostPath
& $env:ComSpec /d /s /c $compileLine
if ($LASTEXITCODE -ne 0) { throw "Host compile failed with exit code $LASTEXITCODE" }

Copy-Item -LiteralPath (Join-Path $forkRoot 'builds\x64\Release\d3d11.dll') -Destination $runRoot
Copy-Item -LiteralPath (Join-Path $forkRoot 'builds\x64\Release\d3dcompiler_47.dll') -Destination $runRoot
Copy-Item -LiteralPath (Join-Path $forkRoot 'builds\x64\Release\nvapi64.dll') -Destination $runRoot
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'd3dx-baseline.ini') -Destination (Join-Path $runRoot 'd3dx.ini')

$startInfo = [Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $hostPath
$startInfo.WorkingDirectory = $runRoot
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$hostProcess = [Diagnostics.Process]::Start($startInfo)

try {
    $readyPath = Join-Path $runRoot 'ready.flag'
    $deadline = [datetime]::UtcNow.AddSeconds(5)
    while (-not (Test-Path -LiteralPath $readyPath)) {
        if ($hostProcess.HasExited) { throw "Host exited before ready with code $($hostProcess.ExitCode)." }
        if ([datetime]::UtcNow -gt $deadline) { throw 'Host did not become ready within five seconds.' }
        Start-Sleep -Milliseconds 50
    }

    $hostProcess.Refresh()
    $noSize = 0x0001
    $noMove = 0x0002
    $noActivate = 0x0010
    $madeTopmost = [RemoteStatusWindowBounds]::SetWindowPos(
        $hostProcess.MainWindowHandle,
        [IntPtr](-1),
        0, 0, 0, 0,
        ($noSize -bor $noMove -bor $noActivate))
    if (-not $madeTopmost) {
        throw "SetWindowPos failed with Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())."
    }
    Start-Sleep -Milliseconds 150
    Save-WindowScreenshot -WindowHandle $hostProcess.MainWindowHandle -Path $beforePath
    $receipt = & $senderPath -Message $statusMessage -ProcessId $hostProcess.Id
    if (-not $receipt.Acknowledged) { throw 'The wrapper did not acknowledge the message.' }
    Start-Sleep -Milliseconds 300
    Save-WindowScreenshot -WindowHandle $hostProcess.MainWindowHandle -Path $afterPath

    $beforeHash = (Get-FileHash -LiteralPath $beforePath -Algorithm SHA256).Hash
    $afterHash = (Get-FileHash -LiteralPath $afterPath -Algorithm SHA256).Hash
    if ($beforeHash -eq $afterHash) {
        throw 'The wrapper acknowledged the message but the rendered host image did not change.'
    }

    [pscustomobject]@{
        Result = 'pass'
        Message = $statusMessage
        AcknowledgedBy3Dmigoto = $true
        RenderedImageChanged = $true
        ForegroundActivationRequired = $false
        Directory = $runRoot
        BeforeScreenshot = $beforePath
        AfterScreenshot = $afterPath
        ProxySha256 = (Get-FileHash -LiteralPath (Join-Path $runRoot 'd3d11.dll') -Algorithm SHA256).Hash
    }
}
finally {
    if ($hostProcess -and -not $hostProcess.HasExited) {
        $hostProcess.Kill()
        $hostProcess.WaitForExit()
    }
}
