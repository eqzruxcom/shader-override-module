[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$output=Join-Path $repo ('artifacts\generated-runtime\FinalCompositeIsolationTest-'+[Guid]::NewGuid().ToString('N'))
$generator=Join-Path $PSScriptRoot 'New-IntergradeFinalCompositeIsolation.ps1'
$result=& $generator -OutputDirectory $output
$m=Get-Content -Raw -LiteralPath $result.Manifest | ConvertFrom-Json
if ($m.trueNativeShaderToggle -or $m.runtimeEligible -or -not $m.diagnosticOnly -or $m.replacesNativeTonemapper) { throw 'Diagnostic overclaims eligibility or native baseline.' }
if ($m.originalTokensByteIdentical -ne 134 -or $m.originalMathChanges -ne 0 -or $m.addedInstructionOrDeclarationCount -ne 6 -or -not $m.neutralRoundTripBinaryIdentical) { throw 'Original code invariants failed.' }
if ($m.control.default -ne 0 -or ($m.control.values -join ',') -ne '0,1' -or $m.control.iniParam -ne 'x30') { throw 'Wrong default or control.' }
if (@($m.files).Count -ne 2) { throw 'Unexpected payload files.' }
foreach ($f in $m.files) {
    $path=Join-Path $output $f.relativePath
    if ((Get-FileHash -LiteralPath $path).Hash -ne $f.sha256 -or (Get-Item -LiteralPath $path).Length -ne $f.size) { throw 'Payload manifest mismatch.' }
}
$ini=Get-Content -Raw -LiteralPath (Join-Path $output 'Mods\UE4EffectsGenerated.ini')
if ($ini -match '(?im)^\s*(?:hunting|show_original|ps|handling|draw)\s*=' -or $ini -match 'af6cd28a0108a18a|ef7fe8d9c4e9ad15|a77b589dce5822d6|e2aa1c8cb39e0a55') { throw 'Unrelated control or replacement leaked.' }
$asm=Get-Content -Raw -LiteralPath (Join-Path $output 'ShaderFixes\41f1bf8b79d01319-ps.txt')
if ($asm -notmatch 'eq r12.x, r12.x, l\(1.000000\)' -or $asm -notmatch 'ld_indexable\(texture1d\).*r12.x, l\(30, 0, 0, 0\), t120.xyzw') { throw 'Toggle is not exact-one gated.' }
$rejected=$false
try { & $generator -OutputDirectory $output | Out-Null } catch { $rejected=$_.Exception.Message -match 'output exists' }
if (-not $rejected) { throw 'Existing artifacts were not protected.' }
$rejected=$false
try { & $generator -OutputDirectory (Join-Path $repo 'outside-generated-runtime') | Out-Null } catch { $rejected=$_.Exception.Message -match 'must stay below' }
if (-not $rejected) { throw 'Output confinement failed.' }
Write-Output 'Final-composite assembly toggle tests passed; live response remains pending.'
Write-Output $output
