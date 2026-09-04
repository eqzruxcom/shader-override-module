[CmdletBinding()]
param(
    [string]$CaptureDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\FrameAnalysis-2026-09-04-001641',
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-r3d-ssgi-pre-temporal-resource-ownership-20260904.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspaceRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $workspaceRoot 'artifacts')).TrimEnd('\')
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
if (-not $resolvedOutput.StartsWith($artifactRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must remain below workspace artifacts: $resolvedOutput"
}

$analyzer = Join-Path $PSScriptRoot 'Analyze-IntergradeShaderResourceFlow.ps1'
$scratchRoot = Join-Path $artifactRoot ('.tmp-c473-resource-ownership-' + [guid]::NewGuid().ToString('N'))
$scratchReport = Join-Path $scratchRoot 'flow.json'
[void](New-Item -ItemType Directory -Path $scratchRoot -Force)

try {
    & $analyzer -CaptureDirectory $CaptureDirectory -ShaderHash c473ab75b7519f7e -Stage ps -OutputPath $scratchReport | Out-Null
    $flow = Get-Content -Raw -LiteralPath $scratchReport | ConvertFrom-Json
    if (-not [bool]$flow.target.observed -or [int]$flow.target.executionCount -ne 1) {
        throw 'The pinned capture must contain exactly one c473 execution.'
    }

    $execution = @($flow.executions)[0]
    $sceneInputs = @($execution.inputs | Where-Object slot -eq 2)
    $historyInputs = @($execution.inputs | Where-Object slot -eq 3)
    $motionInputs = @($execution.inputs | Where-Object slot -eq 4)
    $outputs = @($execution.outputs | Where-Object slot -eq 0)
    if ($sceneInputs.Count -ne 1 -or $historyInputs.Count -ne 1 -or $motionInputs.Count -ne 1 -or $outputs.Count -ne 1) {
        throw 'c473 must expose exactly one current-scene t2, history t3, motion t4, and color o0 resource.'
    }

    $scene = $sceneInputs[0]
    $history = $historyInputs[0]
    $motion = $motionInputs[0]
    $output = $outputs[0]
    if ($scene.address -eq $output.address) {
        throw 'c473 current-scene t2 aliases o0; private pre-temporal composition would create a read/write hazard.'
    }
    if ($scene.resourceHash -ne $output.resourceHash) {
        throw 'c473 current-scene t2 and o0 no longer share descriptor identity; copy_desc compatibility must be re-audited.'
    }
    if ($history.address -in @($scene.address, $output.address) -or $motion.address -in @($scene.address, $output.address, $history.address)) {
        throw 'c473 scene, history, motion, and output resources are not independently owned.'
    }

    $first = $output.firstConsumer
    if ($null -eq $first -or $first.shader -ne 'af6cd28a0108a18a' -or $first.stage -ne 'ps' -or @($first.inputSlots) -notcontains 0) {
        throw 'c473 o0 must flow first into af6cd28a0108a18a-ps:t0 in the pinned capture.'
    }
    if ([int]$first.sequence -le [int]$execution.sequence) {
        throw 'c473 first-consumer ordering is invalid.'
    }

    $report = [ordered]@{
        result = 'pass'
        generatedUtc = [DateTime]::UtcNow.ToString('o')
        capture = $flow.capture
        temporalResolve = [ordered]@{
            shader = 'c473ab75b7519f7e-ps'
            sequence = [int]$execution.sequence
            event = [int]$execution.event
            currentSceneT2 = $scene
            nativeHistoryT3 = $history
            nativeMotionT4 = $motion
            nativeOutputO0 = [ordered]@{
                slot = [int]$output.slot
                address = $output.address
                resourceHash = $output.resourceHash
            }
            sceneOutputAliased = $false
            descriptorCompatible = $true
            firstConsumer = $first
        }
        conclusion = @(
            'The native current-scene input and temporal output are distinct resources, so c473 is not an intrinsic same-resource feedback pass.',
            'The matching descriptor hash supports a private copy_desc-compatible scene-plus-GI target for ps-t2.',
            'Native history t3 and motion t4 are distinct and remain owned by the original temporal resolve.',
            'The old af6 late-scene injection must be quarantined when the c473 path is staged because it is the first consumer of c473 o0.'
        )
        liveFilesModified = $false
    }

    $parent = Split-Path -Parent $resolvedOutput
    if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedOutput -Encoding UTF8
    [pscustomobject]@{
        Result = 'pass'
        SceneOutputAliased = $false
        DescriptorCompatible = $true
        FirstConsumer = 'af6cd28a0108a18a-ps:t0'
        Output = $resolvedOutput
    }
}
finally {
    if (Test-Path -LiteralPath $scratchRoot) { Remove-Item -LiteralPath $scratchRoot -Recurse -Force }
}
