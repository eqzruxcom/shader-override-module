[CmdletBinding()]
param(
    [string]$FrameLogPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\surface-lighting-study-20260830-v3\frame-log.txt'),
    [string]$AssemblyDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\assembly'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\ff7-remake-intergrade-bloom-pyramid.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$frameLog = [IO.Path]::GetFullPath($FrameLogPath)
$assembly = [IO.Path]::GetFullPath($AssemblyDirectory).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputPath)
foreach ($path in @($frameLog,$assembly)) { if (-not (Test-Path -LiteralPath $path)) { throw "Required input is missing: $path" } }
if (-not $frameLog.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase) -or
    -not $assembly.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase) -or
    -not $output.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Inputs and output must remain under artifacts' }

$hashes = [ordered]@{
    downsample = 'c58358673087aaf8'
    pyramidCopy = 'c587b5832661bf21'
    upsampleCombine = '179d5c6f3926223d'
    bloomComposite = '18305e60b4378edb'
    finalColor = '41f1bf8b79d01319'
}

$events = [Collections.Generic.List[object]]::new()
$drawEvents = [Collections.Generic.List[object]]::new()
$activePixelShader = $null
foreach ($line in Get-Content -LiteralPath $frameLog) {
    $m = [regex]::Match($line,'^(?<event>\d{6}) PSSetShader\([^\r\n]+\) hash=(?<hash>[0-9a-f]{16})$')
    if ($m.Success) {
        $activePixelShader = $m.Groups['hash'].Value
        if ($hashes.Values -contains $activePixelShader) {
            $events.Add([pscustomobject][ordered]@{event=[int]$m.Groups['event'].Value;hash=$activePixelShader})
        }
        continue
    }
    $draw = [regex]::Match($line,'^(?<event>\d{6}) DrawIndexed\(')
    if ($draw.Success -and $hashes.Values -contains $activePixelShader) {
        $drawEvents.Add([pscustomobject][ordered]@{event=[int]$draw.Groups['event'].Value;hash=$activePixelShader})
    }
}

function Read-AssemblyFacts([string]$Hash) {
    $path = Join-Path $assembly ($Hash + '-ps.asm')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Assembly missing: $path" }
    $text = Get-Content -Raw -LiteralPath $path
    [ordered]@{
        hash = $Hash
        stage = if ($text -match '(?m)^ps_5_0$') {'ps_5_0'} else {'unexpected'}
        texture2DCount = [regex]::Matches($text,'(?m)^dcl_resource_texture2d\s').Count
        texture3DCount = [regex]::Matches($text,'(?m)^dcl_resource_texture3d\s').Count
        samplerCount = [regex]::Matches($text,'(?m)^dcl_sampler\s').Count
        sampleInstructionCount = [regex]::Matches($text,'(?m)^(?:sample|sample_l)_indexable').Count
        outputCount = [regex]::Matches($text,'(?m)^dcl_output\s').Count
        assemblyPath = [IO.Path]::GetRelativePath($root,$path).Replace('\','/')
        assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    }
}

$facts = [ordered]@{}
foreach ($entry in $hashes.GetEnumerator()) { $facts[$entry.Key] = Read-AssemblyFacts $entry.Value }
$downEvents = @($events | Where-Object hash -eq $hashes.downsample | Select-Object -ExpandProperty event)
$downDraws = @($drawEvents | Where-Object hash -eq $hashes.downsample | Select-Object -ExpandProperty event)
$copyEvents = @($events | Where-Object hash -eq $hashes.pyramidCopy | Select-Object -ExpandProperty event)
$upEvents = @($events | Where-Object hash -eq $hashes.upsampleCombine | Select-Object -ExpandProperty event)
$compositeEvents = @($events | Where-Object hash -eq $hashes.bloomComposite | Select-Object -ExpandProperty event)
$finalEvents = @($events | Where-Object hash -eq $hashes.finalColor | Select-Object -ExpandProperty event)

$report = [ordered]@{
    schemaVersion = 1
    detector = 'ff7-remake-dxbc-bloom-pyramid-v1'
    scope = 'Read-only late-frame shader-sequence and DXBC binding analysis.'
    frameLog = [ordered]@{path=[IO.Path]::GetRelativePath($root,$frameLog).Replace('\','/');sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $frameLog).Hash}
    shaderRoles = [ordered]@{
        downsample = $facts.downsample
        pyramidCopy = $facts.pyramidCopy
        upsampleCombine = $facts.upsampleCombine
        bloomComposite = $facts.bloomComposite
        finalColor = $facts.finalColor
    }
    sequence = [ordered]@{
        c583DownsampleEvents = $downEvents
        c583DownsampleDrawEvents = $downDraws
        c587PyramidEvents = $copyEvents
        upsampleCombineEvents = $upEvents
        bloomCompositeEvents = $compositeEvents
        finalColorEvents = $finalEvents
    }
    classification = [ordered]@{
        c58358673087aaf8 = 'repeated one-input four-sample bloom-pyramid downsample/resample pass'
        relationshipToWhiteSkin = 'downstream amplifier/transport: overbright skin entering the post chain can bloom, but c583 does not create the upstream skin lighting'
        relationshipToIndirectLighting = 'not an indirect-light producer; editing it changes bloom/glow and bright areas, not geometric color bounce on floors or walls'
    }
    policy = [ordered]@{
        indirectLighting = 'Fix the upstream radiance/receiver composite before changing c583.'
        bloom = 'Treat c583 and its paired pyramid shaders as a separate later feature with its own control and tests.'
    }
}

[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,(($report | ConvertTo-Json -Depth 12)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{DownsampleShaderBinds=$downEvents.Count;DownsampleDraws=$downDraws.Count;PyramidEvents=$copyEvents.Count;UpsampleEvents=$upEvents.Count;BloomCompositeEvents=$compositeEvents.Count;FinalColorEvents=$finalEvents.Count;Output=$output}
