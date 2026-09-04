[CmdletBinding()]
param(
    [string]$CaptureRoot,
    [string]$GameRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes',
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\intergrade-capture-analysis.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$binaryDirectory = Join-Path $GameRoot 'End\Binaries\Win64'
if (-not $CaptureRoot) {
    $CaptureRoot = Get-ChildItem -LiteralPath $binaryDirectory -Directory -Filter 'FrameAnalysis-*' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $CaptureRoot -or -not (Test-Path -LiteralPath $CaptureRoot -PathType Container)) {
    throw "No 3Dmigoto FrameAnalysis capture found under $binaryDirectory"
}

$capturePath = (Resolve-Path -LiteralPath $CaptureRoot).Path.TrimEnd('\')
$logPath = Join-Path $capturePath 'log.txt'
$draws = @{}

function Get-DrawRecord {
    param([Parameter(Mandatory)][int]$Draw)

    $key = $Draw.ToString()
    if (-not $draws.ContainsKey($key)) {
        $draws[$key] = [ordered]@{
            draw = $Draw
            operation = $null
            vertexCount = $null
            indexCount = $null
            instanceCount = $null
            ps = $null
            vs = $null
            cs = $null
            renderTargetCount = $null
            depthBound = $null
            outputs = [Collections.Generic.List[object]]::new()
        }
    }
    return $draws[$key]
}

$currentShaders = @{
    ps = $null
    vs = $null
    cs = $null
}
$currentRenderTargetCount = 0
$currentDepthBound = $false

if (Test-Path -LiteralPath $logPath -PathType Leaf) {
    foreach ($line in Get-Content -LiteralPath $logPath) {
        if ($line -notmatch '^(?:\d+\.)?(?<draw>\d{6})\s+(?<event>.+)$') {
            continue
        }

        $draw = [int]$Matches.draw
        $event = $Matches.event
        $record = Get-DrawRecord -Draw $draw

        if ($event -match '^PSSetShader\(.+hash=(?<hash>[0-9a-fA-F]{16})') {
            $currentShaders.ps = $Matches.hash.ToLowerInvariant()
            $record.ps = $currentShaders.ps
        }
        elseif ($event -match '^PSSetShader\(') {
            $currentShaders.ps = $null
            $record.ps = $null
        }
        elseif ($event -match '^VSSetShader\(.+hash=(?<hash>[0-9a-fA-F]{16})') {
            $currentShaders.vs = $Matches.hash.ToLowerInvariant()
            $record.vs = $currentShaders.vs
        }
        elseif ($event -match '^VSSetShader\(') {
            $currentShaders.vs = $null
            $record.vs = $null
        }
        elseif ($event -match '^CSSetShader\(.+hash=(?<hash>[0-9a-fA-F]{16})') {
            $currentShaders.cs = $Matches.hash.ToLowerInvariant()
            $record.cs = $currentShaders.cs
        }
        elseif ($event -match '^CSSetShader\(') {
            $currentShaders.cs = $null
            $record.cs = $null
        }
        elseif ($event -match '^OMSetRenderTargets\(NumViews:(?<count>\d+),.+pDepthStencilView:(?<depth>0x[0-9a-fA-F]+)') {
            $currentRenderTargetCount = [int]$Matches.count
            $currentDepthBound = $Matches.depth -ne '0x0000000000000000'
        }
        elseif ($event -match '^Draw\(VertexCount:(?<vertices>\d+),') {
            $record.operation = 'Draw'
            $record.vertexCount = [int]$Matches.vertices
        }
        elseif ($event -match '^DrawIndexed\(IndexCount:(?<indices>\d+),') {
            $record.operation = 'DrawIndexed'
            $record.indexCount = [int]$Matches.indices
        }
        elseif ($event -match '^DrawInstanced\(VertexCountPerInstance:(?<vertices>\d+), InstanceCount:(?<instances>\d+),') {
            $record.operation = 'DrawInstanced'
            $record.vertexCount = [int]$Matches.vertices
            $record.instanceCount = [int]$Matches.instances
        }
        elseif ($event -match '^DrawIndexedInstanced\(IndexCountPerInstance:(?<indices>\d+), InstanceCount:(?<instances>\d+),') {
            $record.operation = 'DrawIndexedInstanced'
            $record.indexCount = [int]$Matches.indices
            $record.instanceCount = [int]$Matches.instances
        }
        elseif ($event -match '^Dispatch\(') {
            $record.operation = 'Dispatch'
        }

        if ($record.operation) {
            $record.ps = $currentShaders.ps
            $record.vs = $currentShaders.vs
            $record.cs = $currentShaders.cs
            $record.renderTargetCount = $currentRenderTargetCount
            $record.depthBound = $currentDepthBound
        }
    }
}

$dumpGroups = Get-ChildItem -LiteralPath $capturePath -Recurse -File |
    Where-Object { $_.Name -notlike 'log*.txt' } |
    Group-Object { [IO.Path]::Combine($_.DirectoryName, [IO.Path]::GetFileNameWithoutExtension($_.Name)) }

foreach ($group in $dumpGroups) {
    $representative = $group.Group | Sort-Object Length -Descending | Select-Object -First 1
    $baseName = [IO.Path]::GetFileNameWithoutExtension($representative.Name)

    if ($baseName -notmatch '^(?:\d+\.)?(?<draw>\d{6})-(?<slot>oD|o\d+)(?<suffix>.*)$') {
        continue
    }

    $draw = [int]$Matches.draw
    $slot = $Matches.slot
    $suffix = $Matches.suffix
    $record = Get-DrawRecord -Draw $draw

    $resourceHash = $null
    if ($suffix -match '^=.*?(?<hash>[0-9a-fA-F]{8})(?:\(|-|$)') {
        $resourceHash = $Matches.hash.ToLowerInvariant()
    }

    $shaderHashes = [ordered]@{}
    foreach ($stageMatch in [regex]::Matches($suffix, '-(?<stage>vs|hs|ds|gs|ps|cs)=(?<hash>[0-9a-fA-F]{16})')) {
        $shaderHashes[$stageMatch.Groups['stage'].Value] = $stageMatch.Groups['hash'].Value.ToLowerInvariant()
    }

    foreach ($stage in @('ps', 'vs', 'cs')) {
        if ($shaderHashes.Contains($stage)) {
            $record[$stage] = $shaderHashes[$stage]
        }
    }

    $description = $group.Group | Where-Object Extension -eq '.dsc' | Select-Object -First 1
    $width = $null
    $height = $null
    $format = $null
    if ($description) {
        $descriptionText = Get-Content -Raw -LiteralPath $description.FullName
        if ($descriptionText -match '(?i)\bwidth\s*=\s*"?(?<value>\d+)') {
            $width = [int]$Matches.value
        }
        if ($descriptionText -match '(?i)\bheight\s*=\s*"?(?<value>\d+)') {
            $height = [int]$Matches.value
        }
        if ($descriptionText -match '(?i)\bformat\s*=\s*"(?<value>[^"]+)"') {
            $format = $Matches.value.Trim()
        }
    }

    $record.outputs.Add([pscustomobject]@{
        slot = $slot
        resourceHash = $resourceHash
        width = $width
        height = $height
        format = $format
        files = @($group.Group.Name | Sort-Object)
    })
}

$allDraws = @($draws.Values | Sort-Object draw)
$outputDraws = @($allDraws | Where-Object { $_.outputs.Count -gt 0 })
$operationDraws = @($allDraws | Where-Object { $null -ne $_.operation })
$maxDraw = if ($allDraws.Count) {
    ($allDraws | ForEach-Object { [int]$_['draw'] } | Measure-Object -Maximum).Maximum
}
else {
    0
}
$allOutputs = @($outputDraws | ForEach-Object { $_.outputs })
$colorOutputs = @($allOutputs | Where-Object { $_.slot -ne 'oD' })
$widthValues = @($colorOutputs | Where-Object { $null -ne $_.width } | ForEach-Object { [int]$_.width })
$heightValues = @($colorOutputs | Where-Object { $null -ne $_.height } | ForEach-Object { [int]$_.height })
$maxWidth = if ($widthValues.Count -gt 0) { ($widthValues | Measure-Object -Maximum).Maximum } else { $null }
$maxHeight = if ($heightValues.Count -gt 0) { ($heightValues | Measure-Object -Maximum).Maximum } else { $null }

$pixelShaderDrawCounts = @{}
foreach ($record in $operationDraws) {
    if (-not $record.ps) {
        continue
    }
    if (-not $pixelShaderDrawCounts.ContainsKey($record.ps)) {
        $pixelShaderDrawCounts[$record.ps] = 0
    }
    $pixelShaderDrawCounts[$record.ps]++
}

$candidates = foreach ($record in $operationDraws) {
    $score = 0
    $reasons = [Collections.Generic.List[string]]::new()

    if ($record.ps) {
        $score += 2
        $reasons.Add('pixel shader output')
        $psUseCount = $pixelShaderDrawCounts[$record.ps]
        if ($psUseCount -eq 1) {
            $score += 2
            $reasons.Add('unique pixel-shader draw')
        }
        elseif ($psUseCount -ge 5) {
            $score -= 2
            $reasons.Add("repeated pixel-shader family ($psUseCount draws)")
        }
    }
    if ($record.operation -eq 'Draw' -and $record.vertexCount -in @(3, 4)) {
        $score += 5
        $reasons.Add("fullscreen-style $($record.vertexCount)-vertex draw")
    }
    if ($record.operation -eq 'DrawIndexed' -and $record.indexCount -eq 3) {
        $score += 5
        $reasons.Add('fullscreen-style 3-index draw')
    }
    if ($record.renderTargetCount -gt 0) {
        $score += 2
        $reasons.Add("$($record.renderTargetCount) color target(s) bound")
    }
    elseif ($record.depthBound) {
        $score -= 4
        $reasons.Add('depth-only draw')
    }
    if ($maxDraw -gt 0 -and $record.draw -ge [math]::Floor($maxDraw * 0.8)) {
        $score += 2
        $reasons.Add('late-frame output')
    }
    $recordColorOutputs = @($record.outputs | Where-Object { $_.slot -ne 'oD' })
    $squareSingleChannelOutputs = @($recordColorOutputs | Where-Object {
        $null -ne $_.width -and $_.width -eq $_.height -and
        $_.format -match '^R(?:8|16|32)(?:_(?:FLOAT|UINT|SINT|UNORM|SNORM))?$'
    })
    if ($squareSingleChannelOutputs.Count -gt 0) {
        $score -= 6
        $reasons.Add('square single-channel utility target')
    }
    if ($maxWidth -and $maxHeight -and ($record.outputs | Where-Object { $_.width -eq $maxWidth -and $_.height -eq $maxHeight })) {
        $score += 3
        $reasons.Add("maximum captured resolution ${maxWidth}x${maxHeight}")
    }
    if ($recordColorOutputs | Where-Object slot -eq 'o0') {
        $reasons.Add('color output slot o0')
    }

    [pscustomobject]@{
        score = $score
        reasons = @($reasons)
        draw = $record.draw
        operation = $record.operation
        vertexCount = $record.vertexCount
        indexCount = $record.indexCount
        renderTargetCount = $record.renderTargetCount
        depthBound = $record.depthBound
        ps = $record.ps
        psUseCount = if ($record.ps) { $pixelShaderDrawCounts[$record.ps] } else { 0 }
        vs = $record.vs
        outputs = @($record.outputs)
    }
}

$report = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    captureRoot = $capturePath
    logPresent = Test-Path -LiteralPath $logPath -PathType Leaf
    drawCount = $allDraws.Count
    operationDrawCount = $operationDraws.Count
    outputDrawCount = $outputDraws.Count
    maximumDrawNumber = $maxDraw
    maximumCapturedDimensions = [ordered]@{
        width = $maxWidth
        height = $maxHeight
    }
    candidates = @($candidates | Sort-Object @{Expression='score';Descending=$true}, @{Expression='draw';Descending=$true} | Select-Object -First 50)
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$report | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Output "Analyzed capture: $capturePath"
Write-Output "Draw records: $($report.drawCount)"
Write-Output "Output draws: $($report.outputDrawCount)"
Write-Output "Candidate report: $OutputPath"
