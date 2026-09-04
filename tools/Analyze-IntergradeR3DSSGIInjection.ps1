[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\agent2-r3d-ssgi-injection.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$framePath = Join-Path $root 'artifacts\surface-lighting-study-20260830-v3\frame-log.txt'
$e2aaPath = Join-Path $root 'artifacts\captured-shaders\e2aa1c8cb39e0a55-ps\e2aa1c8cb39e0a55-ps_decompiled.txt'
$taaPath = Join-Path $root 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\assembly\c473ab75b7519f7e-ps.asm'
$fullscreenVsPath = Join-Path $root 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\assembly\1bf99472af1427ba-vs.asm'

foreach ($path in @($framePath, $e2aaPath, $taaPath, $fullscreenVsPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required capture evidence is missing: $path" }
}

$frame = Get-Content -Raw -LiteralPath $framePath
$e2aa = Get-Content -Raw -LiteralPath $e2aaPath
$taa = Get-Content -Raw -LiteralPath $taaPath
$fullscreenVs = Get-Content -Raw -LiteralPath $fullscreenVsPath

function Assert-Pattern([string]$Text, [string]$Pattern, [string]$Label) {
    if ($Text -notmatch $Pattern) { throw "Capture assertion failed: $Label" }
}

$lightingResource = '0x00000278082EE960'
$lightingHash = '3a9ee32b'
foreach ($event in 1028..1032) {
    Assert-Pattern $frame ("(?s)00{0}.*?CSSetUnorderedAccessViews.*?resource={1} hash={2}" -f $event, [regex]::Escape($lightingResource), $lightingHash) "event $event writes the lighting accumulation UAV"
}
Assert-Pattern $frame '(?s)001096 OMSetRenderTargets.*?resource=0x00000278082EE960 hash=3a9ee32b' 'e2aa writes the accumulated lighting target'
Assert-Pattern $frame '(?s)001096 PSSetShaderResources\(StartSlot:0.*?resource=0x00000278082EB520 hash=b7f4aa00' 'e2aa t0 is the verified normal resource'
Assert-Pattern $frame '(?s)001095 PSSetShaderResources\(StartSlot:1.*?resource=0x00000278082EB520 hash=b7f4aa00' 'SSR t1 and e2aa t0 share the normal resource'
Assert-Pattern $frame '(?s)001096 PSSetShaderResources\(StartSlot:5.*?resource=0x0000027807DEE560 hash=00236552' 'e2aa t5 is scene depth'
Assert-Pattern $frame '(?s)001096 OMSetRenderTargets.*?D:.*?resource=0x0000027807DEE560 hash=00236552' 'e2aa t5 matches the active DSV resource'
Assert-Pattern $frame '(?s)000011 ClearDepthStencilView\(.*?Depth:0\.000000.*?resource=0x0000027807DEE560 hash=00236552' 'e2aa scene depth resource is explicitly cleared to 0.0'

foreach ($pattern in @(
    'r4\.w = r0\.w \* cb0\[57\]\.x \+ cb0\[57\]\.y',
    'r0\.w = r0\.w \* cb0\[57\]\.z \+ -cb0\[57\]\.w',
    'r12\.xy = v0\.zw \* r0\.ww',
    'cb0\[40\]\.xyzw', 'cb0\[41\]\.xyzw', 'cb0\[42\]\.xyzw', 'cb0\[43\]\.xyzw',
    'cb0\[59\]\.xyz \+ -r12\.xyz'
)) { Assert-Pattern $e2aa $pattern "e2aa native reconstruction statement $pattern" }

Assert-Pattern $fullscreenVs 'mov o0\.zw, r0\.xxxy' 'fullscreen VS exports clip XY in TEXCOORD0.zw'
Assert-Pattern $taa 'dcl_resource_texture2d \(float,float,float,float\) t2' 'temporal resolve has current scene input'
Assert-Pattern $taa 'dcl_resource_texture2d \(float,float,float,float\) t3' 'temporal resolve has history input'
Assert-Pattern $taa 'dcl_resource_texture2d \(float,float,float,float\) t4' 'temporal resolve has motion input'
Assert-Pattern $taa 'sample_l_indexable\(texture2d\).*t3' 'temporal resolve samples history'

$event1096 = $frame.IndexOf('001096 PSSetShader(pPixelShader')
$event1138 = $frame.IndexOf('001138 PSSetShader(pPixelShader')
$event1141 = $frame.IndexOf('001141 PSSetShader(pPixelShader')
if ($event1096 -lt 0 -or $event1138 -le $event1096 -or $event1141 -le $event1138) {
    throw 'Captured lighting -> temporal resolve -> final scene-color order is invalid.'
}
Assert-Pattern $frame '001138 PSSetShader\(.*hash=c473ab75b7519f7e' 'event 1138 temporal resolve identity'
Assert-Pattern $frame '001141 PSSetShader\(.*hash=af6cd28a0108a18a' 'event 1141 verified UI-safe final scene-color identity'

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    classification = 'architecture-defensible-format-and-live-capture-pending'
    trigger = [ordered]@{ event = 1096; shader = 'e2aa1c8cb39e0a55'; stage = 'reflection-environment pixel composite' }
    sceneRadiance = [ordered]@{
        resource = $lightingResource
        resourceHash = $lightingHash
        writtenByLocalLightingEvents = @(1028, 1029, 1030, 1031, 1032)
        activeAsE2aaRt0 = $true
        conclusion = 'copy rt0 before event 1096 to capture native accumulated direct/local lighting radiance'
    }
    geometry = [ordered]@{
        normal = [ordered]@{ e2aaSlot = 't0'; resourceHash = 'b7f4aa00'; crossCheck = 'same resource as SSR event 1095 t1' }
        depth = [ordered]@{ e2aaSlot = 't5'; resourceHash = '00236552'; matchesDsv = $true; clearValue = 0.0; convention = 'captured reversed-Z' }
        nativeViewConstants = [ordered]@{ constantBuffer = 'b0'; depthCoefficients = 'cb0[57]'; reconstructionRows = 'cb0[40..43]'; cameraWorldPosition = 'cb0[59].xyz' }
        fullscreenRay = 'TEXCOORD0.zw from VS 1bf99472af1427ba'
    }
    schedule = [ordered]@{
        lightingCompositeEvent = 1096
        temporalResolveEvent = 1138
        temporalResolveShader = 'c473ab75b7519f7e'
        temporalEvidence = @('current scene t2', 'history t3', 'motion t4', 'history sampling and blend')
        finalSceneColorEvent = 1141
        finalSceneColorShader = 'af6cd28a0108a18a'
        conclusion = 'event 1096 is before Remake temporal resolve and final scene-color post'
    }
    proposedPipeline = @('copy accumulated rt0', 'half-resolution R3D horizon SSGI', 'A-trous 16', 'A-trous 8', 'A-trous 4', 'A-trous 2', 'additive HDR composite', 'native e2aa composition', 'native temporal resolve', 'native final post')
    gates = [ordered]@{
        compileRequired = $true
        resourceFormatCaptureRequired = $true
        subViewportRayCaptureRequired = $true
        motionAndDisocclusionCaptureRequired = $true
        gpuTimingRequired = $true
        runtimeEligible = $false
        installed = $false
    }
    evidence = @($framePath, $e2aaPath, $taaPath, $fullscreenVsPath | ForEach-Object { [IO.Path]::GetRelativePath($root, $_) })
}

$outputFull = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull)) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($outputFull, ($report | ConvertTo-Json -Depth 10) + [Environment]::NewLine, $utf8)

[pscustomobject]@{
    result = 'pass'
    classification = $report.classification
    output = $outputFull
    runtimeEligible = $false
}
