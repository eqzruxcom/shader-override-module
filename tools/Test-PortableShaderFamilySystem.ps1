[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))

& (Join-Path $PSScriptRoot 'Test-RemakeRebirthFamilyRelations.ps1')
& (Join-Path $PSScriptRoot 'Test-ShaderFamilyAliasDecisionLedger.ps1')
& (Join-Path $PSScriptRoot 'Test-PublishReviewedShaderFamilyAliases.ps1')
& (Join-Path $PSScriptRoot 'Test-ReviewedAliasDxvkEndToEnd.ps1')
& (Join-Path $PSScriptRoot 'Test-BuildDxvkD3D11ShaderReplacement.ps1')
& (Join-Path $PSScriptRoot 'Test-BuildDxvkD3D11AssemblyFamily.ps1')
& (Join-Path $PSScriptRoot 'Test-AssertDxvkD3D11AssemblyFamilyBuild.ps1')
& (Join-Path $PSScriptRoot 'Test-DxvkD3D11MsvcBuildPipeline.ps1')
& (Join-Path $PSScriptRoot 'Test-DxvkD3D11RuntimeBundle.ps1')

$jsonRoots=@(
    (Join-Path $workspace 'src\Engine\ShaderFamilies'),
    (Join-Path $workspace 'src\Adapters\FF7RemakeIntergrade'),
    (Join-Path $workspace 'src\Backends\DxvkD3D11'),
    (Join-Path $workspace 'artifacts\analysis')
)
$jsonFiles=@(Get-ChildItem -LiteralPath $jsonRoots -Filter '*.json' -File -Recurse -ErrorAction Stop)
foreach($file in $jsonFiles){
    try{$null=Get-Content -Raw -LiteralPath $file.FullName|ConvertFrom-Json -ErrorAction Stop}
    catch{throw "Invalid JSON artifact or schema: $($file.FullName): $($_.Exception.Message)"}
}

$parseIssues=[Collections.Generic.List[string]]::new()
$scripts=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File)
foreach($script in $scripts){
    $tokens=$null
    $issues=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$issues)
    foreach($issue in @($issues)){$parseIssues.Add("$($issue.Extent.File):$($issue.Extent.StartLineNumber): $($issue.Message)")}
}
if($parseIssues.Count){throw ($parseIssues -join [Environment]::NewLine)}

Write-Host "PASS: complete portable shader-family system is coherent ($($jsonFiles.Count) JSON documents, $($scripts.Count) PowerShell tools)."
