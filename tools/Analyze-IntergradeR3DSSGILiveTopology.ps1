[CmdletBinding()]
param(
    [string]$TargetModsDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\Mods',
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\agent2-r3d-ssgi-live-topology.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$target = [IO.Path]::GetFullPath($TargetModsDirectory).TrimEnd('\')
if (-not $target.EndsWith('\End\Binaries\Win64\Mods', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Target must be an exact FF7 Remake Win64 Mods directory: $target"
}
if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw "Target Mods directory is missing: $target" }

function Get-Hash([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

$expected = [ordered]@{
    disabledOwner = [ordered]@{
        name = 'RebirthEffectsDX11.ini.disabled'
        sha256 = 'EFA15E2A820D6CEE6A919AD3B14B736A8ED428B9C779693FF832479B2CC40ECD'
    }
    generatedIni = [ordered]@{
        name = 'UE4EffectsGenerated.ini'
        sha256 = 'D198023FB70F9F02CC8588D3E022AA7AC43AC2BC04AA460B70353285DD065B08'
    }
}

foreach ($entry in $expected.Values) {
    $path = Join-Path $target $entry.name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Live topology fingerprint file is missing: $path" }
    $actual = Get-Hash $path
    if ($actual -ne $entry.sha256) { throw "Live topology fingerprint drifted: $($entry.name). Expected $($entry.sha256), found $actual" }
}

$activeOwner = Join-Path $target 'RebirthEffectsDX11.ini'
if (Test-Path -LiteralPath $activeOwner -PathType Leaf) { throw "Owner integration is active; standalone topology no longer applies: $activeOwner" }

$claims = [ordered]@{
    F1 = [Collections.Generic.List[object]]::new()
    F2 = [Collections.Generic.List[object]]::new()
    F3 = [Collections.Generic.List[object]]::new()
    E2aa = [Collections.Generic.List[object]]::new()
}
$activeIniFiles = @(Get-ChildItem -LiteralPath $target -Recurse -File -Filter '*.ini' | Sort-Object FullName)
foreach ($ini in $activeIniFiles) {
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $ini.FullName) {
        $lineNumber++
        if ($line -match '^\s*;') { continue }
        foreach ($key in @('F1','F2','F3')) {
            if ($line -match "(?i)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?$key(?![A-Z0-9_]).*$") {
                $claims[$key].Add([ordered]@{path=[IO.Path]::GetRelativePath($target,$ini.FullName); line=$lineNumber; text=$line.Trim()})
            }
        }
        if ($line -match '(?i)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$') {
            $claims.E2aa.Add([ordered]@{path=[IO.Path]::GetRelativePath($target,$ini.FullName); line=$lineNumber; text=$line.Trim()})
        }
    }
}
foreach ($name in @('F1','F2','F3','E2aa')) {
    if ($claims[$name].Count -ne 0) { throw "Standalone live topology requires zero active $name claims: $($claims[$name] | ConvertTo-Json -Compress)" }
}

$agent2Files = @(Get-ChildItem -LiteralPath $target -Recurse -File -Filter 'Agent2R3DSSGI*')
if ($agent2Files.Count -ne 0) { throw "Agent 2 R3D SSGI files are already present: $($agent2Files.FullName -join ', ')" }

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    classification = 'live-topology-requires-standalone-f2-hook'
    target = $target
    activeIniFiles = @($activeIniFiles | ForEach-Object {[IO.Path]::GetRelativePath($target,$_.FullName)})
    fingerprints = $expected
    activeOwnerPresent = $false
    activeClaims = [ordered]@{F1=0; F2=0; F3=0; e2aa=0}
    agent2FilesPresent = 0
    ownerIntegrationEligible = $false
    standalonePreflightEligible = $true
    readOnlyInspection = $true
    gameFilesTouched = $false
    runtimeEligible = $false
}

$outputFull = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull)) | Out-Null
[IO.File]::WriteAllText($outputFull, (($report | ConvertTo-Json -Depth 10) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Result = 'pass'
    Classification = $report.classification
    ActiveIniFiles = $activeIniFiles.Count
    F1 = 0
    F2 = 0
    F3 = 0
    E2aa = 0
    GameFilesTouched = $false
    RuntimeEligible = $false
    Output = $outputFull
}
