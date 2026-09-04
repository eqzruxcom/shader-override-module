[CmdletBinding()]
param(
    [string]$ZeroPackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-owned-fullscreen-zero-pack'),
    [string]$TunedCompositeRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\tests\agent2-r3d-ssgi-native-tuned-remake-character-compiled'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-clean-owned-real-pack'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifactRoot = Join-Path $workspace 'artifacts'
$zero = [IO.Path]::GetFullPath($ZeroPackRoot).TrimEnd('\')
$tuned = [IO.Path]::GetFullPath($TunedCompositeRoot).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
foreach ($path in @($zero,$tuned,$output)) {
    if (-not $path.StartsWith($artifactRoot+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'All package paths must remain beneath workspace artifacts.' }
}
$zeroManifestPath = Join-Path $zero 'manifest.json'
$tunedReceiptPath = Join-Path $tuned 'receipt.json'
$tunedCompositePath = Join-Path $tuned 'Agent2R3DSSGICompositeE2AA_ps.hlsl'
foreach ($path in @($zeroManifestPath,$tunedReceiptPath,$tunedCompositePath,$FxcPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required input is missing: $path" }
}
if (Test-Path -LiteralPath $output) { throw "Output already exists; preserve prior evidence: $output" }

$zeroManifest = Get-Content -Raw -LiteralPath $zeroManifestPath | ConvertFrom-Json
$tunedReceipt = Get-Content -Raw -LiteralPath $tunedReceiptPath | ConvertFrom-Json
if ($zeroManifest.schemaVersion -ne 1 -or $zeroManifest.result -ne 'pass' -or $zeroManifest.runtimeEligible -ne $false -or
    $zeroManifest.hook -ne 'e2aa1c8cb39e0a55-ps' -or $zeroManifest.ownedPass.draw -ne '3, 0' -or @($zeroManifest.files).Count -ne 8) {
    throw 'Zero owned-fullscreen source manifest is invalid.'
}
if ($tunedReceipt.result -ne 'pass' -or $tunedReceipt.classification -ne 'offline-remake-character-receiver-guard-candidate' -or
    $tunedReceipt.compile.hlslSha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $tunedCompositePath).Hash) {
    throw 'Tuned real composite receipt is invalid or drifted.'
}

$sourceMods = Join-Path $zero 'Mods'
foreach ($file in @($zeroManifest.files)) {
    $sourcePath = Join-Path $sourceMods ([string]$file.name)
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash -ne [string]$file.sha256) {
        throw "Zero-pack source drifted: $($file.name)"
    }
}

$tunedComposite = [IO.File]::ReadAllText($tunedCompositePath)
if ($tunedComposite -notmatch '(?m)^\s*return float4\(indirectRadiance, 0\.0\);\s*$' -or
    $tunedComposite -notmatch 'shadingModel == 3u.*shadingModel == 5u.*shadingModel == 7u.*shadingModel == 8u.*shadingModel == 9u') {
    throw 'Tuned composite lacks the real indirect return or complete reviewed character guard.'
}

$outputMods = Join-Path $output 'Mods'
$compileRoot = Join-Path $output 'compile-verification'
[IO.Directory]::CreateDirectory($outputMods)|Out-Null
[IO.Directory]::CreateDirectory($compileRoot)|Out-Null
foreach ($file in Get-ChildItem -LiteralPath $sourceMods -File) {
    if ($file.Name -eq 'Agent2R3DSSGICompositeE2AA_ps.hlsl') { continue }
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $outputMods $file.Name)
}
Copy-Item -LiteralPath $tunedCompositePath -Destination (Join-Path $outputMods 'Agent2R3DSSGICompositeE2AA_ps.hlsl')

$iniPath = Join-Path $outputMods 'Agent2R3DSSGITest.ini'
$ini = [IO.File]::ReadAllText($iniPath)
$ini = $ini.Replace('; ISOLATION MATRIX: 05-zero-composite','; CLEAN OWNED FULLSCREEN: real single-path composite')
$ini = $ini.Replace('; Runs the complete chain with the diagnostic composite shader returning zero.','; Runs the complete chain and adds indirect RGB only through the owned fullscreen pass.')
[IO.File]::WriteAllText($iniPath,$ini,[Text.UTF8Encoding]::new($false))

$compiled = [Collections.Generic.List[object]]::new()
foreach ($file in Get-ChildItem -LiteralPath $outputMods -Filter '*.hlsl' -File | Sort-Object Name) {
    $profile = if ($file.Name.EndsWith('_vs.hlsl',[StringComparison]::OrdinalIgnoreCase)) {'vs_5_0'} else {'ps_5_0'}
    $bin = Join-Path $compileRoot ($file.BaseName+'.bin')
    $asm = Join-Path $compileRoot ($file.BaseName+'.asm')
    & $FxcPath /nologo /Ges /WX /O3 /T $profile /E main /Fo $bin /Fc $asm $file.FullName
    if ($LASTEXITCODE -ne 0) { throw "Strict shader compilation failed ($profile): $($file.Name)" }
    $compiled.Add([ordered]@{name=$file.Name;profile=$profile;hlslSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash;dxbcSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $bin).Hash;assemblySha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $asm).Hash})
}

