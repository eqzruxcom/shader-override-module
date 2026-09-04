[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $EvidenceDirectory,
    [int] $MinimumDeliveredFrames = 3,
    [int] $MinimumNeuralFrames = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts')).TrimEnd('\')
$root = [IO.Path]::GetFullPath($EvidenceDirectory).TrimEnd('\')
$manifestPath = Join-Path $root 'live-evidence.json'
if (-not $root.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing live-evidence validation outside workspace artifacts: $root"
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "live-evidence.json is missing: $manifestPath" }
if ($MinimumDeliveredFrames -lt 3 -or $MinimumNeuralFrames -lt 2) { throw 'Evidence thresholds are below their safe minima.' }

function Get-Sha256Upper {
    param([string] $Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}
function Get-RoleRecord {
    param([object[]] $Records, [string] $Role)
    $found = @($Records | Where-Object { [string]$_.role -eq $Role })
    if ($found.Count -ne 1) { throw "Expected exactly one live-evidence record for role '$Role'." }
    return $found[0]
}
function Get-RoleText {
    param([object[]] $Records, [string] $Role, [string] $Root)
    $record = Get-RoleRecord $Records $Role
    return [IO.File]::ReadAllText((Join-Path $Root ([string]$record.relativePath).Replace('/', '\')))
}
function Get-MaxCapture {
    param([string] $Text, [string] $Pattern, [int] $Group = 1)
    $matches = [regex]::Matches($Text, $Pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($matches.Count -eq 0) { return [long]-1 }
    return [long](($matches | ForEach-Object { [long]$_.Groups[$Group].Value } | Measure-Object -Maximum).Maximum)
}
function Require-Match {
    param([string] $Text, [string] $Pattern, [string] $Failure)
    if ($Text -notmatch $Pattern) { throw $Failure }
}
function Assert-Screenshot {
    param([object[]] $Records, [string] $Role, [string] $Root)
    $record = Get-RoleRecord $Records $Role
    $path = Join-Path $Root ([string]$record.relativePath).Replace('/', '\')
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -lt 1024) { throw "$Role is implausibly small." }
    $png = $bytes.Length -ge 8 -and $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4e -and $bytes[3] -eq 0x47 -and $bytes[4] -eq 0x0d -and $bytes[5] -eq 0x0a -and $bytes[6] -eq 0x1a -and $bytes[7] -eq 0x0a
    $jpeg = $bytes.Length -ge 3 -and $bytes[0] -eq 0xff -and $bytes[1] -eq 0xd8 -and $bytes[2] -eq 0xff
    $bmp = $bytes.Length -ge 2 -and $bytes[0] -eq 0x42 -and $bytes[1] -eq 0x4d
    if (-not ($png -or $jpeg -or $bmp)) { throw "$Role does not have a supported image signature." }
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.kind -ne 'fallout-new-vegas-dlss5-live-evidence' -or
    $manifest.adapter -ne 'FalloutNewVegas' -or [string]$manifest.phase -notin @('transport', 'neural')) {
    throw 'Evidence manifest identity is invalid.'
}
if ($manifest.policy.synthetic -ne $false -or $manifest.policy.gameDirectoryRetained -ne $false -or
    $manifest.policy.rawLogsRetained -ne $true -or $manifest.policy.frameGenerationIncluded -ne $false) {
    throw 'Evidence policy is missing or unsafe.'
}
$started = [DateTimeOffset]$manifest.run.startedUtc
$ended = [DateTimeOffset]$manifest.run.endedUtc
if ($ended -le $started -or $ended -gt [DateTimeOffset]::UtcNow.AddMinutes(10)) { throw 'Evidence run interval is invalid.' }
if ([string]$manifest.binding.packageId -eq '' -or [string]$manifest.binding.packageManifestSha256 -notmatch '^[0-9A-Fa-f]{64}$' -or
    [string]$manifest.binding.installReceiptSha256 -notmatch '^[0-9A-Fa-f]{64}$' -or
    [string]$manifest.binding.gameExecutableSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
    throw 'Evidence is not bound to a package, install receipt, and game executable.'
}

$records = @($manifest.files)
$paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$roles = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($record in $records) {
    $relative = [string]$record.relativePath
    $role = [string]$record.role
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative.Contains(':') -or
        $relative -match '(^|[\\/])\.\.([\\/]|$)' -or -not $paths.Add($relative)) { throw "Unsafe or duplicate evidence path: $relative" }
    if ([string]::IsNullOrWhiteSpace($role) -or -not $roles.Add($role)) { throw "Missing or duplicate evidence role: $role" }
    $path = Join-Path $root $relative.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Evidence file is missing: $relative" }
    if ((Get-Sha256Upper $path) -ne ([string]$record.sha256).ToUpperInvariant()) { throw "Evidence file hash mismatch: $relative" }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$record.sizeBytes) { throw "Evidence file size mismatch: $relative" }
}
$actual = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object FullName -ne $manifestPath | ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') })
if (@($actual | Where-Object { -not $paths.Contains($_) }).Count -ne 0) { throw 'Evidence directory contains unlisted files.' }

$requiredRoles = @('dxvkLog', 'gameReShadeLog', 'feedLog', 'feedLayerLog', 'hostLog')
if ($manifest.phase -eq 'transport') { $requiredRoles += 'transportSplitScreenshot' }
else { $requiredRoles += @('hostReShadeLog', 'neuralOffScreenshot', 'neuralOnScreenshot') }
foreach ($role in $requiredRoles) { $null = Get-RoleRecord $records $role }
foreach ($role in @($requiredRoles | Where-Object { $_ -match 'Screenshot$' })) { Assert-Screenshot $records $role $root }

$dxvk = Get-RoleText $records 'dxvkLog' $root
$gameRs = Get-RoleText $records 'gameReShadeLog' $root
$feed = Get-RoleText $records 'feedLog' $root
$layer = Get-RoleText $records 'feedLayerLog' $root
$hostLog = Get-RoleText $records 'hostLog' $root

Require-Match $dxvk '(?i)DXVK:\s*v[0-9]' 'DXVK log does not identify a DXVK runtime.'
Require-Match $dxvk '(?i)Game:\s*FalloutNV\.exe' 'DXVK log does not identify FalloutNV.exe.'
Require-Match $gameRs '(?i)ReShade[^\r\n]*[0-9]+\.[0-9]+' 'Game ReShade log has no version banner.'
Require-Match $gameRs '(?i)Vulkan' 'Game ReShade log does not prove Vulkan attachment.'
Require-Match $gameRs '(?i)dlss5-feed\.addon32' 'Game ReShade log does not prove the x86 Feeder add-on loaded.'
Require-Match $layer '(?i)VK_LAYER_feed_vk negotiated \(interface version \d+\)' 'Fallback Vulkan layer did not negotiate.'
Require-Match $layer '(?i)vkCreateDevice -> 0' 'Fallback Vulkan layer did not report a successful device creation.'

$wantedMode = if ($manifest.phase -eq 'transport') { 1 } else { 2 }
Require-Match $feed ("(?i)config: enabled=1 mode=" + $wantedMode + "\b") "Feeder log does not prove enabled mode $wantedMode."
$clientProtocolMatch = [regex]::Match($feed, '(?i)host connected \(protocol v(\d+), Vulkan client\)')
if (-not $clientProtocolMatch.Success) { throw 'Feeder log does not prove a Vulkan client/host connection.' }
$hostProtocolMatch = [regex]::Match($hostLog, '(?i)game pid \d+ connected \(protocol v(\d+), Vulkan client')
if (-not $hostProtocolMatch.Success) { throw 'Host log does not prove a Vulkan game connection.' }
if ($clientProtocolMatch.Groups[1].Value -ne $hostProtocolMatch.Groups[1].Value) { throw 'Client and host IPC protocol versions differ.' }
$sharedMatch = [regex]::Match($feed, '(?i)shared set ready \(Vulkan\):\s*(\d+)x(\d+)')
if (-not $sharedMatch.Success) { throw 'Feeder log does not prove a Vulkan shared texture set.' }
$delivered = Get-MaxCapture $feed '(?i)frame (\d+) delivered[^\r\n]*Vulkan'
$evaluated = Get-MaxCapture $hostLog '(?i)frame (\d+) evaluated'
if ($delivered -lt $MinimumDeliveredFrames -or $evaluated -lt $MinimumDeliveredFrames) {
    throw "Transport did not reach the required frame threshold (delivered=$delivered, host=$evaluated)."
}

$fatalPattern = '(?i)(### CRASH RECORDED ###|speaks protocol v\d+, this (?:add-on|host) v\d+|host died|never signalled|texture import FAILED|evaluate (?:failed|raised)|CreateFeature (?:failed|raised)|device removed|0xBAD00002|error X3506)'
foreach ($pair in @(@('feedLog', $feed), @('feedLayerLog', $layer), @('hostLog', $hostLog))) {
    if ([regex]::IsMatch([string]$pair[1], $fatalPattern)) { throw "Fatal runtime marker found in $($pair[0])." }
}

$transportPassed = $true
$neuralExecutionPassed = $false
$inputGuidesPassed = $false
$neuralFrames = [long]0
$mvNonZeroPercent = $null
$depthVariance = $null
if ($manifest.phase -eq 'transport') {
    Require-Match $hostLog '(?i)transport-only mode: Color will be copied to Output, no evaluate' 'Host log does not prove mode-1 transport-only operation.'
}
else {
    $hostRs = Get-RoleText $records 'hostReShadeLog' $root
    if ([regex]::IsMatch($hostRs, $fatalPattern)) { throw 'Fatal neural-runtime marker found in hostReShadeLog.' }
    $feature = [regex]::Match($hostLog, '(?i)feature ready:\s*(\d+)x(\d+) DLAA\b')
    if (-not $feature.Success) { throw 'Host did not create a native-resolution DLAA carrier.' }
    if ($hostLog -match '(?i)feature ready:\s*\d+x\d+\s*->\s*\d+x\d+\s+DLSS') { throw 'Evidence unexpectedly contains a Super Resolution carrier.' }
    if ($feature.Groups[1].Value -ne $sharedMatch.Groups[1].Value -or $feature.Groups[2].Value -ne $sharedMatch.Groups[2].Value) {
        throw 'DLAA carrier resolution differs from the Vulkan shared-set resolution.'
    }
    Require-Match $hostRs '(?i)signed DLSSNR 310\.8\.0[^\r\n]*runtime initialized' 'Host ReShade log does not prove signed DLSSNR 310.8 initialization.'
    Require-Match $hostRs '(?i)feature 18 created' 'Host ReShade log does not prove Feature 18 creation.'
    $neuralFrames = Get-MaxCapture $hostRs '(?i)inline feature 18 evaluation succeeded[^\r\n]*count\s*=\s*(\d+)'
    if ($neuralFrames -lt $MinimumNeuralFrames) { throw "Neural evaluation counter did not reach $MinimumNeuralFrames (max=$neuralFrames)." }
    $off = Get-RoleRecord $records 'neuralOffScreenshot'
    $on = Get-RoleRecord $records 'neuralOnScreenshot'
    if ([string]$off.sha256 -eq [string]$on.sha256) { throw 'Neural off/on screenshots are byte-identical.' }
    $neuralExecutionPassed = $true

    $mv = [regex]::Matches($feed + "`n" + $hostLog + "`n" + $hostRs, '(?i)MV probe[^\r\n]*?(\d+)% non-zero') | Select-Object -Last 1
    $depth = [regex]::Matches($feed + "`n" + $hostLog + "`n" + $hostRs, '(?i)Depth probe[^\r\n]*?variance\s+([0-9.eE+-]+)[^\r\n]*?(\d+)% finite') | Select-Object -Last 1
    if ($null -ne $mv -and $null -ne $depth) {
        $mvNonZeroPercent = [int]$mv.Groups[1].Value
        $depthVariance = [double]::Parse($depth.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
        $depthFinite = [int]$depth.Groups[2].Value
        $inputGuidesPassed = $mvNonZeroPercent -ge 2 -and $depthVariance -gt 0.0 -and $depthFinite -ge 95
    }
}

[pscustomobject]@{
    EvidenceId = [string]$manifest.evidenceId
    EvidenceRoot = $root
    Phase = [string]$manifest.phase
    PackageId = [string]$manifest.binding.packageId
    ProtocolVersion = [int]$clientProtocolMatch.Groups[1].Value
    Width = [int]$sharedMatch.Groups[1].Value
    Height = [int]$sharedMatch.Groups[2].Value
    DeliveredFrames = $delivered
    HostFrames = $evaluated
    NeuralFrames = $neuralFrames
    MotionVectorNonZeroPercent = $mvNonZeroPercent
    DepthVariance = $depthVariance
    TransportPassed = $transportPassed
    NeuralExecutionPassed = $neuralExecutionPassed
    InputGuidesPassed = $inputGuidesPassed
    FullDlss5Passed = ($neuralExecutionPassed -and $inputGuidesPassed)
    NativeResolution = ($manifest.phase -eq 'neural')
    SuperResolutionUsed = $false
    Valid = $true
}
