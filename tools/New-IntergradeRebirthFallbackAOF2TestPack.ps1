[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-rebirth-fallback-consumer-f2-test-pack'),
    [string[]]$ConflictScanRoots,
    [switch]$AllowExternalConflictScanRoot,
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$candidateGenerator = Join-Path $repoRoot 'tools\New-IntergradeRebirthFallbackAOConsumer.ps1'

function Resolve-WorkspacePath([string]$Path, [switch]$AllowMissing, [switch]$Directory) {
    $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $repoRoot $Path)) }
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Path must remain inside the project workspace: $full" }
    if (-not $AllowMissing) {
        $pathType = if ($Directory) { 'Container' } else { 'Leaf' }
        if (-not (Test-Path -LiteralPath $full -PathType $pathType)) { throw "Required path does not exist: $full" }
    }
    $full
}
function Resolve-ConflictRoot([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw "Conflict-scan root does not exist: $full" }
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        if (-not $AllowExternalConflictScanRoot) { throw "External conflict-scan root requires -AllowExternalConflictScanRoot: $full" }
        if (-not $full.EndsWith('\End\Binaries\Win64\Mods', [StringComparison]::OrdinalIgnoreCase)) {
            throw "External conflict-scan root must be an exact FF7 Remake Win64 Mods directory: $full"
        }
    }
    $full
}

if ($null -eq $ConflictScanRoots -or $ConflictScanRoots.Count -eq 0) {
    $ConflictScanRoots = @((Join-Path $repoRoot 'runtime\Intergrade\Mods'))
}
$resolvedConflictRoots = @($ConflictScanRoots | ForEach-Object { Resolve-ConflictRoot $_ })
$runtimeIniFiles = @(
    $resolvedConflictRoots |
        ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -File -Filter '*.ini' } |
        Sort-Object FullName -Unique
)
$conflicts = [Collections.Generic.List[object]]::new()
foreach ($iniFile in $runtimeIniFiles) {
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $iniFile.FullName) {
        $lineNumber++
        if ($line -match '^\s*;') { continue }
        if ($line -match '(?i)(?<![A-Z0-9_])(?:VK_)?F2(?![A-Z0-9_])' -or $line -match '(?i)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$') {
            $conflicts.Add([pscustomobject]@{ path=$iniFile.FullName; line=$lineNumber; text=$line.Trim() })
        }
    }
}
if ($conflicts.Count -ne 0) {
    throw "Refusing corrected F2 AO pack because the scanned runtime already claims F2 or e2aa1c8cb39e0a55: $($conflicts | ConvertTo-Json -Compress)"
}

$packRoot = Resolve-WorkspacePath $OutputDirectory -AllowMissing -Directory
$candidateRoot = Join-Path $packRoot 'evidence\candidate'
$modsRoot = Join-Path $packRoot 'Mods'
New-Item -ItemType Directory -Path $candidateRoot,$modsRoot -Force | Out-Null

$candidate = & $candidateGenerator -OutputDirectory $candidateRoot -FxcPath $FxcPath
$candidateManifest = Get-Content -Raw -LiteralPath $candidate.Manifest | ConvertFrom-Json
if ($candidateManifest.shaderHash -ne 'e2aa1c8cb39e0a55' -or $candidateManifest.stage -ne 'ps') {
    throw 'The source candidate does not target the verified reflection/indirect consumer.'
}
if ($candidateManifest.runtimeAdapterEligible -ne $false -or $candidateManifest.liveStatus -ne 'not-staged' -or $candidateManifest.controlReservation.bindingsEmitted -ne $false) {
    throw 'The source AO candidate is not fail-closed and offline-only.'
}

$shaderName = [IO.Path]::GetFileName($candidate.Source)
$packShaderPath = Join-Path $modsRoot $shaderName
$iniPath = Join-Path $modsRoot 'IntergradeRebirthFallbackAOF2Test.ini'
$manifestPath = Join-Path $packRoot 'manifest.json'
Copy-Item -LiteralPath $candidate.Source -Destination $packShaderPath -Force

$ini = @"
; Offline FF7 Remake Rebirth-derived fallback-AO test pack. Not installed by this tool.
; F2 OFF (0) executes the native e2aa reflection/indirect shader.
; F2 ON (1) runs the donor-derived fallback-AO consumer candidate.
; F1 is intentionally absent; it is reserved for the future global mod switch.

