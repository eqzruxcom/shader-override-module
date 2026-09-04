[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$generator = Join-Path $root 'tools\New-IntergradeR3DSSGIMaterialResponseReview.ps1'
$testRoot = Join-Path $root ('artifacts\agent2-r3d-ssgi-material-response-review-test\' + [guid]::NewGuid().ToString('N'))
$first = Join-Path $testRoot 'first'
$second = Join-Path $testRoot 'second'

function Get-TreeHashes([string]$Path) {
    $map = [ordered]@{}
    foreach ($file in @(Get-ChildItem -LiteralPath $Path -File | Sort-Object Name)) {
        $map[$file.Name] = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
    }
    $map
}

try {
    & $generator -OutputDirectory $first | Out-Null
    & $generator -OutputDirectory $second | Out-Null
    $a = Get-TreeHashes $first
    $b = Get-TreeHashes $second
    if ($a.Count -ne 4 -or ($a | ConvertTo-Json -Compress) -cne ($b | ConvertTo-Json -Compress)) {
        throw 'Material-response review is missing files or is not deterministic.'
    }
    $manifest = Get-Content -Raw -LiteralPath (Join-Path $first 'manifest.json') | ConvertFrom-Json
    if ($manifest.classification -ne 'offline-material-aware-ssgi-response-review-not-installed' -or
        $manifest.response.shadingModelEncoding -ne 'round(saturate(t1.w) * 255) & 0xF' -or
        $manifest.response.unlit0 -notmatch 'zero SSGI' -or
        $manifest.response.preintegratedSkin3 -notmatch 'quarter-scale' -or
        $manifest.response.hair7 -notmatch 'quarter-scale' -or
        $manifest.response.eye9 -notmatch 'quarter-scale' -or
        $manifest.response.otherLit -notmatch 'pi boost' -or
        $manifest.policy.iniEmitted -or $manifest.policy.keyBindingEmitted -or
        $manifest.policy.liveFilesTouched -or $manifest.policy.runtimeEligible -or $manifest.policy.installed) {
        throw 'Material-response manifest contract failed.'
    }
    $hlsl = Get-Content -Raw -LiteralPath (Join-Path $first 'Agent2R3DSSGICompositeMaterialAware_ps.hlsl')
    foreach ($pattern in @(
        'uint shadingModel = \(\(uint\)round\(saturate\(material\.w\) \* 255\.0\)\) & 0xFu',
        'if \(shadingModel == 0u\)',
        'shadingModel == 3u \|\| shadingModel == 7u \|\| shadingModel == 9u',
        'materialBoost = 0\.25',
        'AGENT2_INV_PI \* materialBoost'
    )) {
        if ($hlsl -notmatch $pattern) { throw "Material-response HLSL lost: $pattern" }
    }
    $bytes = [IO.File]::ReadAllBytes((Join-Path $first 'Agent2R3DSSGICompositeMaterialAware_ps.obj'))
    if ($bytes.Length -lt 4 -or [Text.Encoding]::ASCII.GetString($bytes,0,4) -ne 'DXBC') { throw 'Compiled review object is not DXBC.' }
    [pscustomobject]@{
        Result = 'pass'
        DeterministicFiles = $a.Count
        UnlitMasked = $true
        CharacterModelsReduced = '3,7,9 at 0.25 material boost'
        LiveFilesTouched = $false
        RuntimeEligible = $false
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
