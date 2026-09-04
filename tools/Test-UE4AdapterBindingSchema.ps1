[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$schemaPath = Join-Path $repoRoot 'src\Engine\UE4\AdapterBindings\schema.json'
$bindingPath = Join-Path $repoRoot 'src\Adapters\FF7RemakeIntergrade\adapter-bindings.json'

$bindingJson = Get-Content -Raw -LiteralPath $bindingPath
if (-not ($bindingJson | Test-Json -SchemaFile $schemaPath -ErrorAction Stop)) {
    throw 'The canonical FF7 binding does not satisfy the adapter-binding schema.'
}

$missingContract = $bindingJson | ConvertFrom-Json
$missingContract.passes[0].evidence.PSObject.Properties.Remove('temporalBlendContract')
$missingContractJson = $missingContract | ConvertTo-Json -Depth 30
$validationErrors = @()
$acceptedWithoutContract = $missingContractJson | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue -ErrorVariable +validationErrors
if ($acceptedWithoutContract) {
    throw 'A temporal-volume binding without temporalBlendContract was unexpectedly accepted.'
}

Write-Output 'UE4 adapter-binding schema tests passed.'
