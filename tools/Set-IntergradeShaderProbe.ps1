[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Status', 'Install', 'Restore')]
    [string]$Action = 'Status',
    [ValidatePattern('^[0-9a-fA-F]{16}$')]
    [string]$ShaderHash,
    [ValidateSet('Skip', 'SolidColor')]
    [string]$ProbeMode = 'Skip',
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$GameRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$targetPath = Join-Path $GameRoot 'End\Binaries\Win64\Mods\RebirthEffectsDX11.ini'
$stateRoot = Join-Path $projectPath 'backups\live-probe'
$backupPath = Join-Path $stateRoot 'RebirthEffectsDX11.ini.last-clean'
$statePath = Join-Path $stateRoot 'state.json'
$beginMarker = '; REDX11 CONTROLLED PROBE BEGIN'
$endMarker = '; REDX11 CONTROLLED PROBE END'

function Get-ProbeHash {
    param([Parameter(Mandatory)][string]$Text)

    $pattern = '(?ms)^' + [regex]::Escape($beginMarker) + '.*?^hash\s*=\s*([0-9a-fA-F]{16})\s*$.*?^' + [regex]::Escape($endMarker) + '\s*$'
    $match = [regex]::Match($Text, $pattern)
    if ($match.Success) {
        return $match.Groups[1].Value.ToLowerInvariant()
    }
    return $null
}

function Get-Status {
    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        throw "Live mod file was not found: $targetPath"
    }

    $text = [System.IO.File]::ReadAllText($targetPath)
    $activeHash = Get-ProbeHash -Text $text
    $activeMode = if ([string]::IsNullOrWhiteSpace($activeHash)) { $null } elseif ($text -match 'run\s*=\s*CustomShaderRebirthSolidColorProbe') { 'SolidColor' } else { 'Skip' }
    [pscustomobject]@{
        action = 'Status'
        targetPath = $targetPath
        targetSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetPath).Hash
        probeActive = -not [string]::IsNullOrWhiteSpace($activeHash)
        shaderHash = $activeHash
        probeMode = $activeMode
        cleanBackupPresent = Test-Path -LiteralPath $backupPath -PathType Leaf
        statePath = $statePath
    }
}

if ($Action -eq 'Status') {
    Get-Status
    return
}

if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
    throw "Live mod file was not found: $targetPath"
}

if ($Action -eq 'Install') {
    if ([string]::IsNullOrWhiteSpace($ShaderHash)) {
        throw '-ShaderHash is required for Install.'
    }

    $current = [System.IO.File]::ReadAllText($targetPath)
    $existingHash = Get-ProbeHash -Text $current
    if (-not [string]::IsNullOrWhiteSpace($existingHash)) {
        throw "Probe $existingHash is already active. Restore it before installing another probe."
    }

    if ($PSCmdlet.ShouldProcess($targetPath, "Install controlled $ProbeMode probe for pixel shader $ShaderHash")) {
        New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
        Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force
        $baselineSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $backupPath).Hash
        $normalizedHash = $ShaderHash.ToLowerInvariant()
        $block = if ($ProbeMode -eq 'SolidColor') {
            $shaderSource = Join-Path $projectPath 'runtime\Intergrade\Mods\RebirthSolidColorProbe_ps.hlsl'
            if (-not (Test-Path -LiteralPath $shaderSource -PathType Leaf)) {
                throw "Solid-color probe shader was not found: $shaderSource"
            }
            $shaderTarget = Join-Path (Split-Path -Parent $targetPath) 'RebirthSolidColorProbe_ps.hlsl'
            Copy-Item -LiteralPath $shaderSource -Destination $shaderTarget -Force
@"
$beginMarker
[ShaderOverrideRebirthControlledProbe]
hash = $normalizedHash
run = CustomShaderRebirthSolidColorProbe

[CustomShaderRebirthSolidColorProbe]
ps = RebirthSolidColorProbe_ps.hlsl
blend = disable
handling = skip
draw = from_caller
$endMarker
"@
        } else {
@"
$beginMarker
[ShaderOverrideRebirthControlledProbe]
hash = $normalizedHash
handling = skip
$endMarker
"@
        }
        $updated = $current.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $block.Trim() + [Environment]::NewLine
        [System.IO.File]::WriteAllText($targetPath, $updated, [System.Text.UTF8Encoding]::new($false))

        $state = [ordered]@{
            schemaVersion = 1
            status = 'installed'
            installedAtUtc = [DateTime]::UtcNow.ToString('o')
            shaderHash = $normalizedHash
            probeMode = $ProbeMode
            targetPath = $targetPath
            baselineSha256 = $baselineSha256
            probeSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetPath).Hash
            backupPath = $backupPath
        }
        [System.IO.File]::WriteAllText(
            $statePath,
            ($state | ConvertTo-Json -Depth 4) + [Environment]::NewLine,
            [System.Text.UTF8Encoding]::new($false))
    }

    Get-Status
    return
}

if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
    throw "Clean probe backup was not found: $backupPath"
}

if ($PSCmdlet.ShouldProcess($targetPath, 'Restore the clean pre-probe mod configuration')) {
    Copy-Item -LiteralPath $backupPath -Destination $targetPath -Force
    $restoredText = [System.IO.File]::ReadAllText($targetPath)
    if (-not [string]::IsNullOrWhiteSpace((Get-ProbeHash -Text $restoredText))) {
        throw 'The restored configuration still contains a controlled probe block.'
    }

    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
        $state | Add-Member -NotePropertyName status -NotePropertyValue 'restored' -Force
        $state | Add-Member -NotePropertyName restoredAtUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
        $state | Add-Member -NotePropertyName restoredSha256 -NotePropertyValue ((Get-FileHash -Algorithm SHA256 -LiteralPath $targetPath).Hash) -Force
        [System.IO.File]::WriteAllText(
            $statePath,
            ($state | ConvertTo-Json -Depth 4) + [Environment]::NewLine,
            [System.Text.UTF8Encoding]::new($false))
    }
}

Get-Status