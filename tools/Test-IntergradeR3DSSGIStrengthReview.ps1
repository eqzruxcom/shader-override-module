[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$generator = Join-Path $root 'tools\New-IntergradeR3DSSGIStrengthReview.ps1'
$canonicalSource = Join-Path $root 'src\Adapters\FF7RemakeIntergrade\R3DSSGICompositeE2AA_ps.hlsl'
$testRoot = Join-Path $root ('artifacts\agent2-r3d-ssgi-strength-review-test\' + [guid]::NewGuid().ToString('N'))
$first = Join-Path $testRoot 'first'
$second = Join-Path $testRoot 'second'
$canonicalHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $canonicalSource).Hash

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
    if ($a.Count -ne 7 -or $b.Count -ne 7) { throw 'Strength review must contain six compiled payload files plus one manifest.' }
    if (($a | ConvertTo-Json -Compress) -ne ($b | ConvertTo-Json -Compress)) { throw 'Strength-review generation is not deterministic.' }

    $manifest = Get-Content -Raw -LiteralPath (Join-Path $first 'manifest.json') | ConvertFrom-Json
    if ($manifest.classification -ne 'offline-indirect-lighting-strength-review-no-bindings' -or
        $manifest.strengths.Balanced -ne 1.0 -or $manifest.strengths.Strong -ne 1.25 -or
        [Math]::Abs([double]$manifest.strengths.balancedToStrongRatio - 0.8) -gt 1e-12 -or
        $manifest.separation.ambientOcclusionChanged -ne $false -or $manifest.separation.indirectDiffuseOnly -ne $true -or
        $manifest.evidence.r3d.defaultIntensity -ne 1.0 -or $manifest.evidence.rebirth.characterBoost -ne 1.0 -or
        $manifest.evidence.rebirth.directlyTransplanted -ne $false -or @($manifest.variants).Count -ne 2 -or
        @($manifest.files).Count -ne 6 -or $manifest.policy.iniEmitted -ne $false -or
        $manifest.policy.keyBindingsEmitted -ne $false -or $manifest.policy.liveTestsPerformed -ne $false -or
        $manifest.policy.runtimeEligible -ne $false -or $manifest.policy.installed -ne $false -or
        $manifest.policy.gameFilesTouched -ne $false) {
        throw 'Strength-review manifest policy or evidence contract failed.'
    }

    $strong = Get-Content -Raw -LiteralPath (Join-Path $first 'Agent2R3DSSGICompositeStrong_ps.hlsl')
    $balanced = Get-Content -Raw -LiteralPath (Join-Path $first 'Agent2R3DSSGICompositeBalanced_ps.hlsl')
    $canonical = Get-Content -Raw -LiteralPath $canonicalSource
    if ($strong -cne $canonical) { throw 'Strong review source is not the unchanged current diagnostic.' }
    if ($balanced -notmatch 'AGENT2_DIAGNOSTIC_STRENGTH\s*=\s*1\.00' -or
        $balanced -notmatch "R3D's donor-neutral 1\.0 intensity" -or
        $balanced -match '(?i)ambient.?occlusion|screen.?ao|\[Key|key\s*=|VK_F[123]') {
        throw 'Balanced source is not an isolated indirect-lighting strength derivative.'
    }
    $expectedBalanced = $canonical.Replace('static const float AGENT2_DIAGNOSTIC_STRENGTH = 1.25;','static const float AGENT2_DIAGNOSTIC_STRENGTH = 1.00;')
    $oldComment = "    // F2 ON remains an intentionally visible diagnostic until live exposure,`r`n    // motion/disocclusion, and GPU timing captures support a promoted strength."
    if (-not $expectedBalanced.Contains($oldComment)) { $oldComment = "    // F2 ON remains an intentionally visible diagnostic until live exposure,`n    // motion/disocclusion, and GPU timing captures support a promoted strength." }
    $expectedBalanced = $expectedBalanced.Replace($oldComment,"    // Offline Balanced review uses R3D's donor-neutral 1.0 intensity.`n    // This source has no INI or runtime binding.")
    if ($balanced -cne $expectedBalanced) { throw 'Balanced derivative changed math outside its strength declaration.' }

    foreach ($fileName in @('Agent2R3DSSGICompositeBalanced_ps.obj','Agent2R3DSSGICompositeStrong_ps.obj')) {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $first $fileName))
        if ($bytes.Length -lt 4 -or [Text.Encoding]::ASCII.GetString($bytes,0,4) -ne 'DXBC') { throw "$fileName is not DXBC." }
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $first 'Agent2R3DSSGICompositeBalanced_ps.obj')).Hash -eq
        (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $first 'Agent2R3DSSGICompositeStrong_ps.obj')).Hash) {
        throw 'Balanced and Strong DXBC objects unexpectedly match.'
    }

    foreach ($radiance in @(0.01,0.1,0.5,2.0,8.0)) {
        foreach ($receiverDiffuse in @(0.05,0.25,0.75,1.0)) {
            $balancedResult = $radiance * $receiverDiffuse * 1.0
            $strongResult = $radiance * $receiverDiffuse * 1.25
            if ([Math]::Abs(($balancedResult / $strongResult) - 0.8) -gt 1e-12) { throw 'Scalar strength transfer ratio changed.' }
        }
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $canonicalSource).Hash -ne $canonicalHash) { throw 'Canonical Strong source changed during offline generation.' }

    [pscustomobject]@{
        Result = 'pass'
        DeterministicFiles = $a.Count
        Balanced = 1.0
        Strong = 1.25
        BalancedEnergyRelativeToStrong = 0.8
        AmbientOcclusionChanged = $false
        IniEmitted = $false
        KeyBindingsEmitted = $false
        LiveTestsPerformed = $false
        RuntimeEligible = $false
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
