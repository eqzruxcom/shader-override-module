[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Balanced','Strong')]
    [string]$Preset,
    [string]$SourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\captured-shaders\a77b589dce5822d6-ps\a77b589dce5822d6-ps_decompiled.txt'),
    [string]$KernelPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Effects\AO\RemakeTemporalAOPower.hlsl'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-temporal-power-candidates'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$expectedSourceSha256 = 'A615A3D790B68D30EEFA2C1EBF7B01AA609B413BA3E64F152B11F1E09BF153DC'

function Resolve-WorkspacePath([string]$Path, [switch]$AllowMissing) {
    $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $repoRoot $Path)) }
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Path must remain inside the project workspace: $full" }
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "File does not exist: $full" }
    $full
}

$sourceFull = Resolve-WorkspacePath $SourcePath
$kernelFull = Resolve-WorkspacePath $KernelPath
$outputFull = Resolve-WorkspacePath $OutputDirectory -AllowMissing
if (-not (Test-Path -LiteralPath $FxcPath -PathType Leaf)) { throw "FXC was not found: $FxcPath" }

$sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceFull).Hash
if ($sourceSha256 -ne $expectedSourceSha256) {
    throw "Refusing stale or changed SSAO source. Expected $expectedSourceSha256, got $sourceSha256."
}

$presetSpec = switch ($Preset) {
    'Balanced' { [ordered]@{ power = 1.25; suffix = '125' } }
    'Strong'   { [ordered]@{ power = 1.50; suffix = '150' } }
}
$powerLiteral = ([double]$presetSpec.power).ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)
$baseName = "RemakeTemporalAOPower$($presetSpec.suffix)_ps"

New-Item -ItemType Directory -Path $outputFull -Force | Out-Null
$hlslPath = Join-Path $outputFull "$baseName.hlsl"
$objectPath = Join-Path $outputFull "$baseName.cso"
$assemblyPath = Join-Path $outputFull "$baseName.asm"
$manifestPath = Join-Path $outputFull "$baseName.json"

$source = [IO.File]::ReadAllText($sourceFull)
$kernel = [IO.File]::ReadAllText($kernelFull)
$mainPattern = '(?m)^void main\('
$currentPattern = '(?m)^  r2\.w = max\(0, r2\.x\);$'
if ([regex]::Matches($source, $mainPattern).Count -ne 1) { throw 'Expected exactly one main function insertion point.' }
if ([regex]::Matches($source, $currentPattern).Count -ne 1) { throw 'Expected exactly one current-frame AO scalar assignment.' }
if ([regex]::Matches($source, '(?m)^    r0\.xyw = t3\.SampleLevel').Count -ne 1) { throw 'Expected exactly one temporal-history sample.' }
if ([regex]::Matches($source, '(?m)^  o0\.xyzw = r2\.wxyz;$').Count -ne 1) { throw 'Expected the native packed AO output assignment.' }

$generated = [regex]::Replace($source, $mainPattern, ($kernel.TrimEnd() + "`r`n`r`nvoid main("), 1)
$replacement = "  r2.w = max(0, r2.x);`r`n  r2.w = RemakeTemporalAOApplyCurrentPower(r2.w, $powerLiteral);"
$generated = [regex]::Replace($generated, $currentPattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement }, 1)

$powerIndex = $generated.IndexOf('RemakeTemporalAOApplyCurrentPower(r2.w', [StringComparison]::Ordinal)
$historyIndex = $generated.IndexOf('r0.xyw = t3.SampleLevel', [StringComparison]::Ordinal)
if ($powerIndex -lt 0 -or $historyIndex -lt 0 -or $powerIndex -ge $historyIndex) {
    throw 'AO power transform must occur before temporal-history selection.'
}

[IO.File]::WriteAllText($hlslPath, $generated, [Text.UTF8Encoding]::new($false))
$compilerOutput = & $FxcPath /nologo /T ps_5_0 /E main /Ges /WX /O3 /Fo $objectPath /Fc $assemblyPath $hlslPath 2>&1
if ($LASTEXITCODE -ne 0) { throw "FXC failed for $baseName`n$($compilerOutput -join [Environment]::NewLine)" }

