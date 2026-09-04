[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$catalog=Join-Path $workspace 'artifacts\analysis\ue4-dxbc-semantic-family-catalog.json'
$candidates=Join-Path $workspace 'artifacts\analysis\ff7r-contact-area-baseline-20260831-alias-candidates.json'
$ledger=Join-Path $workspace 'src\Adapters\FF7RemakeIntergrade\shader-family-alias-decisions.json'
$validator=Join-Path $PSScriptRoot 'Assert-ShaderFamilyAliasDecisions.ps1'

& (Join-Path $PSScriptRoot 'Test-RemakeShaderFamilyAliasCandidates.ps1')
& $validator -DecisionLedgerPath $ledger -CatalogPath $catalog -CandidatePath $candidates

$resolved=Get-Content -Raw -LiteralPath $ledger|ConvertFrom-Json
if(@($resolved.entries).Count -ne 1 -or $resolved.entries[0].state -ne 'pending' -or $resolved.entries[0].shaderHash -ne 'EDA405F2D455D5C7'){throw 'Expected the one current regional candidate to remain explicitly pending'}

$tempRoot=Join-Path ([IO.Path]::GetTempPath()) ("ue4fx-alias-ledger-test-"+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $tempRoot)
try{
    function Assert-Rejected([object]$Value,[string]$Name){
        $path=Join-Path $tempRoot ($Name+'.json')
        $Value|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $path -Encoding UTF8
        $failed=$false
        try{& $validator -DecisionLedgerPath $path -CatalogPath $catalog -CandidatePath $candidates -Quiet}catch{$failed=$true}
        if(-not $failed){throw "Malformed alias ledger was accepted: $Name"}
    }

    $bad=Get-Content -Raw -LiteralPath $ledger|ConvertFrom-Json
    $bad.entries[0].state='accepted'
    Assert-Rejected $bad 'accepted-without-reviewer'

    $bad=Get-Content -Raw -LiteralPath $ledger|ConvertFrom-Json
    $bad.entries=@()
    Assert-Rejected $bad 'missing-current-candidate'

    $bad=Get-Content -Raw -LiteralPath $ledger|ConvertFrom-Json
    $bad.entries[0].familyId='not-the-reviewed-family'
    Assert-Rejected $bad 'candidate-family-disagreement'

    $bad=Get-Content -Raw -LiteralPath $ledger|ConvertFrom-Json
    $bad.catalog.sha256=('0'*64)
    Assert-Rejected $bad 'catalog-hash-disagreement'
}
finally{
    if(Test-Path -LiteralPath $tempRoot){Remove-Item -LiteralPath $tempRoot -Recurse -Force}
}

Write-Host 'PASS: alias decisions are hash-pinned, candidate-complete, catalog-consistent, and fail closed before runtime eligibility.'
