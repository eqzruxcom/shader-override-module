[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\generated-runtime\test')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$generator = Join-Path $repoRoot 'tools\New-UE4GeneratedRuntime.ps1'
$adapterPath = Join-Path $repoRoot 'artifacts\generated-adapters\FF7RemakeIntergrade\adapter.json'
$positiveRoot = Join-Path $OutputDirectory 'positive'

& $generator -AdapterPath $adapterPath -OutputDirectory $positiveRoot | Out-Null
$manifestPath = Join-Path $positiveRoot 'runtime-manifest.json'
$iniPath = Join-Path $positiveRoot 'Mods\UE4EffectsGenerated.ini'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$ini = Get-Content -Raw -LiteralPath $iniPath

if ($manifest.adapterId -ne 'FF7RemakeIntergrade') { throw 'Unexpected generated runtime adapter id.' }
if ($manifest.licensedRegexDependency -ne $false) { throw 'Generated runtime must remain independent of licensed regexes.' }
if ($manifest.configuredPasses -ne 4 -or $manifest.emittedPasses -ne 3 -or @($manifest.blockedPasses).Count -ne 1) {
    throw 'Generated runtime did not preserve the expected fail-closed pass counts.'
}
if (@($manifest.controls).Count -ne 3) { throw 'Expected three generated controls.' }
if (@($manifest.controls.key | Select-Object -Unique).Count -ne 3) { throw 'Generated control keys must be unique.' }
if (@($manifest.controls.variable | Select-Object -Unique).Count -ne 3) { throw 'Generated control variables must be unique.' }
if (@($manifest.controls.levels | ForEach-Object { $_ } | Where-Object original).Count -ne 3) { throw 'Each control must expose one original level.' }
if (@($manifest.controls.levels | ForEach-Object { $_ } | Where-Object { -not $_.original }).Count -ne 12) { throw 'Expected twelve emitted non-original levels.' }
if (@($manifest.files | Where-Object relativePath -like 'Mods/*.hlsl').Count -ne 12) { throw 'Expected twelve generated HLSL payload files.' }
if (@($manifest.blockedPasses | Where-Object descriptorId -eq 'ue4-reflection-environment-ssr-composite-ps-sm5').Count -ne 1) {
    throw 'The ineligible downstream SSR composite must remain blocked.'
}
if ($ini -match 'e2aa1c8cb39e0a55') { throw 'Blocked SSR shader leaked into the generated runtime INI.' }
foreach ($hash in @('ef7fe8d9c4e9ad15','af6cd28a0108a18a','a77b589dce5822d6')) {
    if ($ini -notmatch [regex]::Escape($hash)) { throw "Eligible shader hash is missing from generated runtime: $hash" }
}
foreach ($key in @('no_modifiers VK_HOME','no_modifiers VK_INSERT','no_modifiers VK_PAGEUP')) {
    if ($ini -notmatch [regex]::Escape("key = $key")) { throw "Generated runtime key is missing: $key" }
}
foreach ($control in @($manifest.controls)) {
    if ($control.defaultIndex -ne 4) { throw "Expected original default index 4 for $($control.descriptorId)." }
    foreach ($level in @($control.levels | Where-Object { -not $_.original })) {
        $generated = Join-Path $positiveRoot ($level.generatedFile -replace '/', '\')
        if (-not (Test-Path -LiteralPath $generated -PathType Leaf)) { throw "Generated shader is missing: $generated" }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $generated).Hash -ne [string]$level.sourceSha256) {
            throw "Generated shader hash mismatch: $generated"
        }
    }
}
foreach ($file in @($manifest.files)) {
    $path = Join-Path $positiveRoot ($file.relativePath -replace '/', '\')
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$file.sha256) { throw "Payload manifest hash mismatch: $path" }
}

function Assert-GeneratorRejected {
    param([string]$Name, [scriptblock]$Mutate)
    $root = Join-Path $OutputDirectory "negative-$Name"
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $adapter = Get-Content -Raw -LiteralPath $adapterPath | ConvertFrom-Json
    & $Mutate $adapter
    $tampered = Join-Path $root 'adapter.json'
    [IO.File]::WriteAllText($tampered, ($adapter | ConvertTo-Json -Depth 12) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    $failed = $false
    try {
        & $generator -AdapterPath $tampered -OutputDirectory (Join-Path $root 'out') | Out-Null
    } catch {
        $failed = $true
    }
    if (-not $failed) { throw "Generated runtime accepted negative case: $Name" }
}

Assert-GeneratorRejected 'licensed-dependency' {
    param($adapter)
    $adapter.licensedRegexDependency = $true
}
Assert-GeneratorRejected 'unsupported-integration' {
    param($adapter)
    $adapter.passes[0].integration = 'unknown-integration'
}
Assert-GeneratorRejected 'blocked-and-eligible' {
    param($adapter)
    $adapter.blockedPasses[0].descriptorId = $adapter.passes[0].descriptorId
}
Assert-GeneratorRejected 'control-pack-hash-mismatch' {
    param($adapter)
    $adapter.passes[0].controlPackSha256 = ('0' * 64)
}

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    emittedPasses = [int]$manifest.emittedPasses
    blockedPasses = @($manifest.blockedPasses).Count
    controls = @($manifest.controls).Count
    shaderFiles = @($manifest.files | Where-Object relativePath -like 'Mods/*.hlsl').Count
    negativeCases = @('licensed-dependency','unsupported-integration','blocked-and-eligible','control-pack-hash-mismatch')
    iniSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $iniPath).Hash
}
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'report.json'), ($report | ConvertTo-Json -Depth 5) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

Write-Output 'UE4 generated runtime tests passed.'
[pscustomobject]@{
    EmittedPasses = $manifest.emittedPasses
    BlockedPasses = @($manifest.blockedPasses).Count
    ShaderFiles = $report.shaderFiles
    NegativeCases = @($report.negativeCases).Count
    Result = 'pass'
}
