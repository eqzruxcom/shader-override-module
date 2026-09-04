[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\remake-ao-architecture-map.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')

function Project-Path([string]$Relative) { Join-Path $repoRoot ($Relative -replace '/', '\') }
function Require-Text([string]$Text, [string]$Pattern, [string]$Meaning) {
    if ($Text -notmatch $Pattern) { throw "Missing AO architecture evidence: $Meaning" }
}

$snapshotPath = Project-Path 'artifacts/analysis/intergrade-shader-cache-before-next-region-20260901.json'
$inventoryPath = Project-Path 'artifacts/analysis/rebirth-v2.2.1-remake-area-inventory.json'
$familyCatalogPath = Project-Path 'artifacts/analysis/rebirth-shader-injector-v2.2.1-family-catalog.json'
$producerAsmPath = Project-Path 'artifacts/captured-shaders/a77b589dce5822d6-ps/a77b589dce5822d6-ps_dumpbin.asm'
$consumerSourcePath = Project-Path 'artifacts/captured-shaders/e2aa1c8cb39e0a55-ps/e2aa1c8cb39e0a55-ps_decompiled.txt'
$frameLogPath = Project-Path 'artifacts/surface-lighting-study-20260830-v3/frame-log.txt'
$donorPath = Project-Path 'reference/external/shader-injector-v2.2.1/maximum-quality/shader-injector-2-2-1-maximum-dood/ShaderInjector/ModifiedShaders/Includes/ComputeShaderPass_ReflectionEnvironment.hlsl'
$runtimeRoots = @(
    (Project-Path 'runtime'),
    (Project-Path 'artifacts/intergrade-runtime'),
    (Project-Path 'artifacts/generated-runtime')
)

$runtimeIniFiles = @(
    $runtimeRoots |
        Where-Object { Test-Path -LiteralPath $_ -PathType Container } |
        ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -File -Filter '*.ini' } |
        Sort-Object FullName -Unique
)
$controlConflicts = @(
    foreach ($iniFile in $runtimeIniFiles) {
        $lineNumber = 0
        foreach ($line in Get-Content -LiteralPath $iniFile.FullName) {
            $lineNumber++
            if ($line -match '^\s*;' -or $line -notmatch '(?i)(?<![A-Z0-9_])(?:VK_)?F[123](?![A-Z0-9_])') { continue }
            [pscustomobject]@{ path=$iniFile.FullName; line=$lineNumber; text=$line.Trim() }
        }
    }
)
# A reservation conflict blocks integration, but it must not suppress the
# read-only architecture report that identifies the exact conflicting owner.
$controlIntegrationBlocked = ($controlConflicts.Count -ne 0)

$snapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
if ($snapshot.shaderCount -ne 184 -or $snapshot.stageCounts.vs -ne 70 -or $snapshot.stageCounts.ps -ne 95 -or $snapshot.stageCounts.cs -ne 18 -or $snapshot.stageCounts.gs -ne 1) {
    throw 'The authoritative 184-shader capture counts changed.'
}
if (@($snapshot.shaders | Where-Object identity -eq 'a77b589dce5822d6-ps').Count -ne 1) { throw 'The verified temporal-SSAO producer is absent from the capture.' }

$producerAsm = Get-Content -Raw -LiteralPath $producerAsmPath
foreach ($pattern in @('dcl_resource_texture3d .* t0','dcl_resource_texture2d .* t1','dcl_resource_texture2d .* t2','dcl_resource_texture2d .* t3','dcl_resource_texture2d .* t4','dcl_resource_texture2d .* t5','dcl_constantbuffer CB0\[21\]','dcl_constantbuffer CB1\[140\]','mov o0\.xyzw, r2\.wxyz')) {
    Require-Text $producerAsm $pattern $pattern
}

$consumerSource = Get-Content -Raw -LiteralPath $consumerSourcePath
foreach ($pattern in @(
    'r0\.x = t6\.SampleLevel\(s6_s, v0\.xy, 0\)\.x;',
    'r1\.y = r3\.w \* r0\.x;',
    'r0\.x = r2\.w \* r0\.x \+ r1\.y;',
    'r3\.xyz = r3\.xyz \* r0\.xxx;',
    'r11\.w = 1 \+ -r11\.w;',
    'r2\.xyz = r2\.xyz \* r11\.www;',
    'r2\.xyz = r2\.xyz \* r0\.www \+ r11\.xyz;'
)) { Require-Text $consumerSource $pattern $pattern }

$frame = Get-Content -Raw -LiteralPath $frameLogPath
$orderedEvents = @(
    '001015 PSSetShader\([^\r\n]+hash=a77b589dce5822d6',
    '001016 PSSetShader\([^\r\n]+hash=40c795101bdaad50',
    '001017 PSSetShader\([^\r\n]+hash=c9dfe2b46edf3ece',
    '001018 PSSetShader\([^\r\n]+hash=d41207d5d61df5b5',
    '001019 PSSetShader\([^\r\n]+hash=a8845c7ad73425a9'
)
$lastIndex = -1
foreach ($pattern in $orderedEvents) {
    $match = [regex]::Match($frame, $pattern)
    if (-not $match.Success -or $match.Index -le $lastIndex) { throw "Missing or out-of-order SSAO chain event: $pattern" }
    $lastIndex = $match.Index
}
foreach ($pattern in @(
    '001015 OMSetRenderTargets[\s\S]{0,250}resource=0x00000278082FB220 hash=36f63b9f',
    '001016 PSSetShaderResources[\s\S]{0,180}resource=0x00000278082FB220 hash=36f63b9f',
    '001019 OMSetRenderTargets[\s\S]{0,260}resource=0x0000027807DEEAE0 hash=54e6f2ca',
    '001028 CSSetShaderResources[\s\S]{0,180}resource=0x0000027807DEEAE0 hash=54e6f2ca',
    '001096 PSSetShader\([^\r\n]+hash=e2aa1c8cb39e0a55[\s\S]{0,900}resource=0x0000027807DEEAE0 hash=54e6f2ca'
)) { Require-Text $frame $pattern $pattern }

$inventory = Get-Content -Raw -LiteralPath $inventoryPath | ConvertFrom-Json
$reflection = @($inventory.donor.families | Where-Object family -eq 'ReflectionEnvironment')
if ($reflection.Count -ne 1 -or $reflection[0].stage -ne 'cs' -or $reflection[0].packageCount -ne 4) { throw 'Pinned Rebirth ReflectionEnvironment family inventory changed.' }
$familyCatalog = Get-Content -Raw -LiteralPath $familyCatalogPath | ConvertFrom-Json
$reflectionCatalog = @($familyCatalog.families | Where-Object logicalName -eq 'ReflectionEnvironment')
if ($reflectionCatalog.Count -ne 1) { throw 'Pinned Rebirth ReflectionEnvironment fingerprint family is missing or ambiguous.' }
$fingerprintVariants = @($reflectionCatalog[0].implementations[0].variants)
if ($fingerprintVariants.Count -ne 3) { throw 'Pinned Rebirth ReflectionEnvironment fingerprint variant count changed.' }
$donor = Get-Content -Raw -LiteralPath $donorPath
foreach ($pattern in @(
    'Texture2D<float4> AmbientOcclusionTexture : register\(t10\)',
    'RWTexture2D<float4> OutTextureColor : register\(u0\)',
    '#define SSAO_POWER 1\.0',
    '#define SSGI_AMBIENT_OCCLUSION',
    'ambientOcclusion \*= saturate\(pow\(ssgi\.a, SSAO_POWER\) \* SSAO_BRIGHTNESS\)',
    'ambientOcclusion \*= saturate\(pow\(gbufferData\.ScreenAO, SSAO_POWER\) \* SSAO_BRIGHTNESS\)',
    'diffuse \*= GTAOMultiBounce\(ambientOcclusion, gbufferData\.BaseColor\)'
)) { Require-Text $donor $pattern $pattern }

$targetHashes = @($reflection[0].packages | ForEach-Object { $_.targets.knownHashes[0] })
$fingerprints = @($fingerprintVariants | ForEach-Object {
    [ordered]@{
        crossVersionIdentityHash = $_.identity.crossVersionIdentityHash
        interfaceSignatureHash = $_.identity.interfaceSignatureHashes[0]
        resourceSignatureHash = $_.identity.resourceSignatureHashes[0]
        constantBufferSignatureHash = $_.identity.constantBufferSignatureHashes[0]
        executionSignatureHash = $_.identity.executionSignatureHashes[0]
        portableReflectionIdentityHash = $_.identity.portableReflectionIdentityHashes[0]
        semanticInstructionSetHash = $_.identity.semanticInstructionSetHashes[0]
        targets = @($_.targets | ForEach-Object shaderHash)
    }
})
$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    scope = 'FF7 Remake Intergrade current 184-shader regional capture versus both pinned Rebirth Shader Injector v2.2.1 presets'
    remakeCapture = [ordered]@{ shaderCount=184; stageCounts=[ordered]@{vs=70;ps=95;cs=18;gs=1}; regionalOnly=$true }
    rebirth = [ordered]@{
        family = 'ReflectionEnvironment'
        stage = 'cs_6_6'
        packages = 4
        targetHashes = $targetHashes
        fingerprints = $fingerprints
        bindings = [ordered]@{ gbuffer='t3-t7'; sceneDepth='t8'; ssr='t9'; ambientOcclusion='t10'; ambiguousLight='t11-t12'; environmentIrradiance='t13-t14'; output='u0' }
        architecture = 'Consumes either native ScreenAO or an in-pass GTVB SSGI visibility result, applies SSAO power/brightness and material AO, derives specular occlusion, then applies AO to ambient diffuse/specular before adding optional SSGI bounce.'
    }
    remake = [ordered]@{
        producer = [ordered]@{ event=1015; shader='a77b589dce5822d6-ps'; stage='ps_5_0'; inputs=[ordered]@{noise3D='t0';normal='t1';sceneDepth='t2';aoHistory='t3';velocity='t4';hierarchicalDepth='t5';constants='b0[21], b1[140]'}; output='o0.xyzw = current visibility, selected current/history visibility, temporal metric, signed depth'; outputResource='0x00000278082FB220' }
        spatialChain = @(
            [ordered]@{event=1016;shader='40c795101bdaad50-ps';role='depth-aware 2x2 neighborhood reduction/filter'},
            [ordered]@{event=1017;shader='c9dfe2b46edf3ece-ps';role='3x3 depth-aware neighborhood filter'},
            [ordered]@{event=1018;shader='d41207d5d61df5b5-ps';role='wider depth-aware neighborhood/filter and variance term'}
        )
        compositor = [ordered]@{event=1019;shader='a8845c7ad73425a9-ps';inputs='native packed temporal result t0 plus filtered chain t1';screenAOOutput='0x0000027807DEEAE0';outputBehavior='saturated scalar replicated to o0.xyzw; auxiliary o1 retained'}
        consumers = @(
            [ordered]@{family='five tiled local-light compute variants';events='1028-1032';screenAOSlots='t6 for c30/0e9/08b; t5 for 62b/5a9';classification='direct-light AO consumer, not the AO producer'},
            [ordered]@{family='reflection/indirect composite';event=1096;shader='e2aa1c8cb39e0a55-ps';screenAOSlot='t6';classification='ambient/reflection AO consumer and verified Rebirth fallback-adapter target';nativeDataflow='combines screen AO with material/extra occlusion, derives specular occlusion, applies GTAO multi-bounce, preserves SSR hit/radiance composition'}
        )
    }
    excludedFromAO = @(
        'b9e2305a994308f2 capsule-occlusion producer and its upsample chain',
        'five tiled local-light shaders except as downstream screen-AO consumers',
        'material/GBuffer writers including 8b1f6ebe443b5615',
        'contact-shadow ray/reconstruction code',
        'SampleGI donor family'
    )
    decision = [ordered]@{
        implementNow = 'Offline Balanced and Strong Rebirth native-ScreenAO fallback variants at the verified e2aa reflection/indirect consumer.'
        rationale = 'Rebirth Performance proves the native ScreenAO fallback ownership boundary; Remake e2aa already owns material AO, extra occlusion, specular occlusion, GTAO multi-bounce, reflection fallback, and SSR composition. Applying fallback shaping there preserves ambient/reflection scope and avoids changing five native direct-light AO consumers.'
        superseded = 'Producer-local Balanced/Strong power candidates are exploratory and non-authoritative because they broaden the donor ambient/reflection change to every screen-AO consumer.'
        defer = @('new GTVB SSGI rays','SSGI bounce light','checkerboard reconstruction','specular-occlusion rewrite beyond the verified native path')
        missingEvidence = @('live native/candidate parity','hair/skin/eye response','indoor/outdoor distance response','performance/GPU timing','later-region reflection-composite permutations','full scheduling and read/write bindings for a new SSGI pass')
    }
    futureControlReservation = [ordered]@{
        keys = @('F1','F2','F3')
        bindingsEmitted = $false
        stagingRule = 'Offline artifacts only; reviewed future mapping is F1 Original, F2 Balanced, F3 Strong.'
        ownership = [ordered]@{ F1='AO Original'; F2='AO Balanced'; F3='AO Strong' }
        conflictAudit = [ordered]@{ iniFilesScanned=$runtimeIniFiles.Count; activeF1ToF3BindingsFound=$controlConflicts.Count; conflicts=@($controlConflicts); integrationBlocked=$controlIntegrationBlocked }
        mapping = [ordered]@{
            F1 = 'Original/native AO'
            F2 = 'Balanced consumer-local fallback shaping'
            F3 = 'Strong donor-faithful consumer-local fallback shaping'
        }
    }
    sources = @(
        'artifacts/analysis/intergrade-shader-cache-before-next-region-20260901.json',
        'artifacts/analysis/rebirth-v2.2.1-remake-area-inventory.json',
        'artifacts/analysis/rebirth-shader-injector-v2.2.1-family-catalog.json',
        'artifacts/analysis/rebirth-v2.2.1-ao-architecture.json',
        'artifacts/captured-shaders/a77b589dce5822d6-ps/a77b589dce5822d6-ps_dumpbin.asm',
        'artifacts/captured-shaders/e2aa1c8cb39e0a55-ps/e2aa1c8cb39e0a55-ps_decompiled.txt',
        'artifacts/surface-lighting-study-20260830-v3/frame-log.txt',
        'reference/external/shader-injector-v2.2.1/maximum-quality/shader-injector-2-2-1-maximum-dood/ShaderInjector/ModifiedShaders/Includes/ComputeShaderPass_ReflectionEnvironment.hlsl'
    )
}

$outputFull = [IO.Path]::GetFullPath($OutputPath)
if (-not $outputFull.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Output must remain inside the workspace: $outputFull" }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFull) | Out-Null
[IO.File]::WriteAllText($outputFull, (($report | ConvertTo-Json -Depth 20) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Output "Intergrade AO architecture audit passed: $outputFull"
