[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CaptureDirectory,
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{16}$')]
    [string]$ShaderHash,
    [Parameter(Mandatory)]
    [ValidateSet('ps','cs')]
    [string]$Stage,
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) ("artifacts\analysis\resource-flow-{0}-{1}.json" -f $ShaderHash.ToLowerInvariant(), (Split-Path -Leaf $CaptureDirectory)))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$capture = [IO.Path]::GetFullPath($CaptureDirectory).TrimEnd('\')
$logPath = Join-Path $capture 'log.txt'
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith($artifacts + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must remain below workspace artifacts: $output"
}
if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) { throw "Frame log is missing: $logPath" }

$psSrv = @{}
$csSrv = @{}
$csUav = @{}
$renderTargets = @{}
$currentPs = $null
$currentCs = $null
$pending = $null
$operations = [Collections.Generic.List[object]]::new()
$sequence = 0

function Clear-SlotRange([hashtable]$Table, [int]$Start, [int]$Count) {
    for ($slot = $Start; $slot -lt $Start + $Count; $slot++) { [void]$Table.Remove($slot) }
}

function Set-Pending([string]$Kind, [hashtable]$Table, [int]$Start, [int]$Count) {
    Clear-SlotRange $Table $Start $Count
    return [ordered]@{ kind=$Kind; table=$Table; start=$Start; count=$Count }
}

function Snapshot-Table([hashtable]$Table) {
    return @($Table.GetEnumerator() | Sort-Object { [int]$_.Key } | ForEach-Object {
        [ordered]@{ slot=[int]$_.Key; address=$_.Value.address; resourceHash=$_.Value.resourceHash }
    })
}

function Add-Operation([int]$Event, [string]$Api) {
    $script:sequence++
    if ($Api -like 'Dispatch*') {
        $inputs = Snapshot-Table $script:csSrv
        $outputs = Snapshot-Table $script:csUav
        $shaderStage = 'cs'
        $shader = $script:currentCs
    } else {
        $inputs = Snapshot-Table $script:psSrv
        $outputs = Snapshot-Table $script:renderTargets
        $shaderStage = 'ps'
        $shader = $script:currentPs
    }
    $script:operations.Add([ordered]@{
        sequence=$script:sequence
        event=$Event
        api=$Api
        stage=$shaderStage
        shader=$shader
        inputs=$inputs
        outputs=$outputs
    })
}

foreach ($line in [IO.File]::ReadLines($logPath)) {
    if ($line -match '^\s+(?<slot>\d+): .*?resource=(?<address>0x[0-9a-fA-F]+) hash=(?<hash>[0-9a-fA-F]+)') {
        if ($null -ne $pending) {
            $slot = [int]$Matches.slot
            $pending.table[$slot] = [ordered]@{ address=$Matches.address.ToLowerInvariant(); resourceHash=$Matches.hash.ToLowerInvariant() }
        }
        continue
    }
    if ($line -notmatch '^(?<event>\d{6}) (?<call>.*)$') { continue }
    $event = [int]$Matches.event
    $call = $Matches.call
    $pending = $null

    if ($call -match '^PSSetShader\(.*hash=(?<hash>[0-9a-fA-F]{16})\s*$') { $currentPs = $Matches.hash.ToLowerInvariant(); continue }
    if ($call -match '^PSSetShader\(') { $currentPs = $null; continue }
    if ($call -match '^CSSetShader\(.*hash=(?<hash>[0-9a-fA-F]{16})\s*$') { $currentCs = $Matches.hash.ToLowerInvariant(); continue }
    if ($call -match '^CSSetShader\(') { $currentCs = $null; continue }

    if ($call -match '^PSSetShaderResources\(StartSlot:(?<start>\d+), NumViews:(?<count>\d+)') {
        $pending = Set-Pending 'ps-srv' $psSrv ([int]$Matches.start) ([int]$Matches.count); continue
    }
    if ($call -match '^CSSetShaderResources\(StartSlot:(?<start>\d+), NumViews:(?<count>\d+)') {
        $pending = Set-Pending 'cs-srv' $csSrv ([int]$Matches.start) ([int]$Matches.count); continue
    }
    if ($call -match '^CSSetUnorderedAccessViews\(StartSlot:(?<start>\d+), NumUAVs:(?<count>\d+)') {
        $pending = Set-Pending 'cs-uav' $csUav ([int]$Matches.start) ([int]$Matches.count); continue
    }
    if ($call -match '^OMSetRenderTargets\(NumViews:(?<count>\d+)') {
        $renderTargets.Clear()
        $pending = [ordered]@{ kind='rt'; table=$renderTargets; start=0; count=[int]$Matches.count }
        continue
    }

    if ($call -match '^(?<api>Draw(?:Indexed)?(?:Instanced)?|Dispatch(?:Indirect)?)\(') {
        Add-Operation $event $Matches.api
    }
}

$normalizedHash = $ShaderHash.ToLowerInvariant()
$targets = @($operations | Where-Object { $_.stage -eq $Stage -and $_.shader -eq $normalizedHash })
$targetReports = [Collections.Generic.List[object]]::new()
foreach ($target in $targets) {
    $outputReports = [Collections.Generic.List[object]]::new()
    foreach ($resource in @($target.outputs)) {
        $consumers = [Collections.Generic.List[object]]::new()
        $overwrite = $null
        foreach ($later in @($operations | Where-Object sequence -gt $target.sequence | Sort-Object sequence)) {
            $readSlots = @($later.inputs | Where-Object address -eq $resource.address | ForEach-Object slot)
            if ($readSlots.Count) {
                $consumers.Add([ordered]@{
                    sequence=$later.sequence; event=$later.event; api=$later.api; stage=$later.stage; shader=$later.shader; inputSlots=$readSlots
                })
            }
            $writeSlots = @($later.outputs | Where-Object address -eq $resource.address | ForEach-Object slot)
            if ($writeSlots.Count) {
                $overwrite = [ordered]@{
                    sequence=$later.sequence; event=$later.event; api=$later.api; stage=$later.stage; shader=$later.shader; outputSlots=$writeSlots
                }
                break
            }
        }
        $outputReports.Add([ordered]@{
            slot=$resource.slot
            address=$resource.address
            resourceHash=$resource.resourceHash
            consumersBeforeOverwrite=@($consumers)
            firstConsumer=if ($consumers.Count) { $consumers[0] } else { $null }
            overwrittenBy=$overwrite
        })
    }
    $targetReports.Add([ordered]@{
        sequence=$target.sequence
        event=$target.event
        api=$target.api
        inputs=$target.inputs
        outputs=@($outputReports)
    })
}

$report = [ordered]@{
    schemaVersion = 1
    detector = 'ff7-remake-shader-resource-flow-v1'
    result = 'pass'
    capture = [ordered]@{
        directory=$capture
        logSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $logPath).Hash
        operationCount=$operations.Count
    }
    target = [ordered]@{
        hash=$normalizedHash
        stage=$Stage
        observed=$targets.Count -gt 0
        executionCount=$targets.Count
    }
    executions=@($targetReports)
    interpretation=if ($targets.Count) {
        'Use firstConsumer only as resource-flow evidence. Classify the consumer from its own assembly and runtime behavior before modifying it.'
    } else {
        'The target did not execute in this frame. This is scene-specific absence, not evidence that the shader is unused.'
    }
}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output))
[IO.File]::WriteAllText($output, ($report | ConvertTo-Json -Depth 14) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Result='pass'
    Shader="$normalizedHash-$Stage"
    Observed=$report.target.observed
    Executions=$targets.Count
    Output=$output
}

