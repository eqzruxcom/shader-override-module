[CmdletBinding()]
param(
    [string]$AuditPath,
    [string[]]$CaptureDirectories,
    [ValidateSet('candidate-only', 'evidence-backed-role', 'all')]
    [string]$CandidateStatus = 'candidate-only',
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $AuditPath) {
    $AuditPath = Join-Path $projectRoot 'artifacts\shader-coverage-audit-20260831-v1\coverage-audit.json'
}
if (-not $CaptureDirectories) {
    $gameDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64'
    $CaptureDirectories = @(
        (Join-Path $gameDirectory 'FrameAnalysis-2026-08-29-123153'),
        (Join-Path $gameDirectory 'FrameAnalysis-2026-08-30-211238')
    )
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $projectRoot 'artifacts\shader-frame-correlation-20260831-v1'
}

if (-not (Test-Path -LiteralPath $AuditPath -PathType Leaf)) {
    throw "Audit does not exist: $AuditPath"
}
foreach ($captureDirectory in $CaptureDirectories) {
    foreach ($name in @('log.txt', 'ShaderUsage.txt')) {
        $path = Join-Path $captureDirectory $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Capture input does not exist: $path"
        }
    }
}

$audit = Get-Content -Raw -LiteralPath $AuditPath | ConvertFrom-Json
$candidates = @(
    $audit.universalMatcher.candidates |
        Where-Object {
            $CandidateStatus -eq 'all' -or $_.status -eq $CandidateStatus
        }
)

$candidateByIdentity = @{}
foreach ($candidate in $candidates) {
    $identity = "$($candidate.hash.ToLowerInvariant())-$($candidate.stage.ToLowerInvariant())"
    $candidateByIdentity[$identity] = $candidate
}

$occurrences = [Collections.Generic.List[object]]::new()
$usagePeersByIdentity = @{}

foreach ($captureDirectory in $CaptureDirectories) {
    $captureName = Split-Path -Leaf $captureDirectory
    $usageText = Get-Content -Raw -LiteralPath (Join-Path $captureDirectory 'ShaderUsage.txt')
    foreach ($candidate in $candidates) {
        $tag = switch ($candidate.stage.ToLowerInvariant()) {
            'vs' { 'VertexShader' }
            'ps' { 'PixelShader' }
            'cs' { 'ComputeShader' }
            'gs' { 'GeometryShader' }
            'hs' { 'HullShader' }
            'ds' { 'DomainShader' }
            default { $null }
        }
        if (-not $tag) {
            continue
        }

        $identity = "$($candidate.hash.ToLowerInvariant())-$($candidate.stage.ToLowerInvariant())"
        $blockPattern = '(?s)<' + $tag + ' hash="' +
            [regex]::Escape($candidate.hash) + '">.*?</' + $tag + '>'
        $block = [regex]::Match($usageText, $blockPattern)
        if (-not $block.Success) {
            continue
        }

        if (-not $usagePeersByIdentity.ContainsKey($identity)) {
            $usagePeersByIdentity[$identity] = [Collections.Generic.HashSet[string]]::new(
                [StringComparer]::OrdinalIgnoreCase
            )
        }
        $peerMatch = [regex]::Match($block.Value, '<PeerShaders>(.*?)</PeerShaders>')
        if ($peerMatch.Success) {
            foreach ($peer in ($peerMatch.Groups[1].Value -split '\s+')) {
                if ($peer) {
                    $null = $usagePeersByIdentity[$identity].Add($peer.ToLowerInvariant())
                }
            }
        }
    }

    $renderTargetCount = $null
    $vertexShader = $null
    $lastCandidateOccurrence = $null

    foreach ($line in [IO.File]::ReadLines((Join-Path $captureDirectory 'log.txt'))) {
        if ($line -notmatch '^(?<event>\d{6}) ') {
            continue
        }
        $event = $Matches.event

        if ($line -match 'OMSetRenderTargets\(NumViews:(?<count>\d+)') {
            $renderTargetCount = [int]$Matches.count
        }
        if ($line -match 'VSSetShader\(.*hash=(?<hash>[0-9a-fA-F]{16})\s*$') {
            $vertexShader = $Matches.hash.ToLowerInvariant()
        }

        if ($line -match '(?<prefix>VS|PS|CS|GS|HS|DS)SetShader\(.*hash=(?<hash>[0-9a-fA-F]{16})\s*$') {
            $stage = $Matches.prefix.ToLowerInvariant()
            $hash = $Matches.hash.ToLowerInvariant()
            $identity = "$hash-$stage"
            if ($candidateByIdentity.ContainsKey($identity)) {
                $candidate = $candidateByIdentity[$identity]
                $lastCandidateOccurrence = [pscustomobject][ordered]@{
                    capture = $captureName
                    event = $event
                    hash = $hash
                    stage = $stage
                    status = $candidate.status
                    families = @($candidate.families)
                    renderTargetCount = if ($stage -eq 'ps') { $renderTargetCount } else { $null }
                    vertexShader = if ($stage -eq 'ps') { $vertexShader } else { $null }
                    call = $null
                }
                $occurrences.Add($lastCandidateOccurrence)
            }
        }

        if (
            $lastCandidateOccurrence -and
            $lastCandidateOccurrence.event -eq $event -and
            $line -match '(?<call>Dispatch\(.*|Draw(?:Indexed)?(?:Instanced)?\(.*)'
        ) {
            $lastCandidateOccurrence.call = $Matches.call
        }
    }
}

