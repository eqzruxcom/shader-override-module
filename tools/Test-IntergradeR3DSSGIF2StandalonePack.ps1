[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$generator = Join-Path $root 'tools\New-IntergradeR3DSSGIF2StandalonePack.ps1'
$ownerPack = Join-Path $root 'artifacts\agent2-r3d-ssgi-f2-owner-integration-pack'
$ownerManifestPath = Join-Path $ownerPack 'manifest.json'
$topologyPath = Join-Path $root 'artifacts\analysis\agent2-r3d-ssgi-live-topology.json'
$testBase = Join-Path $root 'artifacts\agent2-r3d-ssgi-f2-standalone-pack-test'
$runRoot = Join-Path $testBase ([Guid]::NewGuid().ToString('N'))
$first = Join-Path $runRoot 'first'
$second = Join-Path $runRoot 'second'

function Get-TreeHashes([string]$Path) {
    $map = [ordered]@{}
    foreach ($file in Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName) {
        $map[[IO.Path]::GetRelativePath($Path, $file.FullName)] = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
    }
    $map
}

function Assert-MapsEqual([Collections.IDictionary]$Expected, [Collections.IDictionary]$Actual, [string]$Label) {
    if ([string]::Join([Environment]::NewLine, $Expected.Keys) -cne [string]::Join([Environment]::NewLine, $Actual.Keys)) {
        throw "$Label inventory differs."
    }
    foreach ($key in $Expected.Keys) {
        if ($Expected[$key] -ne $Actual[$key]) { throw "$Label differs: $key" }
    }
}

$ownerBefore = Get-TreeHashes $ownerPack
$topologyBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $topologyPath).Hash
try {
    & $generator -OutputDirectory $first | Out-Null
    & $generator -OutputDirectory $second | Out-Null
    $firstHashes = Get-TreeHashes $first
    $secondHashes = Get-TreeHashes $second
    Assert-MapsEqual $firstHashes $secondHashes 'Standalone pack'
    if ($firstHashes.Count -ne 8) { throw "Standalone pack must contain seven payloads plus one manifest; found $($firstHashes.Count)." }

    $iniPath = Join-Path $first 'Mods\Agent2R3DSSGITest.ini'
    $ini = Get-Content -Raw -LiteralPath $iniPath
    if ([regex]::Matches($ini, '(?im)^\s*key\s*=\s*no_modifiers\s+F1\s*$').Count -ne 0) { throw 'Standalone pack bound reserved F1.' }
    if ([regex]::Matches($ini, '(?im)^\s*key\s*=\s*no_modifiers\s+F2\s*$').Count -ne 1) { throw 'Standalone pack must bind F2 exactly once.' }
    if ([regex]::Matches($ini, '(?im)^\s*key\s*=\s*no_modifiers\s+F3\s*$').Count -ne 0) { throw 'Standalone pack changed the live F3-unbound state.' }
    if ([regex]::Matches($ini, '(?im)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$').Count -ne 1) { throw 'Standalone pack must own e2aa exactly once.' }
    if ($ini -match 'rebirth_ab_current|CustomShaderRebirthAB|endifif|\[ShaderOverrideRebirthABShared\]') {
        throw 'Standalone pack leaked disabled rolling-A/B owner logic.'
    }
    if ($ini -notmatch '(?ms)^\[ShaderOverrideAgent2R3DSSGIF2Test\].*?if \$agent2_ssgi_test == 1.*?ResourceAgent2SSGIOriginalT110 = reference ps-t110.*?run = CustomShaderAgent2R3DSSGITrace.*?run = CustomShaderAgent2R3DSSGIDenoise16.*?run = CustomShaderAgent2R3DSSGIDenoise8.*?run = CustomShaderAgent2R3DSSGIDenoise4.*?run = CustomShaderAgent2R3DSSGIDenoise2.*?run = CustomShaderAgent2R3DSSGIComposite.*?ps-t114 = reference ResourceAgent2SSGIOriginalT114.*?endif') {
        throw 'Standalone F2 pass or SRV preservation order is incomplete.'
    }
    if ($ini.Contains("`r`r`n")) {
        throw 'Standalone INI contains doubled carriage returns that break exact flow-control tokens.'
    }
    foreach ($slot in @(110,111,112,113,114)) {
        if ([regex]::Matches($ini, "(?m)^\[ResourceAgent2SSGIOriginalT$slot\]\r?$").Count -ne 1 -or
            [regex]::Matches($ini, "(?m)^\s*ResourceAgent2SSGIOriginalT$slot = reference ps-t$slot\r?$").Count -ne 1 -or
            [regex]::Matches($ini, "(?m)^\s*ps-t$slot = reference ResourceAgent2SSGIOriginalT$slot\r?$").Count -ne 1) {
            throw "Standalone SRV slot $slot is not declared, saved, and restored exactly once."
        }
    }

    $ownerManifest = Get-Content -Raw -LiteralPath $ownerManifestPath | ConvertFrom-Json
    foreach ($file in @($ownerManifest.files | Where-Object {$_.path -like 'Mods\Agent2R3DSSGI*.hlsl'})) {
        $name = [IO.Path]::GetFileName([string]$file.path)
        $standaloneShader = Join-Path $first ('Mods\' + $name)
        if (-not (Test-Path -LiteralPath $standaloneShader -PathType Leaf) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $standaloneShader).Hash -ne [string]$file.sha256) {
            throw "Standalone shader differs from the compiled owner pack: $name"
        }
    }

    $manifest = Get-Content -Raw -LiteralPath (Join-Path $first 'manifest.json') | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or $manifest.result -ne 'pass' -or
        $manifest.classification -ne 'offline-f2-standalone-live-topology-candidate' -or
        $manifest.target.shader -ne 'e2aa1c8cb39e0a55' -or $manifest.target.activeOwnerRequired -ne $false -or
        $manifest.baseline.activeRebirthOwnerPresent -ne $false -or
        $manifest.baseline.disabledRebirthOwner.sha256 -ne 'EFA15E2A820D6CEE6A919AD3B14B736A8ED428B9C779693FF832479B2CC40ECD' -or
        $manifest.baseline.generatedIni.sha256 -ne 'D198023FB70F9F02CC8588D3E022AA7AC43AC2BC04AA460B70353285DD065B08' -or
        $manifest.baseline.activeClaims.F1 -ne 0 -or $manifest.baseline.activeClaims.F2 -ne 0 -or
        $manifest.baseline.activeClaims.F3 -ne 0 -or $manifest.baseline.activeClaims.e2aa -ne 0 -or
        $manifest.controls.F1 -ne 'reserved and unbound' -or
        $manifest.controls.F2 -ne 'standalone SSGI candidate off/on' -or
        $manifest.controls.F3 -ne 'current live unbound state preserved' -or
        @($manifest.compile).Count -ne 6 -or @($manifest.files).Count -ne 7 -or
        $manifest.policy.exactLiveBaselineRequired -ne $true -or
        $manifest.policy.activatesDisabledOwner -ne $false -or
        $manifest.policy.runtimeEligible -ne $false -or $manifest.policy.installed -ne $false -or
        $manifest.policy.gameFilesTouched -ne $false) {
        throw 'Standalone manifest does not preserve the exact fail-closed live topology contract.'
    }

    Assert-MapsEqual $ownerBefore (Get-TreeHashes $ownerPack) 'Source owner pack'
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $topologyPath).Hash -ne $topologyBefore) {
        throw 'Live topology evidence changed during standalone generation.'
    }
    [pscustomobject]@{
        Result = 'pass'
        DeterministicFiles = $firstHashes.Count
        PayloadFiles = @($manifest.files).Count
        Shaders = @($manifest.compile).Count
        F1Reserved = $true
        F2Standalone = $true
        F3UnboundPreserved = $true
        DisabledOwnerInactive = $true
        RuntimeEligible = $false
        Installed = $false
    }
}
finally {
    if (Test-Path -LiteralPath $runRoot -PathType Container) {
        [IO.Directory]::Delete([IO.Path]::GetFullPath($runRoot), $true)
    }
}
