[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RuntimeDirectory,
    [string]$HarnessRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\dxvk-d3d11-smoke-harness')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $root 'artifacts'))
$resolvedRuntime = [IO.Path]::GetFullPath($RuntimeDirectory)
$resolvedHarness = [IO.Path]::GetFullPath($HarnessRoot)

foreach ($path in @($resolvedRuntime, $resolvedHarness)) {
    if (-not $path.StartsWith($artifactsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing runtime test input outside the workspace artifacts directory: $path"
    }
}

$d3d11 = Join-Path $resolvedRuntime 'd3d11.dll'
$dxgi = Join-Path $resolvedRuntime 'dxgi.dll'
$executable = Join-Path $resolvedHarness 'DxvkD3D11Smoke.exe'
$original = Join-Path $resolvedHarness 'original-cs.bin'
$manifestPath = Join-Path $resolvedHarness 'manifest.json'
foreach ($path in @($d3d11, $dxgi, $executable, $original, $manifestPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required patched-runtime test input is missing: $path"
    }
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$identity = $manifest.Identity
if ($identity -notmatch '^[0-9a-f]{16}-cs$') {
    throw "Unexpected smoke shader identity: $identity"
}

$runParent = Join-Path $artifactsRoot 'dxvk-d3d11-smoke-runs'
$runRoot = Join-Path $runParent (Get-Date -Format 'yyyyMMdd-HHmmss')
if (Test-Path -LiteralPath $runRoot) {
    throw "Refusing to overwrite an existing runtime test: $runRoot"
}

$compatibleRoot = Join-Path $runRoot 'replacement-compatible'
$missingRoot = Join-Path $runRoot 'replacement-missing'
$corruptRoot = Join-Path $runRoot 'replacement-corrupt'
$logRoot = Join-Path $runRoot 'logs'
New-Item -ItemType Directory -Force -Path $runRoot, $compatibleRoot, $missingRoot, $corruptRoot, $logRoot | Out-Null

Copy-Item -LiteralPath $d3d11, $dxgi, $executable, $original -Destination $runRoot
$compatibleSource = Join-Path $resolvedHarness "replacements\${identity}_replace.bin"
if (-not (Test-Path -LiteralPath $compatibleSource -PathType Leaf)) {
    throw "Compatible replacement is missing: $compatibleSource"
}
Copy-Item -LiteralPath $compatibleSource -Destination (Join-Path $compatibleRoot "${identity}_replace.bin")
[IO.File]::WriteAllBytes((Join-Path $corruptRoot "${identity}_replace.bin"), [byte[]](0x4e, 0x4f, 0x54, 0x44, 0x58, 0x42, 0x43))

function Invoke-SmokeCase {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ReplacementRoot,
        [Parameter(Mandatory)][int]$Expected
    )

    $configPath = Join-Path $runRoot "$Name.conf"
    $caseLogRoot = Join-Path $logRoot $Name
    New-Item -ItemType Directory -Force -Path $caseLogRoot | Out-Null
    # Exercise the same relative-path contract used by staged runtime bundles.
    # DXVK's config parser treats unquoted spaces as the end of a value, so an
    # absolute workspace path would be truncated at "FF7 Rebirth mod".
    $replacementDirectoryName = Split-Path -Leaf $ReplacementRoot
    "d3d11.shaderOverridePath = $replacementDirectoryName" |
        Set-Content -LiteralPath $configPath -Encoding ascii

    $previousConfig = $env:DXVK_CONFIG_FILE
    $previousLogPath = $env:DXVK_LOG_PATH
    $previousLogLevel = $env:DXVK_LOG_LEVEL
    try {
        $env:DXVK_CONFIG_FILE = $configPath
        $env:DXVK_LOG_PATH = $caseLogRoot
        $env:DXVK_LOG_LEVEL = 'info'
        $previousCurrentDirectory = [Environment]::CurrentDirectory
        Push-Location $runRoot
        try {
            # PowerShell's provider location does not update the Win32 process
            # current directory. DXVK resolves a relative override path through
            # std::filesystem, so set both for this child process.
            [Environment]::CurrentDirectory = $runRoot
            $lines = @(& '.\DxvkD3D11Smoke.exe' '.\original-cs.bin' $Expected 2>&1)
            $exitCode = $LASTEXITCODE
        }
        finally {
            [Environment]::CurrentDirectory = $previousCurrentDirectory
            Pop-Location
        }
        $lines | ForEach-Object { Write-Host "[$Name] $_" }
        if ($exitCode -ne 0) {
            throw "Patched DXVK smoke case '$Name' failed (exit code $exitCode)"
        }

        $d3dLine = $lines | Where-Object { $_ -like 'D3D11Module:*' } | Select-Object -First 1
        if (-not $d3dLine -or $d3dLine -notlike "*$runRoot*") {
            throw "Smoke case '$Name' did not load the staged patched d3d11.dll: $d3dLine"
        }

        $d3dLogs = @(Get-ChildItem -LiteralPath $caseLogRoot -File -Filter '*_d3d11.log')
        if ($d3dLogs.Count -ne 1) {
            throw "Smoke case '$Name' produced $($d3dLogs.Count) D3D11 logs; expected exactly one."
        }
        $d3dLog = $d3dLogs[0]
        $d3dLogText = Get-Content -LiteralPath $d3dLog.FullName -Raw
        $loadedMarker = "D3D11: Loaded shader replacement $identity from"
        $rejectedMarker = "D3D11: Rejecting shader replacement ${identity}:"
        switch ($Name) {
            'compatible' {
                if (-not $d3dLogText.Contains($loadedMarker) -or $d3dLogText.Contains($rejectedMarker)) {
                    throw "Compatible smoke case did not log one accepted replacement without rejection: $($d3dLog.FullName)"
                }
            }
            'missing' {
                if ($d3dLogText.Contains($loadedMarker) -or $d3dLogText.Contains($rejectedMarker)) {
                    throw "Missing smoke case unexpectedly loaded or rejected a replacement instead of silently using the original: $($d3dLog.FullName)"
                }
            }
            'corrupt' {
                if (-not $d3dLogText.Contains($rejectedMarker) -or $d3dLogText.Contains($loadedMarker)) {
                    throw "Corrupt smoke case did not log rejection without accepting the replacement: $($d3dLog.FullName)"
                }
            }
            default { throw "Unknown patched-runtime smoke case: $Name" }
        }

        [pscustomobject]@{
            Name = $Name
            Log = $d3dLog.FullName
            LogSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $d3dLog.FullName).Hash
            ReplacementLoaded = $d3dLogText.Contains($loadedMarker)
            ReplacementRejected = $d3dLogText.Contains($rejectedMarker)
        }
    }
    finally {
        $env:DXVK_CONFIG_FILE = $previousConfig
        $env:DXVK_LOG_PATH = $previousLogPath
        $env:DXVK_LOG_LEVEL = $previousLogLevel
    }
}

$caseEvidence = @(
    Invoke-SmokeCase 'compatible' $compatibleRoot 42
    Invoke-SmokeCase 'missing' $missingRoot 7
    Invoke-SmokeCase 'corrupt' $corruptRoot 7
)

$result = [ordered]@{
    Schema = 1
    RuntimeDirectory = $resolvedRuntime
    RuntimeD3D11Sha256 = (Get-FileHash -LiteralPath $d3d11 -Algorithm SHA256).Hash
    RuntimeDxgiSha256 = (Get-FileHash -LiteralPath $dxgi -Algorithm SHA256).Hash
    ShaderIdentity = $identity
    CompatibleReplacementResult = 42
    MissingReplacementFallbackResult = 7
    CorruptReplacementFallbackResult = 7
    CaseEvidence = $caseEvidence
    RunRoot = $runRoot
    Passed = $true
    Installed = $false
}
$resultPath = Join-Path $runRoot 'result.json'
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resultPath -Encoding utf8

Write-Host 'PASS: patched DXVK accepted the compatible canonical replacement and failed closed for missing and corrupt replacements.'
[pscustomobject]@{ RunRoot = $runRoot; ResultPath = $resultPath; Passed = $true }