$summary = @(
    foreach ($candidate in $candidates) {
        $hash = $candidate.hash.ToLowerInvariant()
        $stage = $candidate.stage.ToLowerInvariant()
        $identity = "$hash-$stage"
        $candidateOccurrences = @(
            $occurrences |
                Where-Object { $_.hash -eq $hash -and $_.stage -eq $stage }
        )
        $eventNumbers = @(
            $candidateOccurrences |
                ForEach-Object { [int]$_.event } |
                Sort-Object -Unique
        )
        [pscustomobject][ordered]@{
            hash = $hash
            stage = $stage
            status = $candidate.status
            executed = $candidateOccurrences.Count -gt 0
            occurrenceCount = $candidateOccurrences.Count
            captureCount = @(
                $candidateOccurrences |
                    ForEach-Object { $_.capture } |
                    Sort-Object -Unique
            ).Count
            firstEvent = if ($eventNumbers.Count) { $eventNumbers[0] } else { $null }
            lastEvent = if ($eventNumbers.Count) { $eventNumbers[-1] } else { $null }
            renderTargetCounts = @(
                $candidateOccurrences |
                    ForEach-Object { $_.renderTargetCount } |
                    Where-Object { $null -ne $_ } |
                    Sort-Object -Unique
            )
            vertexShaders = @(
                $candidateOccurrences |
                    ForEach-Object { $_.vertexShader } |
                    Where-Object { $_ } |
                    Sort-Object -Unique
            )
            shaderUsagePeers = if ($usagePeersByIdentity.ContainsKey($identity)) {
                @($usagePeersByIdentity[$identity] | Sort-Object)
            } else {
                @()
            }
            callKinds = @(
                $candidateOccurrences |
                    ForEach-Object { $_.call } |
                    Where-Object { $_ } |
                    ForEach-Object {
                        if ($_ -match '^(?<kind>[^\(]+)') {
                            $Matches.kind
                        }
                    } |
                    Sort-Object -Unique
            )
            families = @($candidate.families)
            rules = @($candidate.rules)
            observedRole = $candidate.observedRole
        }
    }
)

$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    auditPath = (Resolve-Path -LiteralPath $AuditPath).Path
    candidateStatus = $CandidateStatus
    captureDirectories = @($CaptureDirectories | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })
    counts = [ordered]@{
        candidates = $summary.Count
        executed = @($summary | Where-Object executed).Count
        notExecuted = @($summary | Where-Object { -not $_.executed }).Count
        occurrences = $occurrences.Count
    }
    candidates = $summary
    occurrences = @($occurrences)
    caveats = @(
        'Render-target count and vertex shader are persistent D3D11 state reconstructed from the frame log.',
        'Execution proves a shader ran in the captured frame, not its semantic role.',
        'A cached shader that did not execute remains unresolved until an appropriate scene invokes it.',
        'ShaderUsage peer shaders are correlations, not proof of a fixed one-to-one pass relationship.'
    )
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$result |
    ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath (Join-Path $OutputDirectory 'frame-correlation.json') -Encoding UTF8

$summary |
    Select-Object hash, stage, status, executed, occurrenceCount, captureCount,
        firstEvent, lastEvent,
        @{ n = 'renderTargetCounts'; e = { $_.renderTargetCounts -join ',' } },
        @{ n = 'vertexShaders'; e = { $_.vertexShaders -join ',' } },
        @{ n = 'shaderUsagePeers'; e = { $_.shaderUsagePeers -join ',' } },
        @{ n = 'callKinds'; e = { $_.callKinds -join ',' } },
        @{ n = 'families'; e = { $_.families -join ',' } },
        observedRole |
    Export-Csv -LiteralPath (Join-Path $OutputDirectory 'candidate-summary.csv') -NoTypeInformation -Encoding UTF8

$occurrences |
    Select-Object capture, event, hash, stage, status,
        @{ n = 'families'; e = { $_.families -join ',' } },
        renderTargetCount, vertexShader, call |
    Export-Csv -LiteralPath (Join-Path $OutputDirectory 'occurrences.csv') -NoTypeInformation -Encoding UTF8

Write-Output "Frame correlation: $(Join-Path $OutputDirectory 'frame-correlation.json')"
Write-Output "Candidates: $($summary.Count)"
Write-Output "Executed: $(@($summary | Where-Object executed).Count)"
Write-Output "Not executed: $(@($summary | Where-Object { -not $_.executed }).Count)"
Write-Output "Occurrences: $($occurrences.Count)"
