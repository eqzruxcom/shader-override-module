[CmdletBinding()]
param(
    [string]$TargetModsDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\Mods',
    [string]$PackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-zero-pack'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\agent2-r3d-ssgi-owned-fullscreen-reload-baseline.json'),
    [string]$ContactInstallReportPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\accepted-contact-family-live-install-20260903-132112541\install-report.json'),
    [switch]$AllowExternalTarget
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$target = [IO.Path]::GetFullPath($TargetModsDirectory).TrimEnd('\')
$pack = [IO.Path]::GetFullPath($PackRoot).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputPath)
$contactReportPath = [IO.Path]::GetFullPath($ContactInstallReportPath)
if (-not $pack.StartsWith((Join-Path $workspace 'artifacts') + '\', [StringComparison]::OrdinalIgnoreCase) -or
    -not $output.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase) -or
    -not $contactReportPath.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Pack, baseline output, and contact install report must remain inside the workspace.'
}
if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw "Target Mods directory is missing: $target" }
if (-not $target.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    if (-not $AllowExternalTarget) { throw "External target requires -AllowExternalTarget: $target" }
    if (-not $target.EndsWith('\End\Binaries\Win64\Mods', [StringComparison]::OrdinalIgnoreCase)) {
        throw "External target must be the exact FF7 Remake Win64 Mods directory: $target"
    }
}

$manifestPath = Join-Path $pack 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Owned-pack manifest is missing: $manifestPath" }
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$supportedKinds = @(
    'ff7-remake-owned-fullscreen-zero-ssgi',
    'ff7-remake-clean-owned-fullscreen-real-ssgi'
)
$manifestKind = if ($manifest.PSObject.Properties.Name -contains 'kind' -and
    -not [string]::IsNullOrWhiteSpace([string]$manifest.kind)) {
    [string]$manifest.kind
} else { 'ff7-remake-owned-fullscreen-zero-ssgi' }
$manifestVariant = if ($manifest.PSObject.Properties.Name -contains 'variant') {
    [string]$manifest.variant
} elseif ($manifestKind -eq 'ff7-remake-clean-owned-fullscreen-real-ssgi') {
    'owned-fullscreen-real-25-percent'
} else {
    ''
}
if ($manifest.schemaVersion -ne 1 -or $manifest.result -ne 'pass' -or $manifest.runtimeEligible -ne $false -or
    $manifestKind -notin $supportedKinds -or $manifest.hook -ne 'e2aa1c8cb39e0a55-ps' -or
    [string]$manifest.controls.F10 -notmatch '^native reload(?:,)? unchanged$' -or
    $manifest.ownedPass.draw -ne '3, 0' -or @($manifest.files).Count -ne 8 -or
    [string]::IsNullOrWhiteSpace($manifestVariant)) {
    throw 'Owned fullscreen pack contract is invalid.'
}

$liveFiles = [Collections.Generic.List[object]]::new()
foreach ($file in @($manifest.files)) {
    $path = Join-Path $target ([string]$file.name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Live owned-pass payload is missing: $($file.name)" }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    if ($hash -ne [string]$file.sha256 -or (Get-Item -LiteralPath $path).Length -ne [long]$file.bytes) {
        throw "Live owned-pass payload does not match the selected pack: $($file.name)"
    }
    $liveFiles.Add([ordered]@{name=[string]$file.name;sha256=$hash;bytes=[long]$file.bytes})
}
$iniPath = Join-Path $target 'Agent2R3DSSGITest.ini'
$iniText = Get-Content -Raw -LiteralPath $iniPath
if ([regex]::Matches($iniText,'(?im)^\s*key\s*=.*(?<![A-Z0-9_])F2(?![A-Z0-9_]).*$').Count -ne 1 -or
    $iniText -match '(?im)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F10(?![A-Z0-9_]).*$') {
    throw 'Owned-pass key contract is invalid.'
}
$modF10Claims = @(
    Get-ChildItem -LiteralPath $target -File -Filter '*.ini' | Where-Object {
        (Get-Content -Raw -LiteralPath $_.FullName) -match '(?im)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F10(?![A-Z0-9_]).*$'
    } | Select-Object -ExpandProperty Name
)
if ($modF10Claims.Count -ne 0) { throw "A Mods INI captures native F10: $($modF10Claims -join ', ')" }