$ini = [IO.File]::ReadAllText($iniPath)
foreach ($needle in @('key = no_modifiers F2','vs = Agent2R3DSSGIFullscreen_vs.hlsl','draw = 3, 0','blend = ADD ONE ONE')) {
    if (-not $ini.Contains($needle)) { throw "Clean owned real pack lacks required contract: $needle" }
}
if ($ini -match '(?im)^\s*key\s*=.*(?:F10|VK_PRIOR|VK_NEXT).*$' -or $ini -match '(?im)^\s*draw\s*=\s*from_caller\s*$' -and
    [regex]::Matches($ini,'(?im)^\s*draw\s*=\s*from_caller\s*$').Count -ne 5) {
    throw 'Clean owned real pack changed reserved keys or caller-draw count.'
}
if (Test-Path -LiteralPath (Join-Path $output 'ShaderFixes')) { throw 'Clean owned pack must not ship a native e2aa ShaderFixes replacement.' }

$files = @(Get-ChildItem -LiteralPath $outputMods -File | Sort-Object Name | ForEach-Object {[ordered]@{name=$_.Name;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash;bytes=$_.Length}})
$manifest = [ordered]@{
    schemaVersion=1;result='pass';kind='ff7-remake-clean-owned-fullscreen-real-ssgi'
    purpose='Add reviewed R3D-style indirect RGB exactly once through injector-owned fullscreen geometry.'
    source=[ordered]@{zeroOwnedManifest=$zeroManifestPath;zeroOwnedManifestSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $zeroManifestPath).Hash;tunedCompositeReceipt=$tunedReceiptPath;tunedCompositeReceiptSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $tunedReceiptPath).Hash}
    hook='e2aa1c8cb39e0a55-ps';architecture='single owned fullscreen composite; native e2aa remains unmodified'
    controls=[ordered]@{F2='off/on';F10='native reload unchanged';PageUp='unchanged';PageDown='unchanged';Number1='contact family';Number2='contact family';Number3='contact family'}
    ownedPass=[ordered]@{vertexInput='SV_VertexID';draw='3, 0';topology='triangle_list';blend='ADD ONE ONE';depth='disabled';stencil='disabled';cull='none'}
    compile=@($compiled);files=$files;nativeE2aaReplacementIncluded=$false
    prerequisite='The clean owned literal-zero F2 diagnostic must have live visual parity before staging this real candidate.'
    runtimeEligible=$false;installed=$false;liveTestsPerformed=$false
}
$manifestPath = Join-Path $output 'manifest.json'
[IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 10)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
Write-Host "OUTPUT=$output"
Write-Host "MANIFEST=$manifestPath"
Write-Host 'PASS: clean single-path owned-fullscreen real SSGI pack generated and compiled; native e2aa replacement excluded; live staging remains gated on zero-pass parity.'
