[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Balanced','Strong')]
    [string]$Preset,
    [string]$SourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\captured-shaders\e2aa1c8cb39e0a55-ps\e2aa1c8cb39e0a55-ps_decompiled.txt'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-rebirth-fallback-consumer-variants'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$expectedSourceSha256 = 'E82E8D7A5EF91FD954B50A95CBC250B08F43B28C91450B9EC2106A82478A6716'

function Resolve-WorkspacePath([string]$Path, [switch]$AllowMissing) {
    $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $repoRoot $Path)) }
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Path must remain inside the project workspace: $full" }
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "File does not exist: $full" }
    $full
}

$sourceFull = Resolve-WorkspacePath $SourcePath
$outputFull = Resolve-WorkspacePath $OutputDirectory -AllowMissing
if (-not (Test-Path -LiteralPath $FxcPath -PathType Leaf)) { throw "FXC was not found: $FxcPath" }
$actualSourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceFull).Hash
if ($actualSourceSha256 -ne $expectedSourceSha256) {
    throw "Refusing changed or unmatched e2aa source. Expected $expectedSourceSha256; got $actualSourceSha256."
}

$spec = switch ($Preset) {
    'Balanced' { [ordered]@{ suffix='Balanced'; screenExpression='pow(saturate(r0.x), 1.50)'; screenPower=1.50; characterPower=1.375; donorFidelity='conservative interpolation toward donor fallback' } }
    'Strong'   { [ordered]@{ suffix='Strong'; screenExpression='r0.x * r0.x'; screenPower=2.00; characterPower=1.750; donorFidelity='literal donor native-ScreenAO fallback strength' } }
}
$characterPowerLiteral = ([double]$spec.characterPower).ToString('0.000', [Globalization.CultureInfo]::InvariantCulture)

[void](New-Item -ItemType Directory -Path $outputFull -Force)
$baseName = "RebirthFallbackAO$($spec.suffix)_ps"
$hlslPath = Join-Path $outputFull "$baseName.hlsl"
$objectPath = Join-Path $outputFull "$baseName.cso"
$assemblyPath = Join-Path $outputFull "$baseName.asm"
$manifestPath = Join-Path $outputFull "$baseName.json"
$source = [IO.File]::ReadAllText($sourceFull)

$samplePattern = '(?m)^    r0\.x = t6\.SampleLevel\(s6_s, v0\.xy, 0\)\.x;$'
if ([regex]::Matches($source, $samplePattern).Count -ne 1) { throw 'Expected exactly one verified screen-AO t6 sample anchor.' }
$screenExpression = $spec.screenExpression
$sampleReplacement = @"
    r0.x = t6.SampleLevel(s6_s, v0.xy, 0).x;
    // Rebirth native-ScreenAO fallback strength, scoped to Remake's
    // reflection/indirect consumer. The donor's model condition is always
    // true, so all models receive the power operation before eye protection.
    r0.x = saturate($screenExpression);
    if ((int)r1.x == 9) {
      r0.x = lerp(r0.x, 1.0, 0.5);
    }
"@.TrimEnd()
$generated = [regex]::Replace($source, $samplePattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $sampleReplacement }, 1)

$materialPattern = @'
(?ms)^    r1\.y = r3\.w \* r0\.x;\r?\n    r1\.w = min\(r3\.w, r0\.x\);\r?\n    r2\.w = r3\.w \* r0\.x \+ 1;\r?\n    r2\.w = r2\.w \+ -r1\.w;\r?\n    r2\.w = r2\.w \* r2\.w;\r?\n    r0\.x = -r3\.w \* r0\.x \+ r1\.w;\r?\n    r0\.x = r2\.w \* r0\.x \+ r1\.y;$
'@.Trim()
if ([regex]::Matches($generated, $materialPattern).Count -ne 1) { throw 'Expected exactly one verified screen-AO/material-AO combination anchor.' }
$materialMatch = [regex]::Match($generated, $materialPattern).Value
$materialReplacement = @"
$materialMatch
    // Preintegrated skin (3), hair (7), and eye (9) character protection/
    // shaping at the donor's ambient/reflection ownership boundary.
    if (r8.z != 0 || r8.w != 0 || (int)r1.x == 9) {
      r0.x = pow(saturate(r0.x), $characterPowerLiteral);
    }
"@.TrimEnd()
$generated = [regex]::Replace($generated, $materialPattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $materialReplacement }, 1)

foreach ($required in @('r11.w = 1 + -r11.w;','r2.xyz = r2.xyz * r11.www;','r2.xyz = r2.xyz * r0.www + r11.xyz;','r3.xyz = r3.xyz * r0.xxx;')) {
    if ([regex]::Matches($generated, [regex]::Escape($required)).Count -ne 1) { throw "Generated source does not preserve the reflection/AO contract: $required" }
}
[IO.File]::WriteAllText($hlslPath, $generated, [Text.UTF8Encoding]::new($false))

