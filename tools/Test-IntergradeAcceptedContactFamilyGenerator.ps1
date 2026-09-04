[CmdletBinding()]
param(
    [string]$AcceptedFamilyRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\accepted-contact-family-rebuild-20260904-v2-portable')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$accepted = [IO.Path]::GetFullPath($AcceptedFamilyRoot).TrimEnd('\')
if (-not $accepted.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) {
    throw 'AcceptedFamilyRoot must remain below workspace artifacts.'
}
$acceptedIni = Join-Path $accepted 'ContactShadowFamily.ini'
$acceptedReport = Join-Path $accepted 'family-generation.json'
foreach ($path in @($acceptedIni,$acceptedReport)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Accepted family evidence is missing: $path" }
}
$acceptedManifest = Get-Content -Raw -LiteralPath $acceptedReport | ConvertFrom-Json
if ($acceptedManifest.kind -ne 'ff7-remake-accepted-contact-shadow-family-generator' -or
    $acceptedManifest.schemaVersion -ne 2 -or
    [bool]$acceptedManifest.liveFilesModified) {
    throw 'Accepted family generation report has an invalid contract.'
}

$temp = Join-Path $artifacts ('.tmp-contact-family-generator-' + [guid]::NewGuid().ToString('N'))
try {
    & (Join-Path $PSScriptRoot 'New-IntergradeAcceptedContactShadowFamilyIni.ps1') -OutputDirectory $temp | Out-Null
    $generatedIni = Join-Path $temp 'ContactShadowFamily.ini'
    $generatedReport = Join-Path $temp 'family-generation.json'
    $generated = Get-Content -Raw -LiteralPath $generatedReport | ConvertFrom-Json

    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $generatedIni).Hash -ne
        (Get-FileHash -Algorithm SHA256 -LiteralPath $acceptedIni).Hash) {
        throw 'Fresh tracked-input generation is not byte-identical to the accepted family.'
    }
    if ($generated.outputIniSha256 -ne 'F86A81DEE319C6A6E98933D4AC99C0477B6E5D8B43E6F7D29272FDDA476B5478') {
        throw 'Accepted family INI hash changed.'
    }
    $trackedRoot = [IO.Path]::GetFullPath((Join-Path $root 'working-code\Contact shadows - Rebirth Mod - Code worked\working-remake-port\payload\ShaderFixes')).TrimEnd('\')
    if (-not [string]::Equals([string]$generated.baseCheckpoint,$trackedRoot,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Generator no longer uses the tracked first-working payload.'
    }
    foreach ($variant in @($generated.variants)) {
        if ([string]::IsNullOrWhiteSpace([string]$variant.firstWorkingCanonicalLfSha256) -or
            $variant.firstWorkingCanonicalLfSha256 -ne $variant.firstWorkingSha256 -or
            [string]::IsNullOrWhiteSpace([string]$variant.firstWorkingWorkingTreeSha256)) {
            throw "Canonical/working-tree provenance is incomplete: $($variant.shaderHash)"
        }
    }
    if ($generated.frustumCheckpointCanonicalLfSha256 -ne 'A381CB443608CA44528B20C8BE6657B74FC2A7AB340C4C0E23282780A17A8D3D' -or
        [string]::IsNullOrWhiteSpace([string]$generated.frustumCheckpointWorkingTreeSha256)) {
        throw 'Frustum canonical/working-tree provenance is incomplete.'
    }
}
finally {
    if (Test-Path -LiteralPath $temp) {
        $resolved = [IO.Path]::GetFullPath($temp)
        if (-not $resolved.StartsWith($artifacts + '\.tmp-contact-family-generator-',[StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing unsafe temporary cleanup.'
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

Write-Host 'PASS: a fresh family generated from tracked files is byte-identical to the accepted five-shader 3+1+1 family, with LF/CRLF-independent canonical provenance and no live writes.'
