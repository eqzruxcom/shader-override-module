[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RuntimeDirectory,
    [Parameter(Mandatory)][string]$OriginalBytecode,
    [Parameter(Mandatory)][string]$ReplacementManifestPath,
    [string]$OutputParent = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\dxvk-d3d11-real-shader-runs')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$workspaceRoot = [IO.Path]::GetFullPath($root).TrimEnd('\')
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')

function Resolve-ArtifactFile([string]$Path, [string]$Label) {
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if (-not $resolved.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must be a workspace artifact: $resolved"
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "$Label is missing: $resolved" }
    return $resolved
}

function Resolve-WorkspaceFile([string]$Path, [string]$Label) {
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if (-not ($resolved.Equals($workspaceRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $resolved.StartsWith($workspaceRoot + '\', [StringComparison]::OrdinalIgnoreCase))) {
        throw "$Label must be a workspace file: $resolved"
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "$Label is missing: $resolved" }
    return $resolved
}

$runtime = [IO.Path]::GetFullPath($RuntimeDirectory)
if (-not $runtime.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Runtime directory must be a workspace artifact: $runtime"
}
$d3d11 = Resolve-ArtifactFile (Join-Path $runtime 'd3d11.dll') 'Patched d3d11.dll'
$dxgi = Resolve-ArtifactFile (Join-Path $runtime 'dxgi.dll') 'Patched dxgi.dll'
$original = Resolve-WorkspaceFile $OriginalBytecode 'Original real shader'
$replacementManifestFile = Resolve-ArtifactFile $ReplacementManifestPath 'Replacement manifest'
$replacementManifest = Get-Content -Raw -LiteralPath $replacementManifestFile | ConvertFrom-Json
if ($replacementManifest.schemaVersion -ne 1 -or $replacementManifest.backend -ne 'dxvk-d3d11' -or
    $replacementManifest.stage -ne 'cs' -or $replacementManifest.identity -notmatch '^[0-9a-f]{16}-cs$' -or
    $replacementManifest.originalIdentityVerified -ne $true -or
    $replacementManifest.compatibilityStatus -notin @('passed-reflection-contract','passed-declaration-contract-rdef-unavailable') -or
    -not $replacementManifest.reviewedFamily -or
    $replacementManifest.runtimeEligible -ne $false -or $replacementManifest.installed -ne $false) {
    throw 'Replacement manifest is not a reviewed, identity-verified, compatible, non-installing compute replacement.'
}
$replacement = Resolve-ArtifactFile ([string]$replacementManifest.outputPath) 'Real shader replacement binary'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $replacement).Hash.ToLowerInvariant() -ne $replacementManifest.outputSha256) {
    throw 'Replacement binary hash does not match its manifest.'
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $original).Hash.ToLowerInvariant() -ne $replacementManifest.originalSha256) {
    throw 'Original shader hash does not match the replacement manifest.'
}

$outputRoot = [IO.Path]::GetFullPath($OutputParent).TrimEnd('\')
if (-not $outputRoot.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Real-shader run output must remain under workspace artifacts: $outputRoot"
}
$runRoot = Join-Path $outputRoot ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($runRoot) | Out-Null
$source = Join-Path $PSScriptRoot 'DxvkD3D11CreateShader.cpp'
$executable = Join-Path $runRoot 'DxvkD3D11CreateShader.exe'
$objectFile = Join-Path $runRoot 'DxvkD3D11CreateShader.obj'
$vsDevCmd = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat'
foreach ($path in @($source, $vsDevCmd)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Native build input is missing: $path" } }

$compile = @(
    'call', ('"{0}"' -f $vsDevCmd), '-arch=x64', '-host_arch=x64', '-no_logo', '>', 'nul', '&&',
    'cl.exe', '/nologo', '/std:c++17', '/EHsc', '/W4', '/WX', '/DUNICODE', '/D_UNICODE',
    ('/Fo"{0}"' -f $objectFile), ('/Fe"{0}"' -f $executable), ('"{0}"' -f $source), 'd3d11.lib', 'dxgi.lib'
)
& $env:ComSpec /d /s /c ($compile -join ' ')
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "Compiling the real-shader creation harness failed (exit code $LASTEXITCODE)."
}

Copy-Item -LiteralPath $d3d11, $dxgi, $original -Destination $runRoot
$stagedOriginal = Join-Path $runRoot (Split-Path -Leaf $original)
$identity = [string]$replacementManifest.identity
$caseEvidence = [Collections.Generic.List[object]]::new()

function Invoke-Case([string]$Name, [ValidateSet('compatible','missing','corrupt')][string]$Mode) {
    $replacementRoot = Join-Path $runRoot ("replacement-$Name")
    $logRoot = Join-Path $runRoot ("logs\$Name")
    [IO.Directory]::CreateDirectory($replacementRoot) | Out-Null
    [IO.Directory]::CreateDirectory($logRoot) | Out-Null
    $candidate = Join-Path $replacementRoot ($identity + '_replace.bin')
    if ($Mode -eq 'compatible') { Copy-Item -LiteralPath $replacement -Destination $candidate }
    elseif ($Mode -eq 'corrupt') { [IO.File]::WriteAllBytes($candidate, [byte[]](0x4e,0x4f,0x54,0x44,0x58,0x42,0x43)) }

    $config = Join-Path $runRoot ("$Name.conf")
    "d3d11.shaderOverridePath = $(Split-Path -Leaf $replacementRoot)" | Set-Content -LiteralPath $config -Encoding ascii
    $oldConfig=$env:DXVK_CONFIG_FILE; $oldLogPath=$env:DXVK_LOG_PATH; $oldLogLevel=$env:DXVK_LOG_LEVEL
    $oldCurrent=[Environment]::CurrentDirectory
    try {
        $env:DXVK_CONFIG_FILE=$config; $env:DXVK_LOG_PATH=$logRoot; $env:DXVK_LOG_LEVEL='info'
        Push-Location $runRoot
        try {
            [Environment]::CurrentDirectory=$runRoot
            $lines=@(& '.\DxvkD3D11CreateShader.exe' ('.\' + (Split-Path -Leaf $stagedOriginal)) 2>&1)
            $exitCode=$LASTEXITCODE
        }
        finally { [Environment]::CurrentDirectory=$oldCurrent; Pop-Location }
        $lines | ForEach-Object { Write-Host "[$Name] $_" }
        if ($exitCode -ne 0) { throw "Real shader case '$Name' failed to create the shader object (exit $exitCode)." }
        $moduleLine=$lines|Where-Object{$_ -like 'D3D11Module:*'}|Select-Object -First 1
        if(-not$moduleLine-or$moduleLine-notlike"*$runRoot*"){throw"Real shader case '$Name' did not load staged patched d3d11.dll: $moduleLine"}
        $logs=@(Get-ChildItem -LiteralPath $logRoot -File -Filter '*_d3d11.log')
        if($logs.Count-ne1){throw"Real shader case '$Name' produced $($logs.Count) D3D11 logs; expected one."}
        $log=$logs[0];$text=Get-Content -Raw -LiteralPath $log.FullName
        $loaded="D3D11: Loaded shader replacement $identity from";$rejected="D3D11: Rejecting shader replacement ${identity}:"
        if($Mode-eq'compatible'-and(-not$text.Contains($loaded)-or$text.Contains($rejected))){throw'Compatible real replacement was not accepted exactly once.'}
        if($Mode-eq'missing'-and($text.Contains($loaded)-or$text.Contains($rejected))){throw'Missing real replacement did not silently use the original.'}
        if($Mode-eq'corrupt'-and(-not$text.Contains($rejected)-or$text.Contains($loaded))){throw'Corrupt real replacement was not rejected with original fallback.'}
        $caseEvidence.Add([ordered]@{
            name=$Name; mode=$Mode; shaderCreated=$true; log=$log.FullName
            logSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $log.FullName).Hash
            replacementLoaded=$text.Contains($loaded); replacementRejected=$text.Contains($rejected)
        })
    }
    finally { $env:DXVK_CONFIG_FILE=$oldConfig; $env:DXVK_LOG_PATH=$oldLogPath; $env:DXVK_LOG_LEVEL=$oldLogLevel }
}

Invoke-Case 'compatible' 'compatible'
Invoke-Case 'missing' 'missing'
Invoke-Case 'corrupt' 'corrupt'

$result = [ordered]@{
    schemaVersion=1; kind='dxvk-d3d11-real-shader-creation-gate'; passed=$true
    identity=$identity; stage='cs'
    originalPath=$original; originalSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $original).Hash
    replacementPath=$replacement; replacementSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $replacement).Hash
    replacementManifestPath=$replacementManifestFile; replacementManifestSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $replacementManifestFile).Hash
    runtimeDirectory=$runtime; runtimeD3D11Sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $d3d11).Hash
    runtimeDxgiSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $dxgi).Hash
    caseEvidence=@($caseEvidence); runRoot=$runRoot; installed=$false; runtimeEligible=$false
}
$resultPath=Join-Path $runRoot 'result.json'
[IO.File]::WriteAllText($resultPath,(($result|ConvertTo-Json -Depth 7)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
Write-Host 'PASS: real FF7 shader created through patched DXVK with compatible selection, silent missing fallback, and corrupt rejection fallback.'
[pscustomobject]@{RunRoot=$runRoot;ResultPath=$resultPath;Passed=$true;Installed=$false;RuntimeEligible=$false}