$compilerOutput = & $FxcPath /nologo /T ps_5_0 /E main /Ges /WX /O3 /Fo $objectPath /Fc $assemblyPath $hlslPath 2>&1
if ($LASTEXITCODE -ne 0) { throw "FXC failed for $baseName`n$($compilerOutput -join [Environment]::NewLine)" }

$assembly = [IO.File]::ReadAllText($assemblyPath)
foreach ($contract in @('(?m)^//\s+t6\s+texture\s+float4\s+2d\s+t6\s+1\s*$','(?m)^//\s+t10\s+texture\s+float4\s+cubearray\s+t10\s+1\s*$','(?m)^//\s+t11\s+texture\s+float4\s+2d\s+t11\s+1\s*$','(?m)^//\s+SV_Target\s+0\s+xyzw')) {
    if ($assembly -notmatch $contract) { throw "Compiled candidate is missing expected contract: $contract" }
}
foreach ($sampleContract in @('(?m)^\s*sample_l_indexable\(texture2d\).*t6\.','(?m)^\s*sample_l_indexable\(texturecubearray\).*t10\.','(?m)^\s*sample_l_indexable\(texture2d\).*t11\.')) {
    if ($assembly -notmatch $sampleContract) { throw "Compiled candidate is missing an expected AO/reflection/SSR sample: $sampleContract" }
}

$relative = { param([string]$Path) $Path.Substring($repoRoot.Length + 1).Replace('\','/') }
$manifest = [ordered]@{
    schemaVersion = 1
    adapter = 'FF7RemakeIntergrade'
    shaderHash = 'e2aa1c8cb39e0a55'
    stage = 'ps'
    exactSourceSha256 = $expectedSourceSha256
    matchPolicy = 'exact shader hash, exact decompiled-source SHA-256, unique t6 AO anchor, unique material-AO anchor; fail closed otherwise'
    effect = 'rebirth-native-screen-ao-fallback-consumer-adapter'
    classification = 'ambient-reflection AO shaping; not AO production, contact shadows, material writing, GTVB, or SSGI bounce'
    preset = $Preset
    intendedFutureKey = if ($Preset -eq 'Balanced') { 'F2' } else { 'F3' }
    donorFamily = 'ReflectionEnvironment'
    donorFidelity = $spec.donorFidelity
    formulas = [ordered]@{ screenAOPower=[double]$spec.screenPower; eyeLiftTowardNeutral=0.5; characterCombinedAOPower=[double]$spec.characterPower; characterModels=@('preintegrated skin 3','hair 7','eye 9') }
    scope = 'reflection and indirect-light consumer only'
    preserves = @('a77 temporal AO production/history','screen-AO compositor','five tiled direct-light AO consumers','native extra occlusion','native specular occlusion and GTAO multi-bounce','SSR radiance and hit alpha','capsule occlusion','contact shadows')
    explicitlyNotImplemented = @('GTVB ray marching','SSGI bounce light','checkerboard reconstruction','new SRV/UAV bindings','new dispatch or temporal/filter pass')
    rebirthArchiveEvidence = [ordered]@{
        PerformanceSha256='21C8715F311B1B25CE8C19489F97729F7CBD0846B1A18AF5C976349C74EDE4BA'
        MaximumQualitySha256='CED1790992265E203E0DB418203881D5570A58C5AF0663E5F50C05A7996CD119'
        PerformanceReflectionSourceSha256='CAC5ED975F537238011B6913126299EEE1F415B4DC4DEE254CCABC597C841BDE'
        MaximumQualityReflectionSourceSha256='CEBA077018F2ACBD48A86AEF82CD603B8F219C71E501947AE3E88129A715164B'
        evidenceMap='artifacts/analysis/rebirth-v2.2.1-ao-architecture.json'
    }
    source = & $relative $hlslPath
    sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hlslPath).Hash
    object = & $relative $objectPath
    objectSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectPath).Hash
    assembly = & $relative $assemblyPath
    assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assemblyPath).Hash
    reservedAOControls = [ordered]@{ F1='Original/native AO'; F2='Balanced'; F3='Strong' }
    hotkeysEmitted = $false
    installStatus = 'offline-not-installed'
    runtimeEligible = $false
    nextGate = 'reviewed live Original/Balanced/Strong fixed-camera and motion validation; no installation performed by this generator'
}
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{ Preset=$Preset; Source=$hlslPath; Object=$objectPath; Assembly=$assemblyPath; Manifest=$manifestPath; SourceSha256=$manifest.sourceSha256; ObjectSha256=$manifest.objectSha256 }
