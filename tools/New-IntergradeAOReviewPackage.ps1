[CmdletBinding()]
param(
    [string]$CandidateDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-rebirth-fallback-consumer-variants'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-reviewed-integration-20260901-v1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts'))

function Resolve-ArtifactPath([string]$Path, [switch]$AllowMissing) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($artifactsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "AO review paths must remain beneath artifacts: $full" }
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full)) { throw "AO review input is missing: $full" }
    $full
}
function Relative-Path([string]$Path) { ([IO.Path]::GetFullPath($Path)).Substring($repoRoot.Length + 1).Replace('\','/') }

$candidateFull = Resolve-ArtifactPath $CandidateDirectory
$outputFull = Resolve-ArtifactPath $OutputDirectory -AllowMissing
$architecturePath = Join-Path $artifactsRoot 'analysis\remake-ao-architecture-map.json'
$rebirthPath = Join-Path $artifactsRoot 'analysis\rebirth-v2.2.1-ao-architecture.json'
$architecture = Get-Content -Raw -LiteralPath $architecturePath | ConvertFrom-Json
$rebirth = Get-Content -Raw -LiteralPath $rebirthPath | ConvertFrom-Json
if ($architecture.result -ne 'pass' -or $rebirth.result -ne 'pass') { throw 'AO architecture evidence is not in a passing state.' }

$expected = [ordered]@{
    Balanced = [ordered]@{ base='RebirthFallbackAOBalanced_ps'; sourceSha256='401B30B75A5712BE638B58D43AC634D430813F191F6079C64A4F991781BA7908'; objectSha256='75386D0682553F8C705DA47DC1D57F3FE5F8B8AB97BBB80B8BEFF35499E9DC54' }
    Strong = [ordered]@{ base='RebirthFallbackAOStrong_ps'; sourceSha256='4F2A4B756D912272DDAC6737EFC899D546124B5FD2EA1417A953983411A7FC86'; objectSha256='52199A5565EFDC836A20D982542D24280DF9FE11A1F349FD6DAADB6BAA76712A' }
}

[void](New-Item -ItemType Directory -Force -Path $outputFull)
$candidateOutput = Join-Path $outputFull 'candidates'
[void](New-Item -ItemType Directory -Force -Path $candidateOutput)
$records = @()
foreach ($preset in $expected.Keys) {
    $spec = $expected[$preset]
    $manifestPath = Join-Path $candidateFull "$($spec.base).json"
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    if ($manifest.preset -ne $preset -or $manifest.shaderHash -ne 'e2aa1c8cb39e0a55' -or $manifest.runtimeEligible -ne $false -or $manifest.hotkeysEmitted -ne $false) { throw "$preset candidate manifest is not review-safe." }
    $files = @()
    foreach ($extension in @('hlsl','cso','asm','json')) {
        $sourcePath = Join-Path $candidateFull "$($spec.base).$extension"
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "$preset candidate file is missing: $extension" }
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash
        if ($extension -eq 'hlsl' -and $hash -ne $spec.sourceSha256) { throw "$preset source hash changed." }
        if ($extension -eq 'cso' -and $hash -ne $spec.objectSha256) { throw "$preset object hash changed." }
        $destinationPath = Join-Path $candidateOutput ([IO.Path]::GetFileName($sourcePath))
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        $files += [ordered]@{ path=Relative-Path $destinationPath; sha256=$hash }
    }
    $records += [ordered]@{ preset=$preset; futureKey=if($preset -eq 'Balanced'){'F2'}else{'F3'}; shaderHash='e2aa1c8cb39e0a55'; stage='ps'; sourceSha256=$spec.sourceSha256; objectSha256=$spec.objectSha256; files=$files }
}

$runtimeRoots = @((Join-Path $repoRoot 'runtime'), (Join-Path $artifactsRoot 'intergrade-runtime'), (Join-Path $artifactsRoot 'generated-runtime'))
$conflicts = @()
foreach ($root in $runtimeRoots) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
    foreach ($ini in Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ini' | Sort-Object FullName) {
        $lineNumber = 0
        foreach ($line in Get-Content -LiteralPath $ini.FullName) {
            $lineNumber++
            if ($line -match '^\s*;' -or $line -notmatch '(?i)(?<![A-Z0-9_])(?:VK_)?F[123](?![A-Z0-9_])') { continue }
            $conflicts += [ordered]@{ path=Relative-Path $ini.FullName; line=$lineNumber; text=$line.Trim() }
        }
    }
}

