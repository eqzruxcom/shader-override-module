[CmdletBinding()]
param(
    [string]$ContractDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Engine\PassExecution')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$directory = [IO.Path]::GetFullPath($ContractDirectory).TrimEnd('\')
if (-not $directory.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Pass execution contracts must be inside the workspace.'
}
$schema = Join-Path $directory 'schema.json'
if (-not (Test-Path -LiteralPath $schema -PathType Leaf)) { throw 'Pass execution schema is missing.' }
$documents = @(Get-ChildItem -LiteralPath $directory -File -Filter '*.json' | Where-Object Name -ne 'schema.json')
if ($documents.Count -lt 1) { throw 'No pass execution contracts were found.' }

function Assert-Properties([pscustomobject]$Object, [string[]]$Required, [string[]]$Allowed, [string]$Context) {
    $names = @($Object.PSObject.Properties.Name)
    foreach ($name in $Required) { if ($name -notin $names) { throw "$Context is missing property '$name'." } }
    foreach ($name in $names) { if ($name -notin $Allowed) { throw "$Context has unexpected property '$name'." } }
}

$results = @()
foreach ($file in $documents) {
    $contract = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    Assert-Properties $contract @('schemaVersion','id','displayName','trigger','execution','controls','safety') @('schemaVersion','id','displayName','description','trigger','execution','controls','backendMappings','evidence','safety') $file.Name
    if ($contract.schemaVersion -ne 1 -or $contract.id -notmatch '^[a-z0-9][a-z0-9-]+$') { throw "Invalid envelope: $($file.Name)" }
    Assert-Properties $contract.trigger @('kind','stage','family','timing') @('kind','stage','family','timing','adapterFastPaths') "$($file.Name) trigger"
    Assert-Properties $contract.execution @('ownership','kind','shaders','geometry','fixedState','resources','stateRestore') @('ownership','kind','shaders','geometry','fixedState','resources','stateRestore') "$($file.Name) execution"
    Assert-Properties $contract.controls @('bound','reserved') @('bound','reserved') "$($file.Name) controls"
    Assert-Properties $contract.safety @('runtimeEligible','installed','prerequisites') @('runtimeEligible','installed','prerequisites') "$($file.Name) safety"

    $boundKeys = @($contract.controls.bound | ForEach-Object { ([string]$_.key).ToUpperInvariant() })
    $reservedKeys = @($contract.controls.reserved | ForEach-Object { ([string]$_.key).ToUpperInvariant() })
    if ('F10' -in $boundKeys -or @($boundKeys | Where-Object { $_ -in $reservedKeys }).Count -ne 0) {
        throw "$($file.Name) binds a reserved key."
    }
    if ($contract.execution.ownership -eq 'injector-owned') {
        if ($contract.execution.geometry.source -eq 'caller') { throw "$($file.Name) claims injector ownership but uses caller geometry." }
        if ($contract.execution.kind -eq 'render') {
            foreach ($property in @('blend','depthTest','depthWrite','stencil','cull')) {
                if ($null -eq $contract.execution.fixedState.PSObject.Properties[$property]) {
                    throw "$($file.Name) does not explicitly own render state '$property'."
                }
            }
            if ($contract.execution.geometry.source -eq 'fullscreen-triangle' -and
                ($contract.execution.geometry.vertexCount -ne 3 -or $contract.execution.geometry.startVertex -ne 0)) {
                throw "$($file.Name) fullscreen triangle is not Draw(3,0)."
            }
        }
    }
    foreach ($stage in @('vs','ps','cs','hs','ds','gs')) {
        $binding = $contract.execution.shaders.PSObject.Properties[$stage]
        if ($null -eq $binding -or $null -eq $binding.Value) { continue }
        $relative = [string]$binding.Value.path
        $path = [IO.Path]::GetFullPath((Join-Path $workspace $relative))
        if (-not $path.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$($file.Name) shader path is missing or external: $relative" }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$binding.Value.sha256) {
            throw "$($file.Name) shader hash drifted: $relative"
        }
    }
    if ($contract.safety.runtimeEligible -and -not $contract.safety.installed -and @($contract.safety.prerequisites).Count -gt 0) {
        throw "$($file.Name) is marked runtime-eligible while prerequisites remain."
    }
    $results += [ordered]@{id=[string]$contract.id;ownership=[string]$contract.execution.ownership;trigger=[string]$contract.trigger.family;runtimeEligible=[bool]$contract.safety.runtimeEligible}
}

[pscustomobject]@{
    Result='pass'
    Contracts=$results.Count
    InjectorOwned=@($results | Where-Object ownership -eq 'injector-owned').Count
    ReservedF10='unbound'
    Results=$results
}
