[CmdletBinding()]
param(
    [string]$ContractPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Engine\PassExecution\r3d-ssgi-owned-fullscreen-composite.json'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\pass-execution-3dmigoto-r3d-ssgi-composite')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$contractFile = [IO.Path]::GetFullPath($ContractPath)
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if (-not $contractFile.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase) -or
    -not $output.StartsWith((Join-Path $workspace 'artifacts') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Contract must be in the workspace and output must be in workspace artifacts.'
}
if (-not (Test-Path -LiteralPath $contractFile -PathType Leaf)) { throw "Contract is missing: $contractFile" }

& (Join-Path $PSScriptRoot 'Test-PassExecutionContracts.ps1') | Out-Null
$contract = Get-Content -Raw -LiteralPath $contractFile | ConvertFrom-Json
$mappingProperty = $contract.backendMappings.PSObject.Properties['3dmigoto-d3d11']
if ($null -eq $mappingProperty -or $mappingProperty.Value.kind -ne 'custom-shader') {
    throw 'Contract has no supported 3dmigoto-d3d11 CustomShader mapping.'
}
$mapping = $mappingProperty.Value
if ($contract.execution.ownership -ne 'injector-owned' -or $contract.execution.kind -ne 'render' -or
    $contract.execution.geometry.source -ne 'fullscreen-triangle' -or
    $contract.execution.geometry.vertexCount -ne 3 -or $contract.execution.geometry.startVertex -ne 0) {
    throw 'This emitter currently accepts only injector-owned fullscreen-triangle render passes.'
}

foreach ($name in @('section','shaderFiles','sampler','preCommands','outputBindings','resourceBindings')) {
    if ($null -eq $mapping.PSObject.Properties[$name]) { throw "3DMigoto mapping is missing '$name'." }
}
if ([string]$mapping.section -notmatch '^CustomShader[A-Za-z0-9_]+$') { throw 'Unsafe CustomShader section name.' }

$state = $contract.execution.fixedState
$blend = switch ([string]$state.blend) {
    'add-one-one' { 'ADD ONE ONE' }
    'disabled' { 'disable' }
    default { throw "Unsupported 3DMigoto blend mapping: $($state.blend)" }
}
$topology = switch ([string]$contract.execution.geometry.topology) {
    'triangle-list' { 'triangle_list' }
    default { throw "Unsupported 3DMigoto topology mapping: $($contract.execution.geometry.topology)" }
}
$cull = switch ([string]$state.cull) {
    'none' { 'none' }
    'back' { 'back' }
    'front' { 'front' }
    default { throw "Unsupported 3DMigoto cull mapping: $($state.cull)" }
}

$lines = [Collections.Generic.List[string]]::new()
$lines.Add("[$($mapping.section)]")
$lines.Add("ps = $($mapping.shaderFiles.ps)")
$lines.Add("vs = $($mapping.shaderFiles.vs)")
foreach ($stage in @('hs','ds','gs')) {
    $property = $contract.execution.shaders.PSObject.Properties[$stage]
    if ($null -ne $property -and $null -eq $property.Value) { $lines.Add("$stage = null") }
}
$lines.Add("sampler = $($mapping.sampler)")
$lines.Add("blend = $blend")
$lines.Add('depth_enable = ' + $(if ([bool]$state.depthTest) { 'true' } else { 'false' }))
$lines.Add('depth_write_mask = ' + $(if ([bool]$state.depthWrite) { 'all' } else { 'zero' }))
$lines.Add('stencil_enable = ' + $(if ([bool]$state.stencil) { 'true' } else { 'false' }))
$lines.Add("cull = $cull")
$lines.Add("topology = $topology")
foreach ($command in @($mapping.preCommands)) { $lines.Add([string]$command) }
foreach ($binding in @($mapping.outputBindings)) { $lines.Add([string]$binding) }
foreach ($binding in @($mapping.resourceBindings)) { $lines.Add("$($binding.target) = $($binding.source)") }
$lines.Add("draw = $($contract.execution.geometry.vertexCount), $($contract.execution.geometry.startVertex)")
foreach ($binding in @($mapping.resourceBindings)) { $lines.Add("post $($binding.target) = $($binding.post)") }
$fragment = ($lines -join "`r`n") + "`r`n"

if (Test-Path -LiteralPath $output -PathType Container) { [IO.Directory]::Delete($output, $true) }
$mods = Join-Path $output 'Mods'
[IO.Directory]::CreateDirectory($mods) | Out-Null
$fragmentPath = Join-Path $mods 'GeneratedOwnedPass.ini'
[IO.File]::WriteAllText($fragmentPath, $fragment, [Text.UTF8Encoding]::new($false))
foreach ($stage in @('vs','ps')) {
    $binding = $contract.execution.shaders.PSObject.Properties[$stage].Value
    $source = [IO.Path]::GetFullPath((Join-Path $workspace ([string]$binding.path)))
    $destination = Join-Path $mods ([string]$mapping.shaderFiles.$stage)
    [IO.File]::Copy($source, $destination, $false)
}

$files = @(Get-ChildItem -LiteralPath $mods -File | Sort-Object Name | ForEach-Object {
    [ordered]@{name=$_.Name;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash;bytes=$_.Length}
})
$manifest = [ordered]@{
    schemaVersion=1
    result='pass'
    backend='3dmigoto-d3d11'
    contractId=[string]$contract.id
    contractPath=$contractFile
    contractSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $contractFile).Hash
    section=[string]$mapping.section
    executionOwnership=[string]$contract.execution.ownership
    files=$files
    runtimeEligible=[bool]$contract.safety.runtimeEligible
    installed=$false
}
$manifestPath = Join-Path $output 'manifest.json'
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 8) + "`r`n"), [Text.UTF8Encoding]::new($false))
[pscustomobject]@{Result='pass';Backend='3dmigoto-d3d11';Section=$mapping.section;Files=$files.Count;RuntimeEligible=$manifest.runtimeEligible}
