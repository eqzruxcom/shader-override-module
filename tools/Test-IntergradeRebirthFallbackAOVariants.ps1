[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-rebirth-fallback-consumer-variants-test'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$generator = Join-Path $repoRoot 'tools\New-IntergradeRebirthFallbackAOVariant.ps1'
$baselineObject = Join-Path $repoRoot 'artifacts\captured-shaders\e2aa1c8cb39e0a55-ps\e2aa1c8cb39e0a55-ps_recompiled.cso'
$records = @()

foreach ($preset in @('Balanced','Strong')) {
    $first = & $generator -Preset $preset -OutputDirectory (Join-Path $OutputDirectory "first\$preset")
    $second = & $generator -Preset $preset -OutputDirectory (Join-Path $OutputDirectory "second\$preset")
    if ($first.SourceSha256 -ne $second.SourceSha256 -or $first.ObjectSha256 -ne $second.ObjectSha256) { throw "$preset generation is not deterministic." }
    $manifest = Get-Content -Raw -LiteralPath $first.Manifest | ConvertFrom-Json
    if ($manifest.shaderHash -ne 'e2aa1c8cb39e0a55' -or $manifest.exactSourceSha256 -ne 'E82E8D7A5EF91FD954B50A95CBC250B08F43B28C91450B9EC2106A82478A6716') { throw "$preset exact family contract changed." }
    if ($manifest.runtimeEligible -ne $false -or $manifest.installStatus -ne 'offline-not-installed' -or $manifest.hotkeysEmitted -ne $false) { throw "$preset escaped the offline gate." }
    if ($manifest.reservedAOControls.F1 -ne 'Original/native AO' -or $manifest.reservedAOControls.F2 -ne 'Balanced' -or $manifest.reservedAOControls.F3 -ne 'Strong') { throw "$preset AO control ownership changed." }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $baselineObject).Hash -eq $first.ObjectSha256) { throw "$preset unexpectedly equals the neutral baseline object." }
    $source = [IO.File]::ReadAllText($first.Source)
    foreach ($pattern in @('r0\.x = t6\.SampleLevel\(s6_s, v0\.xy, 0\)\.x;','r0\.x = lerp\(r0\.x, 1\.0, 0\.5\);','r11\.w = 1 \+ -r11\.w;','r2\.xyz = r2\.xyz \* r0\.www \+ r11\.xyz;')) {
        if ([regex]::Matches($source, $pattern).Count -ne 1) { throw "$preset source contract missing or ambiguous: $pattern" }
    }
    if ($source -match '(?i)(?<![A-Z0-9_])(?:VK_)?F[123](?![A-Z0-9_])|(?i)\[Key') { throw "$preset shader source contains a key binding." }
    $records += [pscustomobject]@{ preset=$preset; sourceSha256=$first.SourceSha256; objectSha256=$first.ObjectSha256; manifest=$manifest }
}

$balanced = @($records | Where-Object preset -eq 'Balanced')[0]
$strong = @($records | Where-Object preset -eq 'Strong')[0]
if ($balanced.objectSha256 -eq $strong.objectSha256 -or $balanced.sourceSha256 -eq $strong.sourceSha256) { throw 'Balanced and Strong variants are not distinct.' }
if ($balanced.manifest.formulas.screenAOPower -ne 1.5 -or $balanced.manifest.formulas.characterCombinedAOPower -ne 1.375) { throw 'Balanced strength changed.' }
if ($strong.manifest.formulas.screenAOPower -ne 2.0 -or $strong.manifest.formulas.characterCombinedAOPower -ne 1.75) { throw 'Strong donor-faithful strength changed.' }

$negativeSource = Join-Path $OutputDirectory 'negative-source.hlsl'
[void](New-Item -ItemType Directory -Force -Path $OutputDirectory)
$nativeSource = Join-Path $repoRoot 'artifacts\captured-shaders\e2aa1c8cb39e0a55-ps\e2aa1c8cb39e0a55-ps_decompiled.txt'
$mutated = [IO.File]::ReadAllText($nativeSource).Replace('r0.x = t6.SampleLevel(s6_s, v0.xy, 0).x;', 'r0.x = t6.SampleLevel(s6_s, v0.xy, 0).y;')
[IO.File]::WriteAllText($negativeSource, $mutated, [Text.UTF8Encoding]::new($false))
$failedClosed = $false
try { & $generator -Preset Balanced -SourcePath $negativeSource -OutputDirectory (Join-Path $OutputDirectory 'negative') | Out-Null } catch { $failedClosed = $_.Exception.Message -match 'Refusing changed or unmatched e2aa source' }
if (-not $failedClosed) { throw 'Variant generator did not fail closed on a changed source.' }

$report = [ordered]@{
    schemaVersion=1; result='pass'; deterministic=$true; exactSourceMatch=$true; negativeSourceTest='pass';
    runtimeEligible=$false; installStatus='offline-not-installed'; hotkeysEmitted=$false;
    controls=[ordered]@{ F1='Original/native AO'; F2='Balanced'; F3='Strong' };
    variants=@($records | ForEach-Object { [ordered]@{ preset=$_.preset; sourceSha256=$_.sourceSha256; objectSha256=$_.objectSha256 } })
}
$reportPath = Join-Path $OutputDirectory 'report.json'
[IO.File]::WriteAllText($reportPath, (($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Host "PASS: deterministic offline Rebirth fallback AO variants; report $reportPath"
