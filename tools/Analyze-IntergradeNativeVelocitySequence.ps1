[CmdletBinding()]
param(
    [string]$CaptureDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\FrameAnalysis-2026-09-04-001641',
    [string]$ComputeMirrorManifest = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-live-compute-census-20260903-v3\manifest.json'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-native-velocity-sequence-20260904.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must remain under artifacts: $output"
}

$capture = [IO.Path]::GetFullPath($CaptureDirectory).TrimEnd('\')
$logPath = Join-Path $capture 'log.txt'
$usagePath = Join-Path $capture 'ShaderUsage.txt'
foreach ($required in @($logPath,$usagePath,$ComputeMirrorManifest)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required input is missing: $required" }
}

$manifest = Get-Content -Raw -LiteralPath $ComputeMirrorManifest | ConvertFrom-Json
function Get-ComputeAssembly([string]$Hash) {
    $record = @($manifest.shaders | Where-Object shader -eq "$Hash-cs")
    if ($record.Count -ne 1) { throw "Expected one compute mirror for $Hash; found $($record.Count)" }
    if (-not (Test-Path -LiteralPath $record[0].mirror -PathType Leaf)) { throw "Compute mirror is missing: $($record[0].mirror)" }
    return [ordered]@{
        hash = $Hash
        path = [IO.Path]::GetRelativePath($root,[IO.Path]::GetFullPath($record[0].mirror)).Replace('\','/')
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $record[0].mirror).Hash
        text = Get-Content -Raw -LiteralPath $record[0].mirror
    }
}

$reduce = Get-ComputeAssembly 'a26b3473289dba2d'
$dilate = Get-ComputeAssembly '58101bdcc044cd88'

$events = @{}
foreach ($line in [IO.File]::ReadLines($logPath)) {
    if ($line -notmatch '^(?<event>\d{6}) ') { continue }
    $event = [int]$Matches.event
    if (-not $events.ContainsKey($event)) {
        $events[$event] = [ordered]@{ event=$event; vs=@(); ps=@(); cs=@(); dispatch=@(); drawIndexed=@() }
    }
    if ($line -match 'VSSetShader\([^\r\n]*hash=(?<hash>[0-9a-fA-F]{16})\s*$') {
        $events[$event].vs += $Matches.hash.ToLowerInvariant()
    }
    if ($line -match 'PSSetShader\([^\r\n]*hash=(?<hash>[0-9a-fA-F]{16})\s*$') {
        $events[$event].ps += $Matches.hash.ToLowerInvariant()
    }
    if ($line -match 'CSSetShader\([^\r\n]*hash=(?<hash>[0-9a-fA-F]{16})\s*$') {
        $events[$event].cs += $Matches.hash.ToLowerInvariant()
    }
    if ($line -match 'Dispatch\(ThreadGroupCountX:(?<x>\d+), ThreadGroupCountY:(?<y>\d+), ThreadGroupCountZ:(?<z>\d+)\)') {
        $events[$event].dispatch += [ordered]@{ x=[int]$Matches.x; y=[int]$Matches.y; z=[int]$Matches.z }
    }
    if ($line -match 'DrawIndexed\(IndexCount:(?<count>\d+), StartIndexLocation:(?<start>\d+), BaseVertexLocation:(?<base>-?\d+)\)') {
        $events[$event].drawIndexed += [ordered]@{ indexCount=[int]$Matches.count; startIndex=[int]$Matches.start; baseVertex=[int]$Matches.base }
    }
}

$sequences = [Collections.Generic.List[object]]::new()
foreach ($entry in @($events.GetEnumerator() | Sort-Object { [int]$_.Key })) {
    $event = [int]$entry.Key
    if (@($entry.Value.ps) -notcontains 'c473ab75b7519f7e') { continue }
    if (-not $events.ContainsKey($event+1) -or -not $events.ContainsKey($event+2) -or -not $events.ContainsKey($event+3)) { continue }
    if (@($events[$event+1].cs) -notcontains $reduce.hash) { continue }
    if (@($events[$event+2].cs) -notcontains $dilate.hash) { continue }
    if (@($events[$event+3].ps) -notcontains 'af6cd28a0108a18a') { continue }
    $sequences.Add([ordered]@{
        sceneTemporalResolve = [ordered]@{ event=$event; ps='c473ab75b7519f7e'; drawIndexed=@($entry.Value.drawIndexed) }
        velocityTileReduction = [ordered]@{ event=$event+1; cs=$reduce.hash; dispatch=@($events[$event+1].dispatch) }
        velocityTileDilation = [ordered]@{ event=$event+2; cs=$dilate.hash; dispatch=@($events[$event+2].dispatch) }
        followingFullscreenPass = [ordered]@{ event=$event+3; ps='af6cd28a0108a18a'; drawIndexed=@($events[$event+3].drawIndexed) }
    })
}
if ($sequences.Count -ne 1) { throw "Expected one c473 -> a26b -> 5810 -> af6c sequence; found $($sequences.Count)" }

$sequence = $sequences[0]
if (@($sequence.velocityTileReduction.dispatch).Count -ne 1) { throw 'Velocity reduction dispatch is missing or ambiguous' }
if (@($sequence.velocityTileDilation.dispatch).Count -ne 1) { throw 'Velocity dilation dispatch is missing or ambiguous' }
$reduceDispatch = $sequence.velocityTileReduction.dispatch[0]
$dilateDispatch = $sequence.velocityTileDilation.dispatch[0]

$usage = Get-Content -Raw -LiteralPath $usagePath
$depthMatch = [regex]::Match($usage,'<CopySource orig_hash=00236552 type=Texture2D width=(?<width>\d+) height=(?<height>\d+)[^>]+format="R32G8X24_TYPELESS"')
if (-not $depthMatch.Success) { throw 'Captured full-resolution depth resource was not found in ShaderUsage.txt' }
$frameWidth = [int]$depthMatch.Groups['width'].Value
$frameHeight = [int]$depthMatch.Groups['height'].Value

$reduceChecks = [ordered]@{
    shaderModelCs50 = $reduce.text -match '(?m)^cs_5_0$'
    threadGroup16x16x1 = $reduce.text -match '(?m)^dcl_thread_group 16, 16, 1$'
    twoTextureInputs = [regex]::Matches($reduce.text,'(?m)^dcl_resource_texture2d ').Count -eq 2
    twoFloat4TextureOutputs = [regex]::Matches($reduce.text,'(?m)^dcl_uav_typed_texture2d \(float,float,float,float\) u[01]$').Count -eq 2
    readsVectorXYFromT0 = $reduce.text -match '(?m)^ld_indexable\(texture2d\)\(float,float,float,float\) r\d+\.xy, r\d+\.xyww, t0\.xyzw$'
    readsDepthFromT1 = $reduce.text -match '(?m)^ld_indexable\(texture2d\)\(float,float,float,float\) r\d+\.z, r\d+\.xyzw, t1\.yzxw$'
    sharedTileReduction = $reduce.text -match '(?m)^dcl_tgsm_structured g0, 16, 256$' -and [regex]::Matches($reduce.text,'(?m)^sync_g_t$').Count -ge 3
    writesFullResolutionU0 = $reduce.text -match '(?m)^\s*store_uav_typed u0\.xyzw, r\d+\.xyyy, r\d+\.xyzw$'
    writesPerTileU1 = $reduce.text -match '(?m)^\s*store_uav_typed u1\.xyzw, vThreadGroupID\.xyyy, r\d+\.xyzw$'
    exactFrameCoverage = ($reduceDispatch.x * 16 -eq $frameWidth) -and ($reduceDispatch.y * 16 -eq $frameHeight) -and $reduceDispatch.z -eq 1
}

$dilateChecks = [ordered]@{
    shaderModelCs50 = $dilate.text -match '(?m)^cs_5_0$'
    threadGroup16x16x1 = $dilate.text -match '(?m)^dcl_thread_group 16, 16, 1$'
    oneTextureInput = [regex]::Matches($dilate.text,'(?m)^dcl_resource_texture2d ').Count -eq 1
    oneFloat4TextureOutput = [regex]::Matches($dilate.text,'(?m)^dcl_uav_typed_texture2d \(float,float,float,float\) u0$').Count -eq 1
    neighborhoodStartsAtMinus4 = $dilate.text -match '(?m)^mov r\d+\.w, l\(-4\)$'
    neighborhoodStopsAfterPlus4 = [regex]::Matches($dilate.text,'(?m)^\s*ilt r\d+\.[xyzw], l\(4\), r\d+\.[xyzw]$').Count -ge 2
    comparesVectorMagnitude = [regex]::Matches($dilate.text,'(?m)^\s*dp2 ').Count -ge 4
    writesDilatedTile = $dilate.text -match '(?m)^\s*store_uav_typed u0\.xyzw, vThreadID\.xyyy, r\d+\.xyzw$'
    dispatchCoversReductionGrid = ($dilateDispatch.x * 16 -ge $reduceDispatch.x) -and ($dilateDispatch.x * 16 -lt $reduceDispatch.x + 16) -and ($dilateDispatch.y * 16 -ge $reduceDispatch.y) -and ($dilateDispatch.y * 16 -lt $reduceDispatch.y + 16)
}

if ($reduceChecks.Values -contains $false) { throw 'Velocity reduction structural proof failed' }
if ($dilateChecks.Values -contains $false) { throw 'Velocity dilation structural proof failed' }

$report = [ordered]@{
    schemaVersion = 1
    detector = 'ff7-remake-native-velocity-sequence-v1'
    scope = 'Read-only runtime-order and assembly-dataflow proof for the native post-temporal velocity reduction/dilation sequence.'
    capture = [ordered]@{
        name = Split-Path -Leaf $capture
        directory = $capture
        logSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $logPath).Hash
        shaderUsageSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $usagePath).Hash
        frame = [ordered]@{ width=$frameWidth; height=$frameHeight; depthResourceHash='00236552'; depthFormat='R32G8X24_TYPELESS' }
    }
    runtimeSequence = $sequence
    velocityTileReduction = [ordered]@{
        hash = $reduce.hash
        assemblyPath = $reduce.path
        assemblySha256 = $reduce.sha256
        checks = $reduceChecks
        outputGrid = [ordered]@{ width=$reduceDispatch.x; height=$reduceDispatch.y }
        classification = 'full-resolution motion/depth evaluation plus per-tile vector/depth extent reduction'
    }
    velocityTileDilation = [ordered]@{
        hash = $dilate.hash
        assemblyPath = $dilate.path
        assemblySha256 = $dilate.sha256
        checks = $dilateChecks
        dispatchCoverage = [ordered]@{ width=$($dilateDispatch.x*16); height=$($dilateDispatch.y*16); validTileWidth=$reduceDispatch.x; validTileHeight=$reduceDispatch.y }
        classification = 'nine-by-nine neighborhood selection/dilation over the reduced motion-vector tile grid'
    }
    sampleGIExclusion = [ordered]@{
        excludedHash = $reduce.hash
        verdict = 'proven structural and runtime false positive'
        reasons = @(
            'The dispatch covers the full frame exactly and emits one full-resolution output plus one 16x16 per-tile reduction, rather than paired irradiance volumes.',
            'Its inputs are a vector-like XY field and scene depth; it contains no shading-model decode or radiance/irradiance branch.',
            'The immediately following compute pass performs neighborhood vector selection/dilation over the reduced tile grid.',
            'The chain executes after c473ab75b7519f7e and directly before af6cd28a0108a18a, so c473 remains the valid pre-velocity/pre-motion-blur injection boundary.'
        )
        policy = 'Do not classify or transform a26b3473289dba2d as SampleGI. Retain it as a negative control for resource-count-only family matching.'
    }
}

[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,(($report | ConvertTo-Json -Depth 14)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Event=$sequence.sceneTemporalResolve.event; Frame="${frameWidth}x${frameHeight}"; Reduction="$($reduceDispatch.x)x$($reduceDispatch.y)"; Dilation="$($dilateDispatch.x)x$($dilateDispatch.y)"; Output=$output }

