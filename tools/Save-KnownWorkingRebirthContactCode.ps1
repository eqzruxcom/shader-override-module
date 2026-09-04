[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$output=Join-Path $repo 'working-code/Contact shadows - Rebirth Mod - Code worked'
$checkpoint=Join-Path $repo 'artifacts/checkpoints/rebirth-contact-first-working-20260831-v1'
$record=Get-Content -LiteralPath (Join-Path $checkpoint 'checkpoint.json') -Raw|ConvertFrom-Json
$candidateRoot=Join-Path $repo 'artifacts/rebirth-contact-shared-repeat-candidate-20260831-v1'
$candidate=Get-Content -LiteralPath (Join-Path $candidateRoot 'candidate.json') -Raw|ConvertFrom-Json
$provenance=Get-Content -LiteralPath (Join-Path $repo 'src/ThirdParty/ShaderInjector/provenance.json') -Raw|ConvertFrom-Json
$queue=[Collections.Generic.List[object]]::new()
function Queue-File([string]$source,[string]$relative,[string]$expected='') {
    $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if($expected -and $hash -ne $expected){throw "Changed reference: $source"}
    $target=Join-Path $output $relative
    if(Test-Path -LiteralPath $target){throw "Preserve existing snapshot: $target"}
    $queue.Add([pscustomobject]@{source=$source;relativePath=$relative;sha256=$hash})
}
foreach($entry in $record.files) {
    if($entry.kind -notin @('installed-payload','current-source-snapshot','historical-receipt','validation-receipt')){continue}
    Queue-File (Join-Path $checkpoint $entry.relativePath) ('working-remake-port/'+$entry.relativePath) $entry.sha256
}
foreach($variant in $candidate.variants) {
    Queue-File (Join-Path $candidateRoot "validation/$($variant.shaderHash)-original.bin") ("original-remake/$($variant.shaderHash)-cs.bin") $variant.originalSha256
    Queue-File (Join-Path $candidateRoot "validation/$($variant.shaderHash)-original.asm") ("original-remake/$($variant.shaderHash)-cs.asm")
}
$utf8=[Text.UTF8Encoding]::new($false)
foreach($file in @(@($provenance.sourcePath,$provenance.sourceLfSha256),@($provenance.noiseSourcePath,$provenance.noiseSourceLfSha256))) {
    $source=Join-Path $repo ('reference/ShaderInjector/'+$file[0])
    $lf=[IO.File]::ReadAllText($source).Replace("`r`n","`n")
    $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($lf)))
    if($hash -ne $file[1]){throw 'Original donor differs from pinned provenance.'}
    Queue-File $source ('original-donor/'+(Split-Path $source -Leaf))
}
Queue-File (Join-Path $repo 'src/ThirdParty/ShaderInjector/LICENSE.txt') 'original-donor/LICENSE.txt'
Queue-File (Join-Path $repo 'src/ThirdParty/ShaderInjector/provenance.json') 'original-donor/provenance.json'
if(Test-Path -LiteralPath (Join-Path $output 'code-record.json')){throw 'Do not overwrite a known-working code record.'}
foreach($copy in $queue){
    $target=Join-Path $output $copy.relativePath
    $null=New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force
    Copy-Item -LiteralPath $copy.source -Destination $target
    foreach($path in @($copy.source,$target)){if((Get-FileHash -LiteralPath $path).Hash -ne $copy.sha256){throw "Copy verification failed: $path"}}
}
$manifest=[ordered]@{label='Contact shadows - Rebirth Mod - Code worked';createdAtUtc=[DateTime]::UtcNow.ToString('o');donorCommit=$provenance.commit;donorRepository=$provenance.repository;checkpoint=$checkpoint;checkpointSha256=(Get-FileHash (Join-Path $checkpoint 'checkpoint.json')).Hash;candidateSha256=(Get-FileHash (Join-Path $candidateRoot 'candidate.json')).Hash;scriptSha256=(Get-FileHash $PSCommandPath).Hash;observedGame='FF7 Remake Intergrade modified UE4, DX11';userReportedWorking=$true;knownFlaw='Hard added sword/cone shadow edges beside softer native shadows';releaseEligible=$false;gameFilesModified=$false;files=@($queue.ToArray())}
[IO.File]::WriteAllText((Join-Path $output 'code-record.json'),($manifest|ConvertTo-Json -Depth 7)+"`n",$utf8)
[pscustomobject]@{folder=$output;verifiedFiles=$queue.Count;label=$manifest.label}|ConvertTo-Json
