[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$RuntimeRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64',
    [double]$EmitterRadius = 5.0,
    [switch]$Install
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$runtime = (Resolve-Path -LiteralPath $RuntimeRoot).Path.TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$allowed = [IO.Path]::GetFullPath((Join-Path $repo 'artifacts\generated-runtime')).TrimEnd('\')
if (-not $output.StartsWith($allowed+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)) {
    throw 'Use a fresh artifacts/generated-runtime child.'
}
if ($EmitterRadius -le 0 -or $EmitterRadius -gt 100) { throw 'EmitterRadius must be positive and bounded.' }

$fork = Join-Path $repo 'artifacts\contact-softness-combined-development-20260901-v1'
$candidateRoot = Join-Path $fork 'artifacts\combined-softness-candidate-v1'
$baselineRoot = Join-Path $fork 'artifacts\combined-baseline-proof-v1'
$profileRoot = Join-Path $fork 'artifacts\combined-softness-profile-v1'
$candidatePath = Join-Path $candidateRoot 'candidate.json'
$baselinePath = Join-Path $baselineRoot 'candidate.json'
$profilePath = Join-Path $profileRoot 'manifest.json'
$assembler = Join-Path $repo 'artifacts\shader-assembler-build\bin\cmd_Decompiler.exe'
$liveShader = Join-Path $runtime 'ShaderFixes\62b33a2d1e505241-cs.txt'
$liveIni = Join-Path $runtime 'Mods\ContactShadows.ini'
foreach ($path in @($candidatePath,$baselinePath,$profilePath,$assembler,$liveShader,$liveIni)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required file: $path" }
}

$utf8 = [Text.UTF8Encoding]::new($false)
function Read-Json([string]$path) { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
function Write-Json([string]$path,$value) { [IO.File]::WriteAllText($path,(($value|ConvertTo-Json -Depth 12)+"`n"),$utf8) }
function Assert-Hash([string]$path,[string]$expected) {
    if ($expected -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileHash -LiteralPath $path).Hash -ne $expected) { throw "Fingerprint mismatch: $path" }
}
function Instructions([string[]]$lines) {
    (($lines | ForEach-Object {$_.Trim()} | Where-Object {$_ -and -not $_.StartsWith('//')}) -join "`n")
}
function Relative-LivePath([string]$path) { $path.Substring($runtime.Length+1).Replace('\','/') }

$candidate = Read-Json $candidatePath
$baseline = Read-Json $baselinePath
$profile = Read-Json $profilePath
$variant = @($candidate.variants | Where-Object shaderHash -eq '62b33a2d1e505241')
$baselineVariant = @($baseline.variants | Where-Object shaderHash -eq '62b33a2d1e505241')
if ($candidate.implementation -ne 'Rebirth' -or $candidate.reconstruction -ne 'SharedQuad' -or
    -not $candidate.softnessExperiment -or $candidate.sampleCount -ne 16 -or $variant.Count -ne 1) {
    throw 'Wrong combined softness candidate.'
}
if ($baseline.implementation -ne 'Rebirth' -or $baseline.reconstruction -ne 'SharedQuad' -or
    $baseline.softnessExperiment -or $baselineVariant.Count -ne 1) { throw 'Wrong combined baseline proof.' }
if ($baselineVariant[0].candidateSha256 -ne 'B7AA425C5AFB42171E3C3F7E4F1CBF4921EED472A126064367EA975331D3A2DF') {
    throw 'Combined baseline is not the accepted Frustum Fix binary.'
}
if ($variant[0].candidateSha256 -ne 'D7279079727272E07AC93F4367CB48B58EA0B4E1D691F98DAC117207188C4879' -or
    -not $variant[0].roundTripByteIdentical -or -not $variant[0].maskedContributionIdentityLanes -or
    -not $variant[0].sharedGroup -or $variant[0].sharedMemoryBytes -ne 1024) {
    throw 'Combined softness candidate invariants changed.'
}
if ($profile.status -ne 'passed-analytic-soft-edge-profile-only' -or $profile.numericChecks -ne 2048 -or
    $profile.profiles[0].softTransitionPoints -ne 22 -or $profile.profiles[1].softTransitionPoints -ne 51) {
    throw 'Numerical softness profile is absent or changed.'
}
foreach ($source in $candidate.sources) { Assert-Hash (Join-Path $fork $source.path) $source.sha256 }
Assert-Hash (Join-Path $candidateRoot $variant[0].binary) $variant[0].candidateSha256

$liveLines = @(Get-Content -LiteralPath $liveShader)
$profileIndex = [array]::IndexOf($liveLines,'cs_5_0')
if ($profileIndex -lt 1) { throw 'Live 62b signature header is unavailable.' }
$header = @($liveLines[0..($profileIndex-1)])
$liveBody = @($liveLines[$profileIndex..($liveLines.Count-1)])
if (($header -join "`n") -notmatch '(?m)^//Frustum Fix\s*$') { throw 'Accepted Frustum Fix header marker is missing.' }
$baselineBody = @(Get-Content -LiteralPath (Join-Path $baselineRoot $baselineVariant[0].assembly))
if ((Instructions $liveBody) -cne (Instructions $baselineBody)) { throw 'Live 62b is not the accepted combined baseline.' }

$liveIniText = Get-Content -LiteralPath $liveIni -Raw
if ($liveIniText -match '(?i)VK_PRIOR|contact_softness|(?m)^x28\s*=|(?m)^y28\s*=') { throw 'Page Up or row 28 is not free.' }
if (([regex]::Matches($liveIniText,'(?m)^x31\s*=\s*\$ue4fx_master_injected_v1\s*$')).Count -ne 5 -or
    $liveIniText -notmatch '(?m)^global \$ue4fx_contact_edge_width_v2\s*=\s*0\.06\s*$' -or
    $liveIniText -notmatch '(?m)^global \$ue4fx_contact_edge_cutoff_v2\s*=\s*0\s*$') {
    throw 'Live Page Down master or accepted Frustum Fix controls changed.'
}

$otherHashes = @{}
foreach ($hash in @('08bb8764f1840179','0e97888f9a8767da','5a9fbefe0ab6f815','c30cdc8365df9840')) {
    $path = Join-Path $runtime "ShaderFixes\$hash-cs.txt"
    $otherHashes[$hash] = (Get-FileHash -LiteralPath $path).Hash
}
if (-not $PSCmdlet.ShouldProcess($output,'Stage isolated 62b Page Up softness experiment')) { return }
foreach ($part in @('ShaderFixes','Mods','validation','preinstall-backup\ShaderFixes','preinstall-backup\Mods')) {
    [IO.Directory]::CreateDirectory((Join-Path $output $part)) | Out-Null
}

$candidateBody = @(Get-Content -LiteralPath (Join-Path $candidateRoot $variant[0].assembly))
$stagedShader = Join-Path $output 'ShaderFixes\62b33a2d1e505241-cs.txt'
$stagedShaderLines = @($header + '// Page Up: isolated 62b area-shadow softness test' + $candidateBody)
[IO.File]::WriteAllText($stagedShader,(($stagedShaderLines -join "`n")+"`n"),$utf8)

$roundTripAsm = Join-Path $output 'validation\62b-roundtrip.asm'
Copy-Item -LiteralPath $stagedShader -Destination $roundTripAsm
$originalBinary = Join-Path $candidateRoot 'validation\62b33a2d1e505241-original.bin'
$messages = & $assembler -a --copy-reflection $originalBinary $roundTripAsm 2>&1
if ($LASTEXITCODE -ne 0) { throw "Staged 62b assembly failed: $($messages|Out-String)" }
$roundTripBinary = [IO.Path]::ChangeExtension($roundTripAsm,'.shdr')
Assert-Hash $roundTripBinary $variant[0].candidateSha256
Write-Json (Join-Path $output 'validation\62b-roundtrip.json') ([ordered]@{
    candidateSha256=$variant[0].candidateSha256
    roundTripSha256=(Get-FileHash -LiteralPath $roundTripBinary).Hash
    stagedShaderSha256=(Get-FileHash -LiteralPath $stagedShader).Hash
})

$radius = $EmitterRadius.ToString('0.###',[Globalization.CultureInfo]::InvariantCulture)
$radius2x = ($EmitterRadius * 2).ToString('0.###',[Globalization.CultureInfo]::InvariantCulture)
$radius4x = ($EmitterRadius * 4).ToString('0.###',[Globalization.CultureInfo]::InvariantCulture)
$radius8x = ($EmitterRadius * 8).ToString('0.###',[Globalization.CultureInfo]::InvariantCulture)
$radius16x = ($EmitterRadius * 16).ToString('0.###',[Globalization.CultureInfo]::InvariantCulture)
$ini = $liveIniText
$ini = [regex]::Replace($ini,'(?m)^(global \$ue4fx_master_injected_v1\s*=\s*1\s*)$',"`$1`r`nglobal `$ue4fx_contact_softness_test_v1 = 0`r`nglobal `$ue4fx_contact_softness_radius_v1 = $radius",1)
$key = "[KeyUE4FXContactSoftnessPageUp]`r`nkey = no_modifiers VK_PRIOR`r`ntype = cycle`r`nsmart = true`r`n; Exact states: default shader -> 2x -> 4x -> 8x -> 16x -> default shader.`r`n`$ue4fx_contact_softness_test_v1 = 0, 1, 1, 1, 1`r`n`$ue4fx_contact_softness_radius_v1 = $radius, $radius2x, $radius4x, $radius8x, $radius16x`r`n`r`n"
$ini = [regex]::Replace($ini,'(?m)^\[KeyUE4FXMasterPageDown\]',$key+'[KeyUE4FXMasterPageDown]',1)
$ini = [regex]::Replace($ini,'(?ms)^(\[ShaderOverrideUE4FXContact62b33a2d1e505241\]\s*\r?\nhash\s*=\s*62b33a2d1e505241\s*\r?\n)',"`$1x28 = `$ue4fx_contact_softness_test_v1`r`ny28 = `$ue4fx_contact_softness_radius_v1`r`n",1)
$ini = $ini.Replace('; Page Down is the sole retained-code master. Page Up is free for the next experiment.','; Page Down is the master. Page Up cycles only the isolated 62b softness experiment.')
$stagedIni = Join-Path $output 'Mods\ContactShadows.ini'
[IO.File]::WriteAllText($stagedIni,($ini.TrimEnd()+"`r`n"),$utf8)

$coverage = & (Join-Path $PSScriptRoot 'Test-IntergradeSoftnessExperimentCoverage.ps1') -PackageDirectory $output
$rollback = $null
if ($Install) {
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
    $rollback = Join-Path $repo "artifacts\live-rollbacks\contact-softness-62b-$stamp"
    [IO.Directory]::CreateDirectory((Join-Path $rollback 'ShaderFixes')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $rollback 'Mods')) | Out-Null
    Copy-Item -LiteralPath $liveShader -Destination (Join-Path $rollback 'ShaderFixes\62b33a2d1e505241-cs.txt')
    Copy-Item -LiteralPath $liveIni -Destination (Join-Path $rollback 'Mods\ContactShadows.ini')
    Copy-Item -LiteralPath $liveShader -Destination (Join-Path $output 'preinstall-backup\ShaderFixes\62b33a2d1e505241-cs.txt')
    Copy-Item -LiteralPath $liveIni -Destination (Join-Path $output 'preinstall-backup\Mods\ContactShadows.ini')
    Copy-Item -LiteralPath $stagedShader -Destination $liveShader -Force
    Copy-Item -LiteralPath $stagedIni -Destination $liveIni -Force
    foreach ($hash in $otherHashes.Keys) {
        if ((Get-FileHash -LiteralPath (Join-Path $runtime "ShaderFixes\$hash-cs.txt")).Hash -ne $otherHashes[$hash]) { throw "Unrelated shader changed: $hash" }
    }
    Assert-Hash $liveShader (Get-FileHash -LiteralPath $stagedShader).Hash
    Assert-Hash $liveIni (Get-FileHash -LiteralPath $stagedIni).Hash
}

$manifest = [ordered]@{
    schemaVersion=1;generatedAtUtc=[DateTime]::UtcNow.ToString('o')
    result=$(if($Install){'installed'}else{'staged'})
    mode='isolated-62b-contact-softness-page-up-v1'
    pageDown='master on all five retained shaders'
    pageUp='62b softness cycle: default, 2x, 4x, 8x, 16x; default state is native baseline'
    emitterRadius=$EmitterRadius
    frustumFix='accepted left 0-to-6-percent per-hit fade preserved'
    baselineSha256=$baselineVariant[0].candidateSha256
    candidateSha256=$variant[0].candidateSha256
    numericChecks=$profile.numericChecks
    stagedShaderSha256=(Get-FileHash -LiteralPath $stagedShader).Hash
    stagedIniSha256=(Get-FileHash -LiteralPath $stagedIni).Hash
    otherLiveShaderHashes=$otherHashes
    coverage=$coverage
    installed=[bool]$Install;rollbackDirectory=$rollback;reloadRequired=[bool]$Install
    limitations=@('Eight donor rays on traced 62b receiver lanes while Page Up is ON','Virtual emitter radius is not a verified native light-size binding','Offline profiles prove widening, not FF7 motion quality or performance','Page Up OFF retains the exact accepted hard Frustum Fix instructions but the compiled branch still exists')
}
$manifestPath = Join-Path $output 'runtime-manifest.json'
Write-Json $manifestPath $manifest
[pscustomobject]@{Result=$manifest.result;PageDownShaders=5;PageUpShaders=1;PageUpStates='default,2x,4x,8x,16x';EmitterRadius=$EmitterRadius;Rollback=$rollback;Manifest=$manifestPath;ManifestSha256=(Get-FileHash -LiteralPath $manifestPath).Hash}
