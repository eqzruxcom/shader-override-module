[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$output = Join-Path $repo ('artifacts\FinalCompositeCandidateTest-' + [Guid]::NewGuid().ToString('N'))
$generator = Join-Path $PSScriptRoot 'New-IntergradeFinalCompositeCandidate.ps1'
$result = & $generator -OutputDirectory $output
$manifest = Get-Content -Raw -LiteralPath $result.Manifest | ConvertFrom-Json
if ($manifest.runtimeEligible -or -not $manifest.diagnosticOnly -or $manifest.visualUiPreservation -ne 'pending' -or $manifest.replacesNativeTonemapper) { throw 'Unverified candidate claims production or tone-mapping replacement.' }
if (-not $manifest.neutralBinaryIdentical -or $manifest.changedOriginalInstructionCount -ne 0 -or $manifest.addedInstructionCount -ne 1 -or -not $manifest.nonCodeSectionsIdentical) { throw 'Candidate identity constraints failed.' }
if ($result.UnchangedInstructions -ne 135 -or $manifest.addedInstructionIndex -ne 103) { throw 'Unexpected shader instruction boundary.' }
foreach ($file in $manifest.files) {
    $path = Join-Path $output $file.name
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.sha256 -or (Get-Item -LiteralPath $path).Length -ne $file.size) { throw 'Artifact manifest mismatch.' }
}
$originalHash = (Get-FileHash -LiteralPath (Join-Path $output 'original.bin') -Algorithm SHA256).Hash
$neutralHash = (Get-FileHash -LiteralPath (Join-Path $output 'original.shdr') -Algorithm SHA256).Hash
if ($originalHash -ne $neutralHash) { throw 'Neutral round trip changed bytes.' }
$candidateHash = (Get-FileHash -LiteralPath (Join-Path $output 'scene-half.shdr') -Algorithm SHA256).Hash
if ($candidateHash -ne '507ABAB0052E52DFC5F9A2EF4FFFB82A38AE95D48C3C67D71AB0DF501642F37E') { throw 'Candidate no longer matches the audited single-instruction binary.' }
$rejected = $false
try { & $generator -OutputDirectory $output | Out-Null } catch { $rejected = $_.Exception.Message -match 'output exists' }
if (-not $rejected) { throw 'Generator overwrote existing evidence.' }
$badInput = Join-Path $output 'altered-original.bin'
$bytes = [IO.File]::ReadAllBytes((Join-Path $output 'original.bin'))
$bytes[0] = $bytes[0] -bxor 1
[IO.File]::WriteAllBytes($badInput,$bytes)
$rejected = $false
try { & $generator -OriginalShaderPath $badInput -OutputDirectory (Join-Path $output 'rejected') | Out-Null } catch { $rejected = $_.Exception.Message -match 'fingerprint changed' }
if (-not $rejected -or (Test-Path -LiteralPath (Join-Path $output 'rejected'))) { throw 'Generator accepted modified source or wrote output before source validation.' }
Write-Output 'Final-composite original round-trip and single-instruction candidate tests passed.'
Write-Output $output
