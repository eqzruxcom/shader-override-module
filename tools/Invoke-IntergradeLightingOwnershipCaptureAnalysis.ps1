[CmdletBinding()]
param(
    [string]$CaptureRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64',
    [DateTime]$AfterUtc = [DateTime]::MinValue,
    [Alias('Target')]
    [string[]]$ShaderTarget = @('aadc1c2374853914:ps', 'adb544f9a11d6c7e:cs'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-lighting-ownership-captures-latest.json'),
    [switch]$RequireObserved
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspaceRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $workspaceRoot 'artifacts')).TrimEnd('\')
$resolvedCaptureRoot = [IO.Path]::GetFullPath($CaptureRoot).TrimEnd('\')
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
if (-not $resolvedOutput.StartsWith($artifactRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must remain below workspace artifacts: $resolvedOutput"
}
if (-not (Test-Path -LiteralPath $resolvedCaptureRoot -PathType Container)) {
    throw "Capture root does not exist: $resolvedCaptureRoot"
}

$targets = [Collections.Generic.List[object]]::new()
foreach ($claim in $ShaderTarget) {
    if ($claim -notmatch '^(?<hash>[0-9a-fA-F]{16}):(?<stage>ps|cs)$') {
        throw "Target must use 16hex:ps or 16hex:cs syntax: $claim"
    }
    $targets.Add([pscustomobject][ordered]@{
        hash = $Matches.hash.ToLowerInvariant()
        stage = $Matches.stage.ToLowerInvariant()
        identity = $Matches.hash.ToLowerInvariant() + '-' + $Matches.stage.ToLowerInvariant()
    })
}
if (-not $targets.Count) { throw 'At least one target is required.' }
$targetIdentities = @($targets | ForEach-Object { $_.identity })
if (@($targetIdentities | Group-Object | Where-Object Count -gt 1).Count) { throw 'Duplicate targets are not allowed.' }

$captureDirs = @(Get-ChildItem -LiteralPath $resolvedCaptureRoot -Directory -Filter 'FrameAnalysis-*' |
    Where-Object { $_.LastWriteTimeUtc -ge $AfterUtc.ToUniversalTime() -and (Test-Path -LiteralPath (Join-Path $_.FullName 'log.txt') -PathType Leaf) } |
    Sort-Object LastWriteTimeUtc, Name)
if (-not $captureDirs.Count) {
    throw "No FrameAnalysis capture with log.txt was found at or after $($AfterUtc.ToUniversalTime().ToString('o'))."
}

$analyzer = Join-Path $PSScriptRoot 'Analyze-IntergradeShaderResourceFlow.ps1'
$scratchRoot = Join-Path $artifactRoot ('.tmp-lighting-ownership-ingest-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $scratchRoot -Force)
$captures = [Collections.Generic.List[object]]::new()
$observedIdentities = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

try {
    foreach ($capture in $captureDirs) {
        $targetResults = [Collections.Generic.List[object]]::new()
        foreach ($targetSpec in $targets) {
            $scratchPath = Join-Path $scratchRoot ($capture.Name + '-' + $targetSpec.identity + '.json')
            & $analyzer -CaptureDirectory $capture.FullName -ShaderHash $targetSpec.hash -Stage $targetSpec.stage -OutputPath $scratchPath | Out-Null
            $flow = Get-Content -Raw -LiteralPath $scratchPath | ConvertFrom-Json
            $executions = [Collections.Generic.List[object]]::new()
            foreach ($execution in @($flow.executions)) {
                $outputs = [Collections.Generic.List[object]]::new()
                foreach ($output in @($execution.outputs)) {
                    $first = $output.firstConsumer
                    $outputs.Add([ordered]@{
                        slot = [int]$output.slot
                        address = $output.address
                        resourceHash = $output.resourceHash
                        firstConsumer = if ($null -eq $first) { $null } else { [ordered]@{
                            identity = $first.shader + '-' + $first.stage
                            inputSlots = @($first.inputSlots)
                            sequence = [int]$first.sequence
                            event = [int]$first.event
                        }}
                        overwrittenBy = $output.overwrittenBy
                    })
                }
                $executions.Add([ordered]@{
                    sequence = [int]$execution.sequence
                    event = [int]$execution.event
                    api = $execution.api
                    inputs = @($execution.inputs)
                    outputs = @($outputs)
                })
            }
            if ([bool]$flow.target.observed) { [void]$observedIdentities.Add($targetSpec.identity) }
            $targetResults.Add([ordered]@{
                identity = $targetSpec.identity
                observed = [bool]$flow.target.observed
                executionCount = [int]$flow.target.executionCount
                executions = @($executions)
            })
        }
        $captures.Add([ordered]@{
            name = $capture.Name
            directory = $capture.FullName
            lastWriteUtc = $capture.LastWriteTimeUtc.ToString('o')
            logSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $capture.FullName 'log.txt')).Hash
            targets = @($targetResults)
        })
    }

    $missing = @($targetIdentities | Where-Object { -not $observedIdentities.Contains($_) })
    $report = [ordered]@{
        result = if ($RequireObserved -and $missing.Count) { 'incomplete' } else { 'pass' }
        generatedUtc = [DateTime]::UtcNow.ToString('o')
        captureRoot = $resolvedCaptureRoot
        afterUtc = $AfterUtc.ToUniversalTime().ToString('o')
        targetIdentities = $targetIdentities
        captureCount = $captures.Count
        observedIdentities = @($observedIdentities | Sort-Object)
        missingIdentities = $missing
        captures = @($captures)
        interpretation = if ($missing.Count) {
            'Missing means not observed in the selected captures. It does not mean the shader is unused; capture a scene that exercises the path.'
        } else {
            'Every requested target executed in at least one selected capture. Review each output firstConsumer before modifying a downstream evaluator.'
        }
        liveFilesModified = $false
    }
    $parent = Split-Path -Parent $resolvedOutput
    if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    $report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $resolvedOutput -Encoding UTF8

    if ($RequireObserved -and $missing.Count) {
        throw "Required targets were not observed: $($missing -join ', '). Report: $resolvedOutput"
    }
    [pscustomobject]@{
        Result = 'pass'
        Captures = $captures.Count
        Observed = @($observedIdentities | Sort-Object) -join ', '
        Missing = $missing -join ', '
        Output = $resolvedOutput
    }
}
finally {
    if (Test-Path -LiteralPath $scratchRoot) { Remove-Item -LiteralPath $scratchRoot -Recurse -Force }
}
