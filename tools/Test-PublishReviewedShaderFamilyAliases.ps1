[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$catalog=Join-Path $workspace 'artifacts\analysis\ue4-dxbc-semantic-family-catalog.json'
$ledger=Join-Path $workspace 'src\Adapters\FF7RemakeIntergrade\shader-family-alias-decisions.json'
$publisher=Join-Path $PSScriptRoot 'Publish-ReviewedShaderFamilyAliases.ps1'
$resolver=Join-Path $PSScriptRoot 'Resolve-ShaderFamilyCatalogTarget.ps1'
$testRoot=Join-Path $workspace 'artifacts\reviewed-alias-publisher-test'
$acceptedLedger=Join-Path $testRoot 'accepted-ledger.json'
$published=Join-Path $testRoot 'published-catalog.json'
$publishedAgain=Join-Path $testRoot 'published-catalog-again.json'

if(Test-Path -LiteralPath $testRoot){Remove-Item -LiteralPath $testRoot -Recurse -Force}
[void](New-Item -ItemType Directory -Path $testRoot)
try{
    $baseHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $catalog).Hash
    $accepted=Get-Content -Raw -LiteralPath $ledger|ConvertFrom-Json
    $entry=$accepted.entries[0]
    $entry.state='accepted'
    $entry|Add-Member -NotePropertyName reviewer -NotePropertyValue 'offline-regression-reviewer'
    $entry|Add-Member -NotePropertyName reviewedAtUtc -NotePropertyValue '2026-09-01T00:00:00Z'
    $entry|Add-Member -NotePropertyName adapter -NotePropertyValue 'FF7RemakeIntergrade'
    $entry|Add-Member -NotePropertyName versionGroup -NotePropertyValue 'FF7RemakeIntergrade-regional'
    [IO.File]::WriteAllText($acceptedLedger,(($accepted|ConvertTo-Json -Depth 14)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))

    $baseResolved=$false
    try{$null=& $resolver -CatalogPath $catalog -Stage ps -ShaderHash EDA405F2D455D5C7 2>$null;$baseResolved=$true}catch{}
    if($baseResolved){throw 'Review-only alias unexpectedly resolved from the immutable base catalog'}
    & $publisher -CatalogPath $catalog -DecisionLedgerPath $acceptedLedger -OutputPath $published
    & $publisher -CatalogPath $catalog -DecisionLedgerPath $acceptedLedger -OutputPath $publishedAgain
    if((Get-FileHash -Algorithm SHA256 -LiteralPath $published).Hash-ne(Get-FileHash -Algorithm SHA256 -LiteralPath $publishedAgain).Hash){throw 'Derived alias catalog publication is not byte-deterministic'}
    if((Get-FileHash -Algorithm SHA256 -LiteralPath $catalog).Hash-ne$baseHash){throw 'Alias publisher mutated the base catalog'}
    $match=& $resolver -CatalogPath $published -Stage ps -ShaderHash EDA405F2D455D5C7
    if($match.familyId-ne'ue4-motion-blur-scene-color-resolve-ps-sm5'-or$match.versionGroup-ne'FF7RemakeIntergrade-regional'){throw 'Published alias did not resolve to its reviewed family and version group'}
    $output=Get-Content -Raw -LiteralPath $published|ConvertFrom-Json
    $variant=$output.families[0].implementations[0].variants[0]
    if(@($variant.identity.hashFastPaths|Where-Object hash -eq 'EDA405F2D455D5C7').Count-ne1){throw 'Published alias is missing from semantic fast paths'}
    if(@($variant.targets|Where-Object shaderHash -eq 'EDA405F2D455D5C7').Count-ne1){throw 'Published alias is missing from exact resolver targets'}

    $rejected=$false
    try{& $publisher -CatalogPath $catalog -DecisionLedgerPath $ledger -OutputPath (Join-Path $testRoot 'pending-should-not-publish.json') 2>$null|Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw 'Publisher accepted a ledger with no reviewed aliases'}
}
finally{
    if(Test-Path -LiteralPath $testRoot){
        $resolved=[IO.Path]::GetFullPath($testRoot)
        $artifactRoot=[IO.Path]::GetFullPath((Join-Path $workspace 'artifacts'))
        if(-not $resolved.StartsWith($artifactRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Refusing to remove unexpected test path: $resolved"}
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

Write-Host 'PASS: only explicitly accepted aliases publish atomically to synchronized fast-path and exact-target indexes; pending aliases remain blocked.'
