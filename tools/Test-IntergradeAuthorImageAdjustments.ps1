[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$output=Join-Path $repo ('artifacts\generated-runtime\AuthorImageAdjustmentsTest-'+[Guid]::NewGuid().ToString('N'))
$generator=Join-Path $PSScriptRoot 'New-IntergradeAuthorImageAdjustments.ps1'
$result=& $generator -OutputDirectory $output
$m=Get-Content -Raw -LiteralPath $result.Manifest | ConvertFrom-Json
if ($m.adapterId -ne 'FF7RemakeIntergradeAuthorImageAdjustments' -or $m.runtimeEligible -or $m.trueNativeShaderToggle -or $m.nativeToneReplacement -or -not $m.originalTonemappingRetained) { throw 'Port eligibility or scope is overstated.' }
if ($m.kernelInstructions -ne 5 -or $m.originalTokensByteIdentical -ne 134 -or $m.settings.brightnessEV -ne -0.45 -or $m.settings.gamma -ne 1.15) { throw 'Author algorithm or preservation changed.' }
if ($m.candidateSha256 -ne '01CB3652072A4F4A942CAB9D3BD5C5DC0DB3012F67CE4D8614E833407FDC364B') { throw 'Compiled author port changed.' }
$asm=Get-Content -Raw -LiteralPath (Join-Path $output 'ShaderFixes\41f1bf8b79d01319-ps.txt')
if ($asm -notmatch 'Copyright \(c\) 2026 David Matos' -or $asm -notmatch 'Permission is hereby granted') { throw 'Author license is missing from payload.' }
$inputSample=$asm.IndexOf('sample_l_indexable(texture2d)(float,float,float,float) r2.xyz, r1.zwzz, t1.xyzw')
$adjustment=$asm.IndexOf('mul r13.xyz, r2.xyzx, l(0.732042849')
$pq=$asm.IndexOf('mul r3.xyz, r2.xyzx, l(0.010000')
$ui=$asm.IndexOf('mul r0.w, r1.w, cb0[25].y')
if ($inputSample -lt 0 -or $adjustment -le $inputSample -or $pq -le $adjustment -or $ui -le $pq) { throw 'Author operation order is wrong.' }
if ($asm -match 'mul r2.xyz, r2.xyzx, l\(0.500000') { throw 'Old brightness diagnostic leaked into the port.' }
foreach ($f in $m.files) {
    if ((Get-FileHash -LiteralPath (Join-Path $output $f.relativePath)).Hash -ne $f.sha256) { throw 'Payload drift.' }
}
# Numerical check of the compiler's specialized five-op kernel against the
# author's source formula. This is CPU math evidence, not a GPU/pixel test.
$previous=-1.0
foreach ($x in @(-10.0,0.0)+@(0..256 | ForEach-Object { [Math]::Pow(10.0,-8.0+13.0*$_/256.0) })) {
    $reference=[Math]::Pow([Math]::Max($x*[Math]::Pow(2.0,-0.45),0.0),1.0/1.15)
    $compiled=[Math]::Pow([Math]::Max($x*[double][single]0.732042849,0.0),[double][single]0.869565248)
    if ([double]::IsNaN($compiled) -or [double]::IsInfinity($compiled) -or [Math]::Abs($compiled-$reference) -gt [Math]::Max(1e-12,[Math]::Abs($reference)*1e-6)) { throw 'Compiled exposure/gamma formula differs from source.' }
    if ($compiled -lt $previous) { throw 'Author adjustment is not monotonic.' }
    $previous=$compiled
}
$rejected=$false
try { & $generator -OutputDirectory $output | Out-Null } catch { $rejected=$_.Exception.Message -match 'Output exists' }
if (-not $rejected) { throw 'Existing artifacts overwritten.' }
Write-Output 'Author AdjustImage extraction, SM5 specialization, original-token preservation, placement, license, and numeric checks passed.'
Write-Output $output
