[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$baseCatalog=Join-Path $workspace 'artifacts\analysis\ue4-dxbc-semantic-family-catalog.json'
$sourceLedger=Join-Path $workspace 'src\Adapters\FF7RemakeIntergrade\shader-family-alias-decisions.json'
$sourceHlsl=Join-Path $workspace 'artifacts\final-composite-study-20260830-220038-889\eda405f2d455d5c7-ps_replace.txt'
$originalDxbc=Join-Path $workspace 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\dxbc\eda405f2d455d5c7-ps.bin'
$testRoot=Join-Path $workspace 'artifacts\reviewed-alias-dxvk-e2e-test'
$acceptedLedger=Join-Path $testRoot 'accepted-ledger.json'
$derivedCatalog=Join-Path $testRoot 'derived-catalog.json'
$output=Join-Path $testRoot 'compiled'

foreach($required in @($baseCatalog,$sourceLedger,$sourceHlsl,$originalDxbc)){if(-not(Test-Path -LiteralPath $required -PathType Leaf)){throw "Required end-to-end fixture is missing: $required"}}
if(Test-Path -LiteralPath $testRoot){Remove-Item -LiteralPath $testRoot -Recurse -Force}
[void](New-Item -ItemType Directory -Path $testRoot)
try{
    $accepted=Get-Content -Raw -LiteralPath $sourceLedger|ConvertFrom-Json
    $entry=$accepted.entries[0]
    $entry.state='accepted'
    $entry|Add-Member -NotePropertyName reviewer -NotePropertyValue 'offline-e2e-regression-reviewer'
    $entry|Add-Member -NotePropertyName reviewedAtUtc -NotePropertyValue '2026-09-01T00:00:00Z'
    $entry|Add-Member -NotePropertyName adapter -NotePropertyValue 'FF7RemakeIntergrade'
    $entry|Add-Member -NotePropertyName versionGroup -NotePropertyValue 'FF7RemakeIntergrade-contact-area-baseline'
    [IO.File]::WriteAllText($acceptedLedger,(($accepted|ConvertTo-Json -Depth 14)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))

    & (Join-Path $PSScriptRoot 'Publish-ReviewedShaderFamilyAliases.ps1') -CatalogPath $baseCatalog -DecisionLedgerPath $acceptedLedger -OutputPath $derivedCatalog
    $checkerBuild=& (Join-Path $PSScriptRoot 'Build-DxbcCompatibilityChecker.ps1') -OutputDirectory (Join-Path $testRoot 'checker')
    $checker=[string]$checkerBuild.Executable

    $baseRejected=$false
    try{
        & (Join-Path $PSScriptRoot 'Build-DxvkD3D11ShaderReplacement.ps1') -SourcePath $sourceHlsl -OutputDirectory (Join-Path $testRoot 'base-rejected') -OriginalBytecode $originalDxbc -CompatibilityCheckerPath $checker -FamilyCatalogPath $baseCatalog
    }
    catch{$baseRejected=$_.Exception.Message -match 'No reviewed catalog target matches'}
    if(-not $baseRejected){throw 'Base semantic catalog did not reject the unreviewed regional alias'}

    & (Join-Path $PSScriptRoot 'Build-DxvkD3D11ShaderReplacement.ps1') -SourcePath $sourceHlsl -OutputDirectory $output -OriginalBytecode $originalDxbc -CompatibilityCheckerPath $checker -FamilyCatalogPath $derivedCatalog
    $manifestPath=Join-Path $output 'eda405f2d455d5c7-ps_replace.manifest.json'
    $binaryPath=Join-Path $output 'eda405f2d455d5c7-ps_replace.bin'
    if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)-or-not(Test-Path -LiteralPath $binaryPath -PathType Leaf)){throw 'Reviewed alias build did not publish its offline DXBC and manifest'}
    $manifest=Get-Content -Raw -LiteralPath $manifestPath|ConvertFrom-Json
    if($manifest.originalIdentityVerified-ne$true-or$manifest.compatibilityStatus-ne'passed-declaration-contract-rdef-unavailable'){throw 'Reviewed alias build did not verify original identity and executable declaration compatibility for stripped RDEF'}
    if($manifest.reviewedFamily.familyId-ne'ue4-motion-blur-scene-color-resolve-ps-sm5'-or$manifest.reviewedFamily.versionGroup-ne'FF7RemakeIntergrade-contact-area-baseline'){throw 'DXVK manifest lost the reviewed alias family classification'}
    if($manifest.runtimeEligible-ne$false-or$manifest.installed-ne$false){throw 'Offline reviewed-alias build escaped its non-runtime state'}
    if($manifest.outputSha256-ne(Get-FileHash -Algorithm SHA256 -LiteralPath $binaryPath).Hash.ToLowerInvariant()){throw 'Reviewed alias DXBC manifest hash is incorrect'}

    $badSourceRoot=Join-Path $testRoot 'bad-resource-source'
    [void](New-Item -ItemType Directory -Path $badSourceRoot)
    $badSource=Join-Path $badSourceRoot 'eda405f2d455d5c7-ps_replace.hlsl'
    $badText=[IO.File]::ReadAllText($sourceHlsl).Replace('Texture2D<float4> t2 : register(t2);','Texture2D<uint4> t2 : register(t2);')
    if($badText-eq[IO.File]::ReadAllText($sourceHlsl)){throw 'Failed to construct stripped-RDEF resource mismatch fixture'}
    [IO.File]::WriteAllText($badSource,$badText,[Text.UTF8Encoding]::new($false))
    $badRejected=$false
    try{
        & (Join-Path $PSScriptRoot 'Build-DxvkD3D11ShaderReplacement.ps1') -SourcePath $badSource -OutputDirectory (Join-Path $testRoot 'bad-resource-output') -OriginalBytecode $originalDxbc -CompatibilityCheckerPath $checker -FamilyCatalogPath $derivedCatalog
    }
    catch{$badRejected=$_.Exception.Message -match 'executable resource declaration mismatch' -and $_.Exception.Message -match 'original binding declarations'}
    if(-not $badRejected){throw 'Stripped-RDEF fallback did not reject an altered executable resource declaration'}
}
finally{
    if(Test-Path -LiteralPath $testRoot){
        $resolved=[IO.Path]::GetFullPath($testRoot)
        $artifactRoot=[IO.Path]::GetFullPath((Join-Path $workspace 'artifacts'))
        if(-not $resolved.StartsWith($artifactRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Refusing to remove unexpected end-to-end test path: $resolved"}
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

Write-Host 'PASS: captured EDA405F2D455D5C7 flows from reviewed structural alias to identity-verified, declaration-compatible offline DXVK replacement; base and altered-resource paths are rejected.'