$assembly = [IO.File]::ReadAllText($assemblyPath)
foreach ($binding in @('t0','t1','t2','t3','t4','t5','cb0','cb1')) {
    if ($assembly -notmatch "(?m)^//\s+$binding\s+") { throw "Compiled candidate is missing expected binding $binding." }
}
if ($assembly -notmatch '(?m)^//\s+s0_s\s+sampler\s+' -or $assembly -notmatch '(?m)^dcl_sampler\s+s0,\s*mode_default\s*$') { throw 'Compiled candidate is missing s0.' }
if ($assembly -notmatch '(?m)^//\s+SV_Target\s+0\s+xyzw') { throw 'Compiled candidate is missing SV_Target0.xyzw.' }

$relative = { param([string]$Path) $Path.Substring($repoRoot.Length + 1).Replace('\','/') }
$manifest = [ordered]@{
    schemaVersion = 1
    adapter = 'FF7RemakeIntergrade'
    shaderHash = 'a77b589dce5822d6'
    stage = 'ps'
    effect = 'temporal-ssao-current-visibility-power'
    classification = 'native-ssao-contrast-strength-not-ssgi'
    preset = $Preset
    power = [double]$presetSpec.power
    insertionPoint = 'current visibility r2.w after native max(.,0), before t3 temporal-history sample and selection'
    formula = 'currentVisibility = saturate(pow(saturate(currentVisibility), power))'
    nativePackedOutput = 'o0.xyzw = r2.wxyz'
    temporalContract = [ordered]@{
        currentVisibilityPoweredOnce = $true
        historySampleRepowered = $false
        packedMetadataPreserved = @('z','w')
    }
    scope = [ordered]@{
        modifies = @('a77b589dce5822d6 temporal SSAO current-frame visibility')
        preserves = @('native temporal selection','native spatial filters','native final AO compositor','capsule occlusion','material AO','contact shadows','lighting shaders')
    }
    sourceEvidenceSha256 = $sourceSha256
    kernel = & $relative $kernelFull
    kernelSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $kernelFull).Hash
    source = & $relative $hlslPath
    sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hlslPath).Hash
    object = & $relative $objectPath
    objectSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectPath).Hash
    assembly = & $relative $assemblyPath
    assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assemblyPath).Hash
    runtimeEligible = $false
    installStatus = 'offline-not-installed'
    hotkeysEmitted = $false
    reservedFutureControls = @('F1','F2','F3')
    futureControlPlan = [ordered]@{
        F1 = 'Original/native AO'
        F2 = 'Balanced power 1.25'
        F3 = 'Strong power 1.50'
    }
    futureControlOwnership = [ordered]@{ F1='AO Original'; F2='AO Balanced'; F3='AO Strong' }
    rebirthEvidence = [ordered]@{
        performanceArchiveSha256 = '21C8715F311B1B25CE8C19489F97729F7CBD0846B1A18AF5C976349C74EDE4BA'
        maximumQualityArchiveSha256 = 'CED1790992265E203E0DB418203881D5570A58C5AF0663E5F50C05A7996CD119'
        portableConcept = 'SSAO_POWER visibility-domain shaping from the native ScreenAO branch'
        explicitlyNotImplemented = @('GTVB ray marching','SSGI bounce','ReflectionEnvironment material/specular composite')
    }
    nextGate = 'reviewed offline integration followed by live F1/F2/F3 Original/Balanced/Strong comparison with motion, camera cut, hair/skin, thin geometry, indoor and outdoor distances'
}
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Preset = $Preset
    Power = [double]$presetSpec.power
    Source = $hlslPath
    Object = $objectPath
    Assembly = $assemblyPath
    Manifest = $manifestPath
    SourceSha256 = $manifest.sourceSha256
    ObjectSha256 = $manifest.objectSha256
}
