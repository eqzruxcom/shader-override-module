[CmdletBinding()]
param(
    [string]$AdapterPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\generated-adapters\FF7RemakeIntergrade\adapter.json'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\generated-runtime\FF7RemakeIntergrade')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$adapterFull = (Resolve-Path -LiteralPath $AdapterPath).Path
$outputFull = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$allowedOutputRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts\generated-runtime')).TrimEnd('\')
$utf8 = [Text.UTF8Encoding]::new($false)

if (-not $outputFull.StartsWith($allowedOutputRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Generated runtime output must remain below $allowedOutputRoot."
}

function Resolve-ProjectFile([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'A required project file path is empty.' }
    $full = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    } else {
        [IO.Path]::GetFullPath((Join-Path $repoRoot ($Path -replace '/', '\')))
    }
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Project path escapes the workspace: $full"
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Required project file is missing: $full" }
    $full
}

function Get-Sha256([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Get-IntegrationSpec([string]$Integration) {
    switch ($Integration) {
        'temporal-volume-post' {
            [pscustomobject]@{ Token = 'TemporalVolume'; Variable = 'temporal_volume'; Key = 'no_modifiers VK_HOME'; ValueProperty = 'target'; Kind = 'post' }
        }
        'scene-saturation-replacement' {
            [pscustomobject]@{ Token = 'SceneSaturation'; Variable = 'scene_saturation'; Key = 'no_modifiers VK_INSERT'; ValueProperty = 'saturation'; Kind = 'replacement' }
        }
        'packed-ao-strength-replacement' {
            [pscustomobject]@{ Token = 'AmbientOcclusion'; Variable = 'ambient_occlusion'; Key = 'no_modifiers VK_PAGEUP'; ValueProperty = 'strength'; Kind = 'replacement' }
        }
        default { throw "Unsupported generated runtime integration: $Integration" }
    }
}

function Get-SafeAdapterToken([string]$AdapterId) {
    $token = $AdapterId -replace '[^A-Za-z0-9]', ''
    if ([string]::IsNullOrWhiteSpace($token)) { throw 'Adapter id does not contain a safe runtime token.' }
    $token
}

function Get-LevelSource([object]$Level) {
    $property = $Level.PSObject.Properties['source']
    if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) { return $null }
    [string]$property.Value
}

function Assert-Adapter {
    param([object]$Adapter)

    if ([int]$Adapter.schemaVersion -ne 1) { throw 'Generated adapter schemaVersion must be 1.' }
    if ([string]$Adapter.renderer -ne 'D3D11') { throw 'Generated runtime currently supports D3D11 adapters only.' }
    if ([bool]$Adapter.licensedRegexDependency) { throw 'Generated runtime refuses adapters with a licensed regex dependency.' }
    if ([int]$Adapter.configuredPasses -ne (@($Adapter.passes).Count + @($Adapter.blockedPasses).Count)) {
        throw 'Configured pass count does not equal emitted plus blocked passes.'
    }
    $duplicates = @($Adapter.passes | Group-Object descriptorId | Where-Object Count -gt 1)
    if ($duplicates.Count) { throw 'Generated adapter contains duplicate eligible descriptor ids.' }
    $blockedIds = @($Adapter.blockedPasses.descriptorId)
    foreach ($pass in @($Adapter.passes)) {
        if ($blockedIds -contains [string]$pass.descriptorId) { throw "Pass is both eligible and blocked: $($pass.descriptorId)" }
        $pack = Resolve-ProjectFile ([string]$pass.controlPack)
        if ((Get-Sha256 $pack) -ne [string]$pass.controlPackSha256) { throw "Control-pack hash mismatch: $($pass.descriptorId)" }
        if (-not @($pass.levels).Count) { throw "Eligible pass has no levels: $($pass.descriptorId)" }
        $originals = @($pass.levels | Where-Object { $null -eq (Get-LevelSource $_) })
        if ($originals.Count -ne 1) { throw "Eligible pass must expose exactly one original level: $($pass.descriptorId)" }
    }
}

$adapter = Get-Content -Raw -LiteralPath $adapterFull | ConvertFrom-Json
Assert-Adapter $adapter
$adapterToken = Get-SafeAdapterToken ([string]$adapter.adapterId)

if (Test-Path -LiteralPath $outputFull -PathType Container) {
    $resolvedOutput = (Resolve-Path -LiteralPath $outputFull).Path.TrimEnd('\')
    if (-not $resolvedOutput.StartsWith($allowedOutputRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to replace unexpected output path: $resolvedOutput"
    }
    Remove-Item -LiteralPath $resolvedOutput -Recurse -Force
}

$modsDirectory = Join-Path $outputFull 'Mods'
[IO.Directory]::CreateDirectory($modsDirectory) | Out-Null
$constants = [Collections.Generic.List[string]]::new()
$keys = [Collections.Generic.List[string]]::new()
$definitions = [Collections.Generic.List[string]]::new()
$overrides = [Collections.Generic.List[string]]::new()
$controls = [Collections.Generic.List[object]]::new()
$copied = @{}

foreach ($pass in @($adapter.passes)) {
    $spec = Get-IntegrationSpec ([string]$pass.integration)
    $variable = '$ue4fx_' + $adapterToken.ToLowerInvariant() + '_' + $spec.Variable
    $levels = @($pass.levels)
    $originalIndex = -1
    for ($index = 0; $index -lt $levels.Count; $index++) {
        if ($null -eq (Get-LevelSource $levels[$index])) { $originalIndex = $index }
    }
    if ($originalIndex -lt 0) { throw "Original level was not found: $($pass.descriptorId)" }

    $constants.Add("global $variable = $originalIndex")
    $cycle = @($originalIndex)
    for ($index = $originalIndex - 1; $index -ge 0; $index--) { $cycle += $index }
    $keys.Add((@"
[KeyUE4FX${adapterToken}$($spec.Token)]
key = $($spec.Key)
type = cycle
smart = true
$variable = $($cycle -join ', ')
"@).Trim())

    $manifestLevels = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $levels.Count; $index++) {
        $level = $levels[$index]
        $sourceRelative = Get-LevelSource $level
        $valueProperty = $level.PSObject.Properties[$spec.ValueProperty]
        if ($null -eq $valueProperty) { throw "Level is missing '$($spec.ValueProperty)': $($pass.descriptorId) index $index" }
        $manifestLevel = [ordered]@{
            index = $index
            value = [double]$valueProperty.Value
            verification = [string]$level.verification
            original = $null -eq $sourceRelative
            source = $sourceRelative
            generatedFile = $null
            sourceSha256 = $null
        }
        if ($null -eq $sourceRelative) {
            $manifestLevels.Add([pscustomobject]$manifestLevel)
            continue
        }

        $sourceFull = Resolve-ProjectFile $sourceRelative
        if ([IO.Path]::GetExtension($sourceFull) -ine '.hlsl') { throw "Runtime source must be HLSL: $sourceRelative" }
        $expectedSourceSha = [string]$level.sourceSha256
        $actualSourceSha = Get-Sha256 $sourceFull
        if ($actualSourceSha -ne $expectedSourceSha) { throw "Source hash mismatch: $sourceRelative" }
        $destinationName = [IO.Path]::GetFileName($sourceFull)
        $destination = Join-Path $modsDirectory $destinationName
        if ($copied.ContainsKey($destinationName)) {
            if ($copied[$destinationName] -ne $actualSourceSha) { throw "Generated runtime filename collision: $destinationName" }
        } else {
            Copy-Item -LiteralPath $sourceFull -Destination $destination
            $copied[$destinationName] = $actualSourceSha
        }
        $manifestLevel.generatedFile = "Mods/$destinationName"
        $manifestLevel.sourceSha256 = $actualSourceSha

        $sectionToken = "UE4FX${adapterToken}$($spec.Token)L$index"
        if ($spec.Kind -eq 'replacement') {
            $definitions.Add((@"
[CustomShader$sectionToken]
$($pass.stage) = $destinationName
handling = skip
draw = from_caller
"@).Trim())
            $runName = "CustomShader$sectionToken"
        } else {
            if ([string]$pass.stage -ne 'cs') { throw 'Temporal post integration requires a compute shader.' }
            $outputSlot = [string]$pass.bindings.originalOutput
            $srvSlot = [string]$pass.bindings.snapshotSrv
            if ($outputSlot -notmatch '^cs-u\d+$' -or $srvSlot -notmatch '^cs-t\d+$') { throw 'Temporal post integration has invalid compute slots.' }
            $resourceName = "Resource${sectionToken}Source"
            $definitions.Add("[$resourceName]")
            $definitions.Add((@"
[CustomShader$sectionToken]
handling = skip
draw = from_caller
$resourceName = copy $outputSlot
$srvSlot = $resourceName
run = CustomShader${sectionToken}Impl
$srvSlot = null
"@).Trim())
            $definitions.Add((@"
[CustomShader${sectionToken}Impl]
cs = $destinationName
draw = from_caller
"@).Trim())
            $runName = "CustomShader$sectionToken"
        }

        $overrides.Add((@"
[ShaderOverride${sectionToken}]
hash = $($pass.shaderHash)
allow_duplicate_hash = true
if $variable == $index
    run = $runName
endif
"@).Trim())
        $manifestLevels.Add([pscustomobject]$manifestLevel)
    }

    $controls.Add([pscustomobject][ordered]@{
        descriptorId = [string]$pass.descriptorId
        shaderHash = [string]$pass.shaderHash
        stage = [string]$pass.stage
        integration = [string]$pass.integration
        variable = $variable
        key = [string]$spec.Key
        defaultIndex = $originalIndex
        levels = @($manifestLevels)
    })
}

$ini = (@"
; Generated fail-closed UE4 effects runtime.
; Source adapter: $($adapter.adapterId)
; Only live-eligible passes are emitted. Blocked passes are manifest-only.

[Constants]
$($constants -join "`r`n")

$($keys -join "`r`n`r`n")

$($definitions -join "`r`n`r`n")

$($overrides -join "`r`n`r`n")
"@ -replace "`r?`n", "`r`n").Trim() + "`r`n"
$iniPath = Join-Path $modsDirectory 'UE4EffectsGenerated.ini'
[IO.File]::WriteAllText($iniPath, $ini, $utf8)

$payloadFiles = foreach ($file in Get-ChildItem -LiteralPath $modsDirectory -File | Sort-Object Name) {
    [pscustomobject][ordered]@{
        relativePath = "Mods/$($file.Name)"
        size = $file.Length
        sha256 = Get-Sha256 $file.FullName
    }
}
$manifest = [ordered]@{
    schemaVersion = 1
    adapterId = [string]$adapter.adapterId
    renderer = [string]$adapter.renderer
    executable = $adapter.executable
    sourceAdapter = $adapterFull.Substring($repoRoot.Length + 1).Replace('\', '/')
    sourceAdapterSha256 = Get-Sha256 $adapterFull
    licensedRegexDependency = [bool]$adapter.licensedRegexDependency
    configuredPasses = [int]$adapter.configuredPasses
    emittedPasses = @($controls).Count
    blockedPasses = @($adapter.blockedPasses | ForEach-Object {
        [pscustomobject][ordered]@{
            descriptorId = [string]$_.descriptorId
            shaderHash = [string]$_.shaderHash
            reason = [string]$_.reason
            status = [string]$_.status
            liveGate = [string]$_.liveGate
        }
    })
    controls = @($controls)
    files = @($payloadFiles)
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$manifestPath = Join-Path $outputFull 'runtime-manifest.json'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 12) + [Environment]::NewLine, $utf8)

[pscustomobject]@{
    Adapter = [string]$adapter.adapterId
    EmittedPasses = @($controls).Count
    BlockedPasses = @($adapter.blockedPasses).Count
    ShaderFiles = $copied.Count
    Output = $outputFull
    IniSha256 = Get-Sha256 $iniPath
    Manifest = $manifestPath
}
