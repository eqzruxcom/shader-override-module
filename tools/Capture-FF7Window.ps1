[CmdletBinding()]
param(
    [string]$ExpectedExe = 'ff7remake_',

    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\artifacts\game-captures'),

    [ValidateSet('PrintWindow', 'Screen')]
    [string]$Method = 'PrintWindow'
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class FF7WindowCaptureNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
}
'@

$processes = @(Get-Process -Name $ExpectedExe -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 })
if ($processes.Count -ne 1) {
    throw "Expected exactly one visible $ExpectedExe window; found $($processes.Count)."
}

$process = $processes[0]
$window = [IntPtr]$process.MainWindowHandle
$rect = [FF7WindowCaptureNative+RECT]::new()
if (-not [FF7WindowCaptureNative]::GetWindowRect($window, [ref]$rect)) {
    throw 'GetWindowRect failed.'
}

$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
if ($width -le 0 -or $height -le 0) {
    throw "Invalid game-window dimensions: ${width}x${height}."
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$stamp = [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$outputPath = Join-Path $OutputDirectory "$stamp-$Method.png"
$bitmap = [Drawing.Bitmap]::new($width, $height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [Drawing.Graphics]::FromImage($bitmap)

try {
    if ($Method -eq 'PrintWindow') {
        $deviceContext = $graphics.GetHdc()
        try {
            # PW_RENDERFULLCONTENT asks DWM for the complete window without activating it.
            if (-not [FF7WindowCaptureNative]::PrintWindow($window, $deviceContext, 2)) {
                throw 'PrintWindow failed.'
            }
        }
        finally {
            $graphics.ReleaseHdc($deviceContext)
        }
    }
    else {
        # Screen capture is reliable for a visible window but does not see obscured pixels.
        $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, [Drawing.Size]::new($width, $height))
    }

    $bitmap.Save($outputPath, [Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $graphics.Dispose()
    $bitmap.Dispose()
}

[pscustomobject]@{
    Path = (Resolve-Path -LiteralPath $outputPath).Path
    Method = $Method
    ProcessId = $process.Id
    WindowHandle = $process.MainWindowHandle
    Width = $width
    Height = $height
    CapturedWithoutActivation = ($Method -eq 'PrintWindow')
}