$liveTestPath = Join-Path $outputFull 'live-test-plan.md'
$liveTest = @'
# AO live-test plan (review required; do not install yet)

This package contains no INI, key binding, installer, or live-game path. Integration remains blocked until the recorded F1/F2/F3 conflicts are cleared by their owner and the main task reviews the package.

After review, map only F1 = Original/native, F2 = Balanced, and F3 = Strong. Keep Page Down, Page Up, and F10 unchanged.

1. Use one fixed camera and fixed resolution/settings. Capture F1, F2, and F3 after temporal history settles for at least two seconds.
2. Repeat on wall/floor corners, cloth, thin rails, foliage, moving geometry, and near/mid/far geometry indoors and outdoors.
3. Include Cloud and another character with hair, skin, and eyes. Reject eye sockets, hair cards, or facial indirect light that crushes or flickers.
4. Fast-pan and force a camera cut. Reject trails, history pumping, halos, shimmer, or a strength difference that grows over settled frames.
5. Verify the five tiled direct-light AO consumers, capsule occlusion, contact shadows, SSR radiance/hit behavior, and Page Up/Page Down lighting behavior are unchanged.
6. Record GPU timing for Original/Balanced/Strong and identify the active e2aa family/permutation. Stop on an unmatched later-region permutation.

Expected result: Balanced moderately deepens ambient/reflection creases; Strong reproduces the donor native-ScreenAO fallback strength. Neither adds new AO reach, rays, geometry detail, SSGI, or bounce light.
'@
[IO.File]::WriteAllText($liveTestPath, ($liveTest.Trim() + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

$manifest = [ordered]@{
    schemaVersion=1
    package='FF7 Remake Intergrade AO reviewed integration candidate'
    reviewStatus='ready-for-root-review'
    integrationReady=($conflicts.Count -eq 0)
    integrationBlocked=($conflicts.Count -ne 0)
    blockReason=if($conflicts.Count -ne 0){'Reserved F1/F2/F3 control conflict exists; do not integrate until its owner resolves it.'}else{$null}
    controls=[ordered]@{ F1='Original/native AO'; F2='Balanced'; F3='Strong'; PageDown='owned by main lighting/contact task'; PageUp='owned by main lighting experiment'; F10='3Dmigoto reload' }
    bindingsEmitted=$false
    iniFilesEmitted=$false
    installerEmitted=$false
    liveGameTouched=$false
    dxvkTouched=$false
    target=[ordered]@{ shaderHash='e2aa1c8cb39e0a55'; stage='ps_5_0'; exactSourceSha256='E82E8D7A5EF91FD954B50A95CBC250B08F43B28C91450B9EC2106A82478A6716'; matchPolicy='exact/fail-closed' }
    candidates=$records
    controlConflicts=$conflicts
    evidence=@(
        [ordered]@{ path=Relative-Path $architecturePath; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $architecturePath).Hash },
        [ordered]@{ path=Relative-Path $rebirthPath; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $rebirthPath).Hash }
    )
    expectedVisual=[ordered]@{ Balanced='moderate ambient/reflection-only AO contrast'; Strong='literal donor native-ScreenAO fallback strength'; NotExpected='new AO reach, rays, SSGI detail, bounce light, or changed direct-light/contact/capsule shading' }
    rejectionRisks=@('temporal ghosting or pumping','thin-geometry halos or shimmer','hair/skin/eye over-darkening','crushed indirect detail','SSR/reflection regression','later-region family mismatch','unexpected direct-light/contact/capsule change')
    liveTestPlan=Relative-Path $liveTestPath
}
$manifestPath = Join-Path $outputFull 'review-manifest.json'
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 16) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Host "PASS: wrote offline AO review package to $outputFull (integrationReady=$($manifest.integrationReady))"
