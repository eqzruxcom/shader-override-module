[CmdletBinding()]
param(
    [string[]]$CaptureDirectories,
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-tiled-light-dispatch-sequence-20260904.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must remain under artifacts: $output"
}

if (-not $CaptureDirectories) {
    $gameDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64'
    $CaptureDirectories = @(
        (Join-Path $gameDirectory 'FrameAnalysis-2026-08-29-123153'),
        (Join-Path $gameDirectory 'FrameAnalysis-2026-08-30-211238'),
        (Join-Path $gameDirectory 'FrameAnalysis-2026-09-03-180300'),
        (Join-Path $gameDirectory 'FrameAnalysis-2026-09-03-180936'),
        (Join-Path $gameDirectory 'FrameAnalysis-2026-09-04-001641')
    )
}

$expected = @(
    [ordered]@{ hash='c30cdc8365df9840'; offset=0;  materialBucket='general/mixed fallback' },
    [ordered]@{ hash='62b33a2d1e505241'; offset=12; materialBucket='material IDs 1/5 only' },
    [ordered]@{ hash='5a9fbefe0ab6f815'; offset=24; materialBucket='material ID 3, optionally mixed with 1/5' },
    [ordered]@{ hash='0e97888f9a8767da'; offset=36; materialBucket='material ID 7, optionally mixed with 1/5' },
    [ordered]@{ hash='08bb8764f1840179'; offset=48; materialBucket='material ID 8 or remaining specialized mask' }
)
$known = @{}
foreach ($entry in $expected) { $known[$entry.hash] = $entry }

$captures = foreach ($directory in $CaptureDirectories) {
    $resolvedDirectory = [IO.Path]::GetFullPath($directory).TrimEnd('\')
    $log = Join-Path $resolvedDirectory 'log.txt'
    if (-not (Test-Path -LiteralPath $log -PathType Leaf)) { throw "Frame log is missing: $log" }

    $events = @{}
    $classifierEvents = [Collections.Generic.List[int]]::new()
    foreach ($line in [IO.File]::ReadLines($log)) {
        if ($line -notmatch '^(?<event>\d{6}) ') { continue }
        $event = [int]$Matches.event

        if ($line -match 'CSSetShader\([^\r\n]*hash=f97a821dddaa328a\s*$') {
            $classifierEvents.Add($event)
        }
        if ($line -match 'CSSetShader\([^\r\n]*hash=(?<hash>[0-9a-fA-F]{16})\s*$') {
            $hash = $Matches.hash.ToLowerInvariant()
            if ($known.ContainsKey($hash)) {
                if ($events.ContainsKey($event)) { throw "Duplicate accepted light shader at event $event in $log" }
                $events[$event] = [ordered]@{ event=$event; hash=$hash; call=$null; buffer=$null; offset=$null; argumentResourceHash=$null }
            }
        }
        if ($events.ContainsKey($event) -and $line -match 'DispatchIndirect\(pBufferForArgs:(?<buffer>0x[0-9A-Fa-f]+),\s*AlignedByteOffsetForArgs:(?<offset>\d+)\)\s+hash=(?<resourceHash>[0-9a-fA-F]{8})\s*$') {
            $events[$event].call = 'DispatchIndirect'
            $events[$event].buffer = $Matches.buffer.ToLowerInvariant()
            $events[$event].offset = [int]$Matches.offset
            $events[$event].argumentResourceHash = $Matches.resourceHash.ToLowerInvariant()
        }
    }

    $sequence = @($events.Values | Sort-Object { [int]$_['event'] })
    if ($sequence.Count -ne $expected.Count) {
        throw "Expected five accepted tiled-light dispatches in $log; found $($sequence.Count)"
    }
    for ($i=0; $i -lt $expected.Count; $i++) {
        if ($sequence[$i].hash -ne $expected[$i].hash) {
            throw "Tiled-light hash order changed at index $i in ${log}: $($sequence[$i].hash)"
        }
        if ($sequence[$i].call -ne 'DispatchIndirect') { throw "Missing indirect dispatch for $($sequence[$i].hash) in $log" }
        if ($sequence[$i].offset -ne $expected[$i].offset) {
            throw "Indirect offset changed for $($sequence[$i].hash) in ${log}: $($sequence[$i].offset)"
        }
        if ($i -gt 0 -and $sequence[$i].event -ne ($sequence[$i-1].event + 1)) {
            throw "Accepted tiled-light dispatches are no longer consecutive in $log"
        }
    }
    $buffers = @($sequence | ForEach-Object buffer | Sort-Object -Unique)
    $argumentHashes = @($sequence | ForEach-Object argumentResourceHash | Sort-Object -Unique)
    if ($buffers.Count -ne 1) { throw "Accepted tiled-light dispatches do not share one indirect argument buffer in $log" }
    if ($argumentHashes.Count -ne 1 -or $argumentHashes[0] -ne '6380a698') {
        throw "Unexpected indirect argument resource identity in $log"
    }
    $classifierBeforeSequence = @($classifierEvents | Where-Object { $_ -lt $sequence[0].event } | Sort-Object)[-1]
    if ($classifierBeforeSequence -ne ($sequence[0].event - 1)) {
        throw "Material/tile classifier is not immediately before the accepted dispatch sequence in $log"
    }

    [ordered]@{
        name = Split-Path -Leaf $resolvedDirectory
        directory = $resolvedDirectory
        logSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $log).Hash
        classifier = [ordered]@{ hash='f97a821dddaa328a'; event=$classifierBeforeSequence }
        sharedArgumentBuffer = $buffers[0]
        argumentResourceHash = $argumentHashes[0]
        sequence = $sequence
    }
}

$canonicalSequence = @($expected | ForEach-Object {
    [ordered]@{ hash=$_.hash; offset=$_.offset; materialBucket=$_.materialBucket }
})
$report = [ordered]@{
    schemaVersion = 1
    detector = 'ff7-remake-tiled-light-dispatch-sequence-v1'
    scope = 'Read-only cross-capture proof of the stable classifier and five-bucket tiled surface-light dispatch topology.'
    captureCount = @($captures).Count
    canonicalSequence = $canonicalSequence
    captures = @($captures)
    conclusions = @(
        'The five hashes are stable material/tile specializations selected by one classifier, not object-specific face, hair, clothing, or light identities.',
        'Every retained capture uses the same five-hash order, consecutive events, one indirect argument buffer, and offsets 0/12/24/36/48.',
        'Dispatch presence does not prove a nonzero group count because the indirect argument contents are not captured.',
        'A material or lighting change must cover every specialization that can receive the relevant material-class mask; camera movement can change tile masks and therefore the active specialization.',
        'Directional or IES ownership remains unproven: stable bucket order proves specialization routing, not per-light type labels.'
    )
    safetyPolicy = [ordered]@{
        objectLabels = 'Never promote live face/hair/clothing observations into object-exclusive shader labels.'
        automaticTransform = 'Require the full five-bucket contract or a formally proven subset selected by material-class logic.'
        directionalAndIes = 'Require runtime light-type data or a dedicated profile lookup before type-specific transformation.'
    }
}

[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,(($report | ConvertTo-Json -Depth 12)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Captures=$captures.Count; Dispatches=$captures.Count*$expected.Count; Output=$output }

