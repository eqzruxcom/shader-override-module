[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$GameRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64',
    [string]$CaptureName = 'FrameAnalysis-2026-08-29-123153',
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if (-not $output.StartsWith((Join-Path $repo 'artifacts') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Study output must remain under workspace artifacts.' }
if (Test-Path -LiteralPath $output) { throw 'Output exists; preserve earlier evidence.' }
$cache = Join-Path $GameRoot 'ShaderCache'
$frameLog = Join-Path (Join-Path $GameRoot $CaptureName) 'log.txt'
$assembler = Join-Path $repo 'artifacts\shader-assembler-build\bin\cmd_Decompiler.exe'
$expectedExe = '25B54C345C94EE9F6C6876B9C7537A69E6B0EEF25F322207C32A8DDCEE816635'
if ((Get-FileHash -LiteralPath (Join-Path $GameRoot 'ff7remake_.exe')).Hash -ne $expectedExe) { throw 'Executable fingerprint changed.' }
$variants = @(
    @{ Hash='c30cdc8365df9840'; Event=1028; Offset=0; AO=6; OtherOcclusion=7; Shadow='r29.z'; Binary='0FF0D61014A447B4B9E133CDAD1C927F8A5ABFE8396151BED3E4A5D537483216' },
    @{ Hash='62b33a2d1e505241'; Event=1029; Offset=12; AO=5; OtherOcclusion=6; Shadow='r17.y'; Binary='1E290F68B5A07E8987A674384B955C0D6A8246A96B47506CD2E4CC6E6EED9551' },
    @{ Hash='5a9fbefe0ab6f815'; Event=1030; Offset=24; AO=5; OtherOcclusion=6; Shadow='r21.z'; Binary='45D1C022E89B58C9524E86F54901FCCB98D93448940B1E925CE53D133D36BA16' },
    @{ Hash='0e97888f9a8767da'; Event=1031; Offset=36; AO=6; OtherOcclusion=7; Shadow='r21.y'; Binary='B6D1E0A7EA8032F55EAA6017D39BF70B097669335951DBF437782C5804BCF283' },
    @{ Hash='08bb8764f1840179'; Event=1032; Offset=48; AO=6; OtherOcclusion=7; Shadow='r15.w'; Binary='CB9A9EE79FF8DB0B63B8DD6F239AF69FF23A83D786A46E51EB07D352DD7659EE' }
)
$logText = Get-Content -LiteralPath $frameLog -Raw
foreach ($v in $variants) {
    $binaryPath = Join-Path $cache ($v.Hash + '-cs.bin')
    if ((Get-FileHash -LiteralPath $binaryPath).Hash -ne $v.Binary) { throw "Original binary changed: $($v.Hash)" }
    $eventPrefix = '{0:D6}' -f $v.Event
    if ($logText -notmatch "(?m)^$eventPrefix CSSetShader\([^\r\n]+hash=$($v.Hash)\s*$" -or
        $logText -notmatch "(?m)^$eventPrefix DispatchIndirect\([^\r\n]+AlignedByteOffsetForArgs:$($v.Offset)\)") { throw "Captured dispatch mismatch: $($v.Hash)" }
}
foreach ($toolPath in @($assembler,$FxcPath)) { if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) { throw "Missing tool: $toolPath" } }
$utf8 = [Text.UTF8Encoding]::new($false)
$null = New-Item -ItemType Directory -Path $output
Copy-Item -LiteralPath $frameLog -Destination (Join-Path $output 'frame-log.txt')
function Invoke-StudyTool([string]$Tool, [string[]]$Arguments, [string]$LogPath) {
    $messages = & $Tool @Arguments 2>&1
    $resultCode = $LASTEXITCODE
    [IO.File]::WriteAllText($LogPath, ($messages | Out-String), $utf8)
    if ($resultCode -ne 0) { throw "Offline tool failed; inspect $LogPath" }
}
function Get-Evidence([string[]]$Lines, [string]$Pattern) {
    $found = @(for ($i=0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match $Pattern) { [pscustomobject]@{line=$i+1; instruction=$Lines[$i].Trim()} }
    })
    if (-not $found.Count) { throw "Expected native instruction missing: $Pattern" }
    return $found
}
$records = foreach ($v in $variants) {
    $baseName = $v.Hash + '-cs'
    $binaryCopy = Join-Path $output ($baseName + '.bin')
    Copy-Item -LiteralPath (Join-Path $cache ($baseName + '.bin')) -Destination $binaryCopy
    Copy-Item -LiteralPath (Join-Path $cache ($baseName + '_replace.txt')) -Destination (Join-Path $output ($baseName + '-cached-decompilation.txt'))
    Invoke-StudyTool $FxcPath @('/nologo','/dumpbin','/Fc',(Join-Path $output ($baseName + '-fxc.asm')),$binaryCopy) (Join-Path $output ($baseName + '-fxc.log'))
    Invoke-StudyTool $assembler @('-d','-V',$binaryCopy) (Join-Path $output ($baseName + '-validation.log'))
    Invoke-StudyTool $assembler @('-a','--copy-reflection',$binaryCopy,(Join-Path $output ($baseName + '.asm'))) (Join-Path $output ($baseName + '-roundtrip.log'))
    $neutralHash = (Get-FileHash -LiteralPath (Join-Path $output ($baseName + '.shdr'))).Hash
    if ($neutralHash -ne $v.Binary) { throw "Neutral round trip is not byte-identical: $baseName" }
    $asmLines = @(Get-Content -LiteralPath (Join-Path $output ($baseName + '-fxc.asm')))
    $shadow = [regex]::Escape($v.Shadow)
    $patterns = [ordered]@{
        computeGroup = '^\s*dcl_thread_group 16, 16, 1\s*$'
        normalLoad = '^\s*ld_indexable.*r3.xyz,.*t1\.'
        materialLoad = '^\s*ld_indexable.*r5.xyzw,.*t3\.'
        screenAO = ('^\s*sample_l_indexable.*r3.w,.*t' + $v.AO + '\.')
        otherOcclusion = ('^\s*sample_l_indexable.*r4.x,.*t' + $v.OtherOcclusion + '\.')
        combineProduct = '^\s*mul r0.y, r3.w, r5.w\s*$'
        combineLower = '^\s*min r0.z, r3.w, r5.w\s*$'
        combineSquare = '^\s*mul r2.x, r2.x, r2.x\s*$'
        shadowMinimum = ('^\s*min ' + $shadow + ', r0.y, ' + $shadow + '\s*$')
        shadowFallback = ('^\s*mov ' + $shadow + ', r0.y\s*$')
        output = '^\s*store_uav_typed u0.xyzw,'
    }
    $evidence = [ordered]@{}
    foreach ($key in $patterns.Keys) { $evidence[$key] = @(Get-Evidence $asmLines $patterns[$key]) }
    [ordered]@{
        shaderHash=$v.Hash; stage='cs'; capturedEvent=$v.Event; indirectArgumentOffset=$v.Offset
        originalSha256=$v.Binary; neutralSha256=$neutralHash; byteIdenticalRoundTrip=$true
        fxcAssembly=($baseName + '-fxc.asm'); fxcAssemblySha256=(Get-FileHash -LiteralPath (Join-Path $output ($baseName + '-fxc.asm'))).Hash
        screenAOSlot=$v.AO; otherOcclusionSlot=$v.OtherOcclusion; nativeShadowRegister=$v.Shadow
        instructionEvidence=$evidence; runtimeEligible=$false
    }
}
$relatedRecords = foreach ($supportShader in @('f97a821dddaa328a-cs','a8845c7ad73425a9-ps','c814bac1ac75b35e-cs','53fca3b84eeecea5-ps','37efcd402da50bcb-ps','b9e2305a994308f2-cs')) {
    $supportBinary = Join-Path $output ($supportShader + '.bin')
    Copy-Item -LiteralPath (Join-Path $cache ($supportShader + '.bin')) -Destination $supportBinary
    Copy-Item -LiteralPath (Join-Path $cache ($supportShader + '_replace.txt')) -Destination (Join-Path $output ($supportShader + '-cached-decompilation.txt'))
    $supportAssembly = Join-Path $output ($supportShader + '-fxc.asm')
    Invoke-StudyTool $FxcPath @('/nologo','/dumpbin','/Fc',$supportAssembly,$supportBinary) (Join-Path $output ($supportShader + '-fxc.log'))
    [ordered]@{shader=$supportShader;originalSha256=(Get-FileHash -LiteralPath $supportBinary).Hash;fxcAssembly=($supportShader + '-fxc.asm');fxcAssemblySha256=(Get-FileHash -LiteralPath $supportAssembly).Hash;roundTripTested=$false}
}
$report = [ordered]@{
    schemaVersion=1; generatedAtUtc=[DateTime]::UtcNow.ToString('o'); purpose='Native surface-lighting occlusion audit; not an effect install'
    executableSha256=$expectedExe; capture=$CaptureName; frameLogSha256=(Get-FileHash -LiteralPath (Join-Path $output 'frame-log.txt')).Hash
    localResearchOnly=$true; redistributionAllowed=$false; runtimeEligible=$false
    fxcSha256=(Get-FileHash -LiteralPath $FxcPath).Hash; assemblerSha256=(Get-FileHash -LiteralPath $assembler).Hash
    nativeOcclusionFinding='The original binaries combine material/screen/other occlusion before per-light attenuation. This does not establish equivalence to the donor Uncharted4 method or a visual benefit from replacing it.'
    limitations=@('No live replacement executed','No new texture or constant-buffer contents captured','Indirect dispatch invocation does not prove every variant shaded visible pixels','Material-channel semantics require producer audit before effect insertion')
    variants=@($records); relatedProducerAndClassifierEvidence=@($relatedRecords)
}
[IO.File]::WriteAllText((Join-Path $output 'study.json'), (($report | ConvertTo-Json -Depth 12) + "`n"), $utf8)
[pscustomobject]@{Result='offline-native-audit-passed';Variants=@($records).Count;RuntimeEligible=$false;Output=$output}
