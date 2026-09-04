[CmdletBinding()]
param(
    [string]$FamilyDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\accepted-contact-family-rebuild-20260904-v2-portable'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-accepted-contact-family-guard-rejection-20260904.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$familyRoot = [IO.Path]::GetFullPath($FamilyDirectory).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $familyRoot.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase) -or -not $output.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Inputs and output must remain under artifacts' }

$sourceIni = Join-Path $familyRoot 'ContactShadowFamily.ini'
$sourceGeneration = Join-Path $familyRoot 'family-generation.json'
$contractTest = Join-Path $PSScriptRoot 'Test-IntergradeAcceptedContactShadowFamilyContract.ps1'
foreach ($path in @($sourceIni,$sourceGeneration,$contractTest)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file is missing: $path" } }

$temporaryRoot = Join-Path $artifacts ('.tmp-contact-family-guards-' + [guid]::NewGuid().ToString('N'))
$utf8 = [Text.UTF8Encoding]::new($false)
$results = [Collections.Generic.List[object]]::new()

function Replace-ExactlyOnce([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    $first = $Text.IndexOf($Old,[StringComparison]::Ordinal)
    if ($first -lt 0 -or $Text.IndexOf($Old,$first+$Old.Length,[StringComparison]::Ordinal) -ge 0) { throw "Mutation anchor was not unique: $Label" }
    return $Text.Substring(0,$first) + $New + $Text.Substring($first+$Old.Length)
}

function Invoke-NegativeCase([string]$Name,[scriptblock]$Mutation,[string]$ExpectedFailure,[bool]$UpdateManifestHash) {
    $caseRoot = Join-Path $temporaryRoot $Name
    [IO.Directory]::CreateDirectory($caseRoot) | Out-Null
    $iniPath = Join-Path $caseRoot 'ContactShadowFamily.ini'
    $generationPath = Join-Path $caseRoot 'family-generation.json'
    $reportPath = Join-Path $caseRoot 'contract.json'
    $text = & $Mutation (Get-Content -Raw -LiteralPath $sourceIni)
    [IO.File]::WriteAllText($iniPath,$text,$utf8)
    $generation = Get-Content -Raw -LiteralPath $sourceGeneration | ConvertFrom-Json
    if ($UpdateManifestHash) { $generation.outputIniSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $iniPath).Hash }
    $generation.outputIni = $iniPath
    [IO.File]::WriteAllText($generationPath,(($generation | ConvertTo-Json -Depth 10)+[Environment]::NewLine),$utf8)
    $failure = $null
    try { & $contractTest -IniPath $iniPath -GenerationReportPath $generationPath -OutputPath $reportPath | Out-Null }
    catch { $failure = $_.Exception.Message }
    if (-not $failure -or $failure -notmatch $ExpectedFailure) { throw "Negative case $Name was not rejected as expected: $failure" }
    $results.Add([ordered]@{ case=$Name; result='rejected-as-expected'; expected=$ExpectedFailure; message=$failure })
}

try {
    [IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
    $positiveReport = Join-Path $temporaryRoot 'positive-contract.json'
    & $contractTest -IniPath $sourceIni -GenerationReportPath $sourceGeneration -OutputPath $positiveReport | Out-Null
    $positive = Get-Content -Raw -LiteralPath $positiveReport | ConvertFrom-Json
    if (-not $positive.passed -or $positive.matchCount -ne 5) { throw 'Positive family contract failed' }
    $results.Add([ordered]@{ case='unchanged-family'; result='passed'; matched=$positive.matchCount })

    Invoke-NegativeCase -Name 'stale-manifest-hash' -UpdateManifestHash $false -ExpectedFailure 'Generation report does not describe' -Mutation {
        param($text) Replace-ExactlyOnce $text 'global $ue4fx_contact_edge_width_v2 = 0.06' 'global $ue4fx_contact_edge_width_v2 = 0.060001' 'manifest drift'
    }
    Invoke-NegativeCase -Name 'base-t4-range-overlap' -UpdateManifestHash $true -ExpectedFailure '62b33a2d1e505241-cs.asm' -Mutation {
        param($text) Replace-ExactlyOnce $text "min_instructions = 631`r`nmax_instructions = 631" "min_instructions = 478`r`nmax_instructions = 631" 'Base-T4 lower bound'
    }
    Invoke-NegativeCase -Name 'frustum-t4-range-overlap' -UpdateManifestHash $true -ExpectedFailure '5a9fbefe0ab6f815-cs.asm' -Mutation {
        param($text) Replace-ExactlyOnce $text "min_instructions = 478`r`nmax_instructions = 478" "min_instructions = 478`r`nmax_instructions = 631" 'Frustum-T4 upper bound'
    }

    $summary = [ordered]@{
        schemaVersion = 1
        detector = 'ff7-remake-accepted-contact-family-guard-rejection-v1'
        familyDirectory = [IO.Path]::GetRelativePath($root,$familyRoot).Replace('\','/')
        familyIniSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceIni).Hash
        positiveCases = @($results | Where-Object result -eq 'passed').Count
        rejectedNegativeCases = @($results | Where-Object result -eq 'rejected-as-expected').Count
        cases = @($results)
        conclusion = 'Manifest drift and either unsafe T4 instruction-range widening fail closed.'
        liveFilesModified = $false
    }
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
    [IO.File]::WriteAllText($output,(($summary | ConvertTo-Json -Depth 10)+[Environment]::NewLine),$utf8)
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        $resolvedTemp = [IO.Path]::GetFullPath($temporaryRoot)
        if (-not $resolvedTemp.StartsWith($artifacts + '\.tmp-contact-family-guards-',[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing unsafe temporary cleanup' }
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}

Write-Host "PASS: one positive family and $(@($results | Where-Object result -eq 'rejected-as-expected').Count) guard mutations behaved fail-closed."
Write-Host "REPORT=$output"

