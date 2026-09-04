[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Balanced','Strong')]
    [string]$Preset,
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-temporal-power-f2-test-pack'),
    [string[]]$ConflictScanRoots,
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$candidateGenerator = Join-Path $repoRoot 'tools\New-IntergradeTemporalAOCandidate.ps1'

function Resolve-WorkspacePath([string]$Path, [switch]$AllowMissing, [switch]$Directory) {
    $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $repoRoot $Path)) }
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Path must remain inside the project workspace: $full" }
    if (-not $AllowMissing) {
        $pathType = if ($Directory) { 'Container' } else { 'Leaf' }
        if (-not (Test-Path -LiteralPath $full -PathType $pathType)) { throw "Required path does not exist: $full" }
    }
    $full
}

if ($null -eq $ConflictScanRoots -or $ConflictScanRoots.Count -eq 0) {
    $ConflictScanRoots = @((Join-Path $repoRoot 'runtime\Intergrade\Mods'))
}
$resolvedConflictRoots = @($ConflictScanRoots | ForEach-Object { Resolve-WorkspacePath $_ -Directory })
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
        if ($line -match '(?i)(?<![A-Z0-9_])(?:VK_)?F2(?![A-Z0-9_])' -or $line -match '(?i)^\s*hash\s*=\s*a77b589dce5822d6\s*$') {
            $conflicts.Add([pscustomobject]@{ path=$iniFile.FullName; line=$lineNumber; text=$line.Trim() })
        }
    }
}
if ($conflicts.Count -ne 0) {
    throw "Refusing F2 AO pack because the scanned runtime already claims F2 or a77b589dce5822d6: $($conflicts | ConvertTo-Json -Compress)"
}

$outputRoot = Resolve-WorkspacePath $OutputDirectory -AllowMissing -Directory
$packRoot = Join-Path $outputRoot $Preset
$candidateRoot = Join-Path $packRoot 'evidence\candidate'
$modsRoot = Join-Path $packRoot 'Mods'
New-Item -ItemType Directory -Path $candidateRoot,$modsRoot -Force | Out-Null

$candidate = & $candidateGenerator -Preset $Preset -OutputDirectory $candidateRoot -FxcPath $FxcPath
$candidateManifest = Get-Content -Raw -LiteralPath $candidate.Manifest | ConvertFrom-Json
if ($candidateManifest.runtimeEligible -ne $false -or $candidateManifest.installStatus -ne 'offline-not-installed' -or $candidateManifest.hotkeysEmitted -ne $false) {
    throw 'The source AO candidate is not fail-closed and offline-only.'
}
if ($candidateManifest.futureControlPlan.F2 -ne 'test toggle: staged candidate off/on' -or $candidateManifest.futureControlOwnership.F1 -ne 'global') {
    throw 'The source AO candidate control contract is stale.'
}

$shaderName = [IO.Path]::GetFileName($candidate.Source)
$packShaderPath = Join-Path $modsRoot $shaderName
$iniPath = Join-Path $modsRoot 'IntergradeTemporalAOF2Test.ini'
$manifestPath = Join-Path $packRoot 'manifest.json'
Copy-Item -LiteralPath $candidate.Source -Destination $packShaderPath -Force

$ini = @"
; Offline FF7 Remake temporal-AO live-test pack. Not installed by this tool.
; F2 OFF (0) executes the native game shader. F2 ON (1) runs the staged $Preset candidate.
; F1 is intentionally absent; it is reserved for the future global mod switch.

[KeyIntergradeTemporalAOF2Test]
key = no_modifiers F2
type = cycle
smart = true
`$intergrade_temporal_ao_f2_test = 0, 1

[CustomShaderIntergradeTemporalAOF2Candidate]
ps = $shaderName
handling = skip
draw = from_caller

[ShaderOverrideIntergradeTemporalAOF2Test]
hash = a77b589dce5822d6
allow_duplicate_hash = true
if `$intergrade_temporal_ao_f2_test == 1
    run = CustomShaderIntergradeTemporalAOF2Candidate
endif
"@ -replace "`r?`n", "`r`n"

if ([regex]::Matches($ini, '(?im)^\s*key\s*=\s*no_modifiers\s+F2\s*$').Count -ne 1) { throw 'Offline pack must emit exactly one unmodified F2 key.' }
if ($ini -match '(?im)^\s*key\s*=.*(?:F1|F3|PAGEUP|PAGEDOWN)\s*$') { throw 'Offline pack claimed a forbidden control key.' }
if ([regex]::Matches($ini, '(?im)^\s*hash\s*=\s*a77b589dce5822d6\s*$').Count -ne 1) { throw 'Offline pack must target exactly one temporal-AO override.' }
if ($ini -notmatch '(?ms)^if \$intergrade_temporal_ao_f2_test == 1\r?\n\s+run = CustomShaderIntergradeTemporalAOF2Candidate\r?\nendif\s*$') {
    throw 'Offline pack does not gate the candidate exclusively on F2 ON.'
}
[IO.File]::WriteAllText($iniPath, $ini.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

$relative = { param([string]$Path) $Path.Substring($repoRoot.Length + 1).Replace('\','/') }
$manifest = [ordered]@{
    schemaVersion = 1
    adapter = 'FF7RemakeIntergrade'
    effect = 'temporal-ssao-current-visibility-power-f2-test'
    shaderHash = 'a77b589dce5822d6'
    stage = 'ps'
    preset = $Preset
    power = [double]$candidate.Power
    status = 'offline-staging-pack-not-installed'
    runtimeEligible = $false
    installationPerformed = $false
    liveGameDirectoryTouched = $false
    keyContract = [ordered]@{
        F1 = 'not claimed; future global mod on/off'
        F2 = 'binary native/candidate test toggle'
        F3 = 'not claimed; unassigned'
        defaultState = 0
        off = 'native game shader fallthrough'
        on = "$Preset power $($candidate.Power) candidate"
    }
    overrideContract = [ordered]@{
        candidateRunsOnlyWhen = '$intergrade_temporal_ao_f2_test == 1'
        offBranchHasReplacementRun = $false
        handling = 'skip only inside candidate CustomShader'
        draw = 'from_caller'
    }
    conflictAudit = [ordered]@{
        roots = @($resolvedConflictRoots | ForEach-Object { & $relative $_ })
        iniFilesScanned = $runtimeIniFiles.Count
        activeF2OrAOHashConflictsFound = 0
    }
    ini = & $relative $iniPath
    iniSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $iniPath).Hash
    shader = & $relative $packShaderPath
    shaderSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $packShaderPath).Hash
    candidateManifest = & $relative $candidate.Manifest
    candidateManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidate.Manifest).Hash
    compiledObject = & $relative $candidate.Object
    compiledObjectSha256 = $candidate.ObjectSha256
    nextGate = 'explicit reviewed stage into project/live Mods, F10 reload, then fixed-camera F2 OFF/ON capture'
}
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Preset = $Preset
    Power = [double]$candidate.Power
    PackRoot = $packRoot
    Ini = $iniPath
    Shader = $packShaderPath
    Manifest = $manifestPath
    IniSha256 = $manifest.iniSha256
    ShaderSha256 = $manifest.shaderSha256
    ObjectSha256 = $candidate.ObjectSha256
    Installed = $false
}
