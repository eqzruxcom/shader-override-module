[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$generator = Join-Path $root 'tools\New-IntergradeR3DSSGIF2MaterialAwarePack.ps1'
$testRoot = Join-Path $root ('artifacts\agent2-r3d-ssgi-f2-material-aware-pack-test\' + [guid]::NewGuid().ToString('N'))
$first = Join-Path $testRoot 'first'
$second = Join-Path $testRoot 'second'

function Get-TreeHashes([string]$Path) {
    $map = [ordered]@{}
    foreach ($file in @(Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName)) {
        $map[[IO.Path]::GetRelativePath($Path,$file.FullName)] = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
    }
    $map
}

try {
    & $generator -OutputDirectory $first | Out-Null
    & $generator -OutputDirectory $second | Out-Null
    $a = Get-TreeHashes $first
    $b = Get-TreeHashes $second
    if ($a.Count -ne 8 -or ($a | ConvertTo-Json -Compress) -cne ($b | ConvertTo-Json -Compress)) {
        throw 'Material-aware standalone package is incomplete or non-deterministic.'
    }
    $manifest = Get-Content -Raw -LiteralPath (Join-Path $first 'manifest.json') | ConvertFrom-Json
    if ($manifest.classification -ne 'offline-f2-standalone-live-topology-candidate' -or
        $manifest.variant -ne 'material-aware-unlit-mask-and-rebirth-character-response' -or
        $manifest.target.shader -ne 'e2aa1c8cb39e0a55' -or @($manifest.files).Count -ne 7 -or
        $manifest.controls.F1 -ne 'reserved and unbound' -or
        $manifest.controls.F2 -ne 'standalone SSGI candidate off/on' -or
        $manifest.controls.F3 -ne 'current live unbound state preserved' -or
        $manifest.effect.receiverDiffuse -notmatch 'unlit 0 excluded' -or
        $manifest.effect.receiverDiffuse -notmatch 'quarter-scale response' -or
        $manifest.policy.runtimeEligible -or $manifest.policy.installed -or $manifest.policy.gameFilesTouched) {
        throw 'Material-aware standalone manifest contract failed.'
    }
    $ini = Get-Content -Raw -LiteralPath (Join-Path $first 'Mods\Agent2R3DSSGITest.ini')
    if ([regex]::Matches($ini,'(?im)^\s*key\s*=.*(?:VK_)?F2\s*$').Count -ne 1 -or
        [regex]::Matches($ini,'(?im)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$').Count -ne 1 -or
        $ini -match '(?im)^\s*key\s*=.*(?:VK_)?F[13]\s*$' -or $ini.Contains("`r`r`n")) {
        throw 'Material-aware standalone INI ownership or line endings changed.'
    }
    $hlsl = Get-Content -Raw -LiteralPath (Join-Path $first 'Mods\Agent2R3DSSGICompositeE2AA_ps.hlsl')
    foreach ($pattern in @('if \(shadingModel == 0u\)','shadingModel == 3u \|\| shadingModel == 7u \|\| shadingModel == 9u','materialBoost = 0\.25','AGENT2_INV_PI \* materialBoost')) {
        if ($hlsl -notmatch $pattern) { throw "Material-aware composite lost: $pattern" }
    }
    foreach ($entry in @($manifest.files)) {
        $path = Join-Path $first ([string]$entry.path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$entry.sha256) {
            throw "Material-aware payload hash failed: $($entry.path)"
        }
    }
    [pscustomobject]@{
        Result = 'pass'
        DeterministicFiles = $a.Count
        PayloadFiles = $manifest.files.Count
        F2Standalone = $true
        UnlitMasked = $true
        CharacterModelsReduced = '3,7,9 at 0.25 material boost'
        LiveFilesTouched = $false
        RuntimeEligible = $false
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