[KeyIntergradeRebirthFallbackAOF2Test]
key = no_modifiers F2
type = cycle
smart = true
`$intergrade_rebirth_fallback_ao_f2_test = 0, 1

[CustomShaderIntergradeRebirthFallbackAOCandidate]
ps = $shaderName
handling = skip
draw = from_caller

[ShaderOverrideIntergradeRebirthFallbackAOF2Test]
hash = e2aa1c8cb39e0a55
allow_duplicate_hash = true
if `$intergrade_rebirth_fallback_ao_f2_test == 1
    run = CustomShaderIntergradeRebirthFallbackAOCandidate
endif
"@ -replace "`r?`n", "`r`n"

if ([regex]::Matches($ini, '(?im)^\s*key\s*=\s*no_modifiers\s+F2\s*$').Count -ne 1) { throw 'Offline pack must emit exactly one unmodified F2 key.' }
if ($ini -match '(?im)^\s*key\s*=.*(?:F1|F3|PAGEUP|PAGEDOWN)\s*$') { throw 'Offline pack claimed a forbidden control key.' }
if ([regex]::Matches($ini, '(?im)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$').Count -ne 1) { throw 'Offline pack must target exactly one reflection/indirect override.' }
if ($ini -match '(?im)^\s*hash\s*=\s*a77b589dce5822d6\s*$') { throw 'Superseded temporal-AO producer leaked into the corrected pack.' }
if ($ini -notmatch '(?ms)^if \$intergrade_rebirth_fallback_ao_f2_test == 1\r?\n\s+run = CustomShaderIntergradeRebirthFallbackAOCandidate\r?\nendif\s*$') {
    throw 'Offline pack does not gate the candidate exclusively on F2 ON.'
}
[IO.File]::WriteAllText($iniPath, $ini.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

$relative = { param([string]$Path) $Path.Substring($repoRoot.Length + 1).Replace('\','/') }
$displayPath = {
    param([string]$Path)
    if ($Path.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { & $relative $Path } else { $Path }
}
$manifest = [ordered]@{
    schemaVersion = 1
    adapter = 'FF7RemakeIntergrade'
    effect = 'rebirth-native-ssao-fallback-consumer-f2-test'
    shaderHash = 'e2aa1c8cb39e0a55'
    stage = 'ps'
    donorFamily = 'ReflectionEnvironment'
    donorMode = 'native SSAO fallback subset; no GTVB SSGI or bounce light'
    status = 'offline-staging-pack-not-installed'
    runtimeEligible = $false
    installationPerformed = $false
    liveGameDirectoryTouched = $false
    keyContract = [ordered]@{
        F1 = 'not claimed; future global mod on/off'
        F2 = 'binary native/candidate test toggle'
        F3 = 'not claimed; unassigned'
        defaultState = 0
        off = 'native e2aa1c8cb39e0a55 game shader fallthrough'
        on = 'Rebirth fallback-AO consumer candidate'
    }
    overrideContract = [ordered]@{
        candidateRunsOnlyWhen = '$intergrade_rebirth_fallback_ao_f2_test == 1'
        offBranchHasReplacementRun = $false
        handling = 'skip only inside candidate CustomShader'
        draw = 'from_caller'
        directLightAOConsumersChanged = $false
        temporalAOProducerChanged = $false
    }
    conflictAudit = [ordered]@{
        roots = @($resolvedConflictRoots | ForEach-Object { & $displayPath $_ })
        externalReadOnlyScan = @($resolvedConflictRoots | Where-Object { -not $_.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        iniFilesScanned = $runtimeIniFiles.Count
        activeF2OrConsumerHashConflictsFound = 0
    }
    ini = & $relative $iniPath
    iniSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $iniPath).Hash
    shader = & $relative $packShaderPath
    shaderSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $packShaderPath).Hash
    candidateManifest = & $relative $candidate.Manifest
    candidateManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidate.Manifest).Hash
    compiledObject = & $relative $candidate.Object
    compiledObjectSha256 = $candidate.ObjectSha256
    nextGate = 'explicit reviewed live staging, shader reload, then fixed-camera F2 OFF/ON capture'
}
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    PackRoot = $packRoot
    Ini = $iniPath
    Shader = $packShaderPath
    Manifest = $manifestPath
    IniSha256 = $manifest.iniSha256
    ShaderSha256 = $manifest.shaderSha256
    ObjectSha256 = $candidate.ObjectSha256
    Installed = $false
}