$win64 = Split-Path -Parent $target
$logPath = Join-Path $win64 'd3d11_log.txt'
if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) { throw "3DMigoto log is missing: $logPath" }
$contactIniPath = Join-Path $target 'ContactShadows.ini'
if (-not (Test-Path -LiteralPath $contactReportPath -PathType Leaf)) { throw "Accepted contact-family install report is missing: $contactReportPath" }
$contactReport = Get-Content -Raw -LiteralPath $contactReportPath | ConvertFrom-Json
if ($contactReport.schemaVersion -ne 2 -or
    $contactReport.kind -ne 'ff7-remake-accepted-contact-family-live-install' -or
    $contactReport.installed -ne $true -or @($contactReport.failures).Count -ne 0 -or
    -not [string]::Equals([IO.Path]::GetFullPath([string]$contactReport.liveIni), $contactIniPath, [StringComparison]::OrdinalIgnoreCase) -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $contactIniPath).Hash -ne [string]$contactReport.liveIniSha256) {
    throw 'Accepted contact-family install report does not prove the current live ContactShadows.ini.'
}
$stream = [IO.File]::Open($logPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
try { $logOffset = [long]$stream.Length } finally { $stream.Dispose() }

$processes = @(Get-Process -Name 'ff7remake_' -ErrorAction Stop)
if ($processes.Count -ne 1) { throw "Expected one FF7 Remake process, found $($processes.Count)." }
$process = $processes[0]
$expectedExe = Join-Path $win64 'ff7remake_.exe'
if (-not $target.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase) -and
    -not [string]::Equals([string]$process.Path,$expectedExe,[StringComparison]::OrdinalIgnoreCase)) {
    throw "Running process is not the target FF7 executable: $($process.Path)"
}

$protected = [ordered]@{'Mods\ContactShadows.ini'=[string]$contactReport.liveIniSha256}
$protectedRecords = [Collections.Generic.List[object]]::new()
foreach ($pair in $protected.GetEnumerator()) {
    $path = Join-Path $win64 $pair.Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne $pair.Value) {
        throw "Protected accepted contact-shadow file drifted: $($pair.Key)"
    }
    $protectedRecords.Add([ordered]@{relativePath=$pair.Key;sha256=$pair.Value})
}
$backupHashByPath = @{}
foreach ($file in @($contactReport.backupFiles)) { $backupHashByPath[[string]$file.path -replace '/','\'] = [string]$file.sha256 }
$protectedAbsentRecords = [Collections.Generic.List[object]]::new()
foreach ($hash in @('08bb8764f1840179','0e97888f9a8767da','5a9fbefe0ab6f815','62b33a2d1e505241','c30cdc8365df9840')) {
    $relative = "ShaderFixes\$hash-cs.txt"
    if (Test-Path -LiteralPath (Join-Path $win64 $relative)) { throw "Graduated explicit contact replacement unexpectedly returned: $relative" }
    if (-not $backupHashByPath.ContainsKey($relative)) { throw "Accepted contact report lacks the preserved original replacement hash: $relative" }
    $protectedAbsentRecords.Add([ordered]@{relativePath=$relative;expected='absent';preservedBackupSha256=$backupHashByPath[$relative]})
}

$baseline = [ordered]@{
    schemaVersion=1
    kind='agent2-r3d-ssgi-owned-fullscreen-reload-baseline'
    classification='captured-before-F10'
    capturedUtc=[DateTime]::UtcNow.ToString('o')
    variant=$manifestVariant
    packManifest=$manifestPath
    packManifestSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash
    contactInstallReport=$contactReportPath
    contactInstallReportSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $contactReportPath).Hash
    targetModsDirectory=$target
    process=[ordered]@{id=[int]$process.Id;path=[string]$process.Path;responding=[bool]$process.Responding}
    log=[ordered]@{path=$logPath;byteOffset=$logOffset;lastWriteUtc=(Get-Item -LiteralPath $logPath).LastWriteTimeUtc.ToString('o')}
    liveFiles=@($liveFiles)
    protectedFiles=@($protectedRecords)
    protectedAbsentFiles=@($protectedAbsentRecords)
    expected=[ordered]@{
        ini='Agent2R3DSSGITest.ini'
        keySection='Agent2R3DSSGITest'
        overrideSection='Agent2R3DSSGIF2Test'
        shaderHash='e2aa1c8cb39e0a55'
        customSections=@('Agent2R3DSSGITrace','Agent2R3DSSGIDenoise16','Agent2R3DSSGIDenoise8','Agent2R3DSSGIDenoise4','Agent2R3DSSGIDenoise2','Agent2R3DSSGIComposite')
        shaders=@(
            [ordered]@{stage='ps';name='Agent2R3DSSGITraceE2AA_ps.hlsl'},
            [ordered]@{stage='ps';name='Agent2R3DSSGIDenoise16_ps.hlsl'},
            [ordered]@{stage='ps';name='Agent2R3DSSGIDenoise8_ps.hlsl'},
            [ordered]@{stage='ps';name='Agent2R3DSSGIDenoise4_ps.hlsl'},
            [ordered]@{stage='ps';name='Agent2R3DSSGIDenoise2_ps.hlsl'},
            [ordered]@{stage='ps';name='Agent2R3DSSGICompositeE2AA_ps.hlsl'},
            [ordered]@{stage='vs';name='Agent2R3DSSGIFullscreen_vs.hlsl'}
        )
    }
    modF10Claims=@($modF10Claims)
    visualResult='pending user F2 comparison'
    runtimeEligible=$false
}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,(($baseline | ConvertTo-Json -Depth 10) + "`r`n"),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{Status='captured-before-F10';Variant=$baseline.variant;ProcessId=[int]$process.Id;LogOffset=$logOffset;LiveFiles=$liveFiles.Count;ProtectedFiles=$protectedRecords.Count;ProtectedAbsentFiles=$protectedAbsentRecords.Count;ModF10Claims=$modF10Claims.Count;Output=$output}
