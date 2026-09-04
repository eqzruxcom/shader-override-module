[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ForkRoot = (Join-Path $PSScriptRoot '..\src\Backends\3DmigotoFork')
)

$ErrorActionPreference = 'Stop'
$inputPath = Join-Path $ForkRoot 'DirectX11\input.cpp'
if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
    throw "3Dmigoto DirectX11 input source was not found: $inputPath"
}

$source = [IO.File]::ReadAllText($inputPath)
if ($source -match '#include "RemoteInput.h"') {
    [pscustomobject]@{ Result='already-applied'; Path=$inputPath }
    return
}

$newline = if ($source.Contains("`r`n")) { "`r`n" } else { "`n" }

$includePattern = '#include "Input\.h"\r?\n'
$checkPattern = '(?ms)bool VKInputButton::CheckState\(\)\s*\{\s*return \(\(GetAsyncKeyState\(vkey\) < 0\) \^ invert\);\s*\}'
$foregroundPattern = '(?m)^\s*if \(!CheckForegroundWindow\(\)\)\r?$\n^\s*return false;\r?$'
$dispatchPattern = '(?ms)(bool DispatchInputEvents\(HackerDevice \*device\).*?)(\s*return input_processed;\r?\n\})'

foreach ($entry in @(
    @{Name='include'; Pattern=$includePattern},
    @{Name='VKInputButton::CheckState'; Pattern=$checkPattern},
    @{Name='foreground gate'; Pattern=$foregroundPattern},
    @{Name='DispatchInputEvents tail'; Pattern=$dispatchPattern}
)) {
    $count = [regex]::Matches($source, $entry.Pattern).Count
    if ($count -ne 1) {
        throw "Expected exactly one $($entry.Name) anchor; found $count. Refusing a partial rewrite."
    }
}

$updated = [regex]::Replace(
    $source,
    $includePattern,
    '#include "Input.h"' + $newline + '#include "RemoteInput.h"' + $newline,
    1)

$checkReplacement = 'bool VKInputButton::CheckState()' + $newline + '{' + $newline +
    "`treturn ((UE4FXRemoteInput::CheckVirtualKeyState(vkey) < 0) ^ invert);" + $newline + '}'
$updated = [regex]::Replace($updated, $checkPattern, $checkReplacement, 1)

$foregroundReplacement = "`tbool remote_input_frame = UE4FXRemoteInput::BeginDispatchFrame();" + $newline +
    "`tif (!remote_input_frame && !CheckForegroundWindow())" + $newline +
    "`t`treturn false;"
$updated = [regex]::Replace($updated, $foregroundPattern, $foregroundReplacement, 1)

$dispatchRegex = [regex]::new($dispatchPattern)
$updated = $dispatchRegex.Replace($updated, {
    param($match)
    $match.Groups[1].Value + $newline + "`tUE4FXRemoteInput::EndDispatchFrame();" + $match.Groups[2].Value
}, 1)

foreach ($required in @(
    '#include "RemoteInput.h"',
    'UE4FXRemoteInput::CheckVirtualKeyState(vkey)',
    'UE4FXRemoteInput::BeginDispatchFrame()',
    'UE4FXRemoteInput::EndDispatchFrame()'
)) {
    if (-not $updated.Contains($required)) {
        throw "Generated source is missing required integration marker: $required"
    }
}

if (-not $PSCmdlet.ShouldProcess($inputPath, 'Add no-focus remote input event integration')) { return }

$backup = "$inputPath.pre-remote-input"
if (-not (Test-Path -LiteralPath $backup)) {
    [IO.File]::WriteAllText($backup, $source, [Text.UTF8Encoding]::new($false))
}
[IO.File]::WriteAllText($inputPath, $updated, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Result = 'applied'
    Path = $inputPath
    Backup = $backup
    Sha256 = (Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash
}
