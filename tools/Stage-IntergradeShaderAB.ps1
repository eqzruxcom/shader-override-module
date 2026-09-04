[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Status', 'Stage', 'Restore')]
    [string]$Action = 'Status',
    [ValidatePattern('^[0-9a-fA-F]{16}$')]
    [string]$ShaderHash,
    [ValidateSet('Original', 'SolidColor', 'Zero', 'Custom', 'Post')]
    [string]$Mode = 'Zero',
    [ValidateSet('ps', 'cs')]
    [string]$ShaderStage = 'ps',
    [string]$CustomShaderPath,
    [ValidatePattern('^cs-u\d+$')]
    [string]$PostSource = 'cs-u0',
    [ValidatePattern('^cs-t\d+$')]
    [string]$PostSrv = 'cs-t113',
    [ValidatePattern('^cs-t\d+$')]
    [string]$PostIniSrv,
    [string]$PostGate,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$GameRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$projectIni = Join-Path $projectPath 'runtime\Intergrade\Mods\RebirthEffectsDX11.ini'
$liveMods = Join-Path $GameRoot 'End\Binaries\Win64\Mods'
$liveIni = Join-Path $liveMods 'RebirthEffectsDX11.ini'
$stateRoot = Join-Path $projectPath 'backups\rolling-ab'
$statePath = Join-Path $stateRoot 'state.json'
$beginMarker = '; REDX11 ROLLING AB BEGIN'
$endMarker = '; REDX11 ROLLING AB END'

function Get-Sha256([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Get-State {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw "Rolling A/B state was not found: $statePath"
    }
    Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
}

function Get-SpecProperty([object]$Spec, [string]$Name) {
    if ($Spec -is [Collections.IDictionary] -and $Spec.Contains($Name)) {
        return $Spec[$Name]
    }
    $property = $Spec.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    $null
}

function New-Spec(
    [string]$Hash,
    [string]$SpecMode,
    [string]$Stage,
    [string]$CustomFile = $null,
    [string]$CustomSha256 = $null,
    [string]$PostSourceSlot = $null,
    [string]$PostSrvSlot = $null,
    [string]$PostIniSrvSlot = $null,
    [string]$PostGateExpression = $null) {
    $spec = [ordered]@{
        mode = $SpecMode
        shaderHash = $Hash.ToLowerInvariant()
        stage = $Stage.ToLowerInvariant()
    }
    if ($SpecMode -in @('Custom', 'Post')) {
        if ([string]::IsNullOrWhiteSpace($CustomFile)) { throw "$SpecMode specs require customShaderFile." }
        if ($CustomSha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw "$SpecMode specs require a SHA-256 hash." }
        $spec['customShaderFile'] = $CustomFile
        $spec['customShaderSha256'] = $CustomSha256.ToUpperInvariant()
    }
    if ($SpecMode -eq 'Post') {
        if ($Stage -ne 'cs') { throw 'Post mode currently supports compute shaders only.' }
        if ([string]::IsNullOrWhiteSpace($PostSourceSlot)) { $PostSourceSlot = 'cs-u0' }
        if ([string]::IsNullOrWhiteSpace($PostSrvSlot)) { $PostSrvSlot = 'cs-t113' }
        if (-not [string]::IsNullOrWhiteSpace($PostIniSrvSlot) -and $PostIniSrvSlot -eq $PostSrvSlot) {
            throw 'PostIniSrv must differ from PostSrv.'
        }
        $spec['postSource'] = $PostSourceSlot.ToLowerInvariant()
        $spec['postSrv'] = $PostSrvSlot.ToLowerInvariant()
        if (-not [string]::IsNullOrWhiteSpace($PostIniSrvSlot)) {
            $spec['postIniSrv'] = $PostIniSrvSlot.ToLowerInvariant()
        }
        if (-not [string]::IsNullOrWhiteSpace($PostGateExpression)) {
            if ($PostGateExpression -match '[\r\n\[\]]') { throw 'PostGate must be a single command-list expression.' }
            $spec['postGate'] = $PostGateExpression.Trim()
        }
    }
    $spec
}

function Get-SpecStage([object]$Spec) {
    $stage = Get-SpecProperty $Spec 'stage'
    if (-not [string]::IsNullOrWhiteSpace($stage)) { return ([string]$stage).ToLowerInvariant() }
    'ps'
}

function Copy-Spec([object]$Spec) {
    New-Spec -Hash ([string](Get-SpecProperty $Spec 'shaderHash')) -SpecMode ([string](Get-SpecProperty $Spec 'mode')) -Stage (Get-SpecStage $Spec) -CustomFile ([string](Get-SpecProperty $Spec 'customShaderFile')) -CustomSha256 ([string](Get-SpecProperty $Spec 'customShaderSha256')) -PostSourceSlot ([string](Get-SpecProperty $Spec 'postSource')) -PostSrvSlot ([string](Get-SpecProperty $Spec 'postSrv')) -PostIniSrvSlot ([string](Get-SpecProperty $Spec 'postIniSrv')) -PostGateExpression ([string](Get-SpecProperty $Spec 'postGate'))
}

function Get-RunName([object]$Spec) {
    $stage = Get-SpecStage $Spec
    switch ([string](Get-SpecProperty $Spec 'mode')) {
        'SolidColor' { "CustomShaderRebirthAB$($stage.ToUpperInvariant())Magenta" }
        'Zero' { "CustomShaderRebirthAB$($stage.ToUpperInvariant())Zero" }
        'Custom' {
            $sha = [string](Get-SpecProperty $Spec 'customShaderSha256')
            if ($sha.Length -lt 12) { throw 'Custom spec SHA-256 is missing or invalid.' }
            "CustomShaderRebirthAB$($stage.ToUpperInvariant())Custom$($sha.Substring(0, 12))"
        }
        'Post' {
            $sha = [string](Get-SpecProperty $Spec 'customShaderSha256')
            if ($sha.Length -lt 12) { throw 'Post spec SHA-256 is missing or invalid.' }
            $source = [string](Get-SpecProperty $Spec 'postSource')
            $srv = [string](Get-SpecProperty $Spec 'postSrv')
            $iniSrv = [string](Get-SpecProperty $Spec 'postIniSrv')
            $slotSuffix = (($source + $srv + $iniSrv) -replace '[^A-Za-z0-9]', '').ToUpperInvariant()
            "CustomShaderRebirthAB$($stage.ToUpperInvariant())Post$($sha.Substring(0, 12))$slotSuffix"
        }
        default { $null }
    }
}

function New-CustomDefinitions([object]$Previous, [object]$Current) {
    $sections = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($spec in @($Previous, $Current)) {
        $mode = [string](Get-SpecProperty $spec 'mode')
        if ($mode -notin @('Custom', 'Post')) { continue }
        $runName = Get-RunName $spec
        if (-not $seen.Add($runName)) { continue }
        $stage = Get-SpecStage $spec
        $file = [string](Get-SpecProperty $spec 'customShaderFile')
        if ($mode -eq 'Custom') {
            $sections.Add((@"
[$runName]
$stage = $file
handling = skip
draw = from_caller
"@).Trim())
            continue
        }

        $postRunName = "${runName}Impl"
        $resourceName = ($runName -replace '^CustomShader', 'Resource') + 'Source'
        $postSourceSlot = [string](Get-SpecProperty $spec 'postSource')
        $postSrvSlot = [string](Get-SpecProperty $spec 'postSrv')
        $postIniSrvSlot = [string](Get-SpecProperty $spec 'postIniSrv')
        $postGate = [string](Get-SpecProperty $spec 'postGate')
        $bindIniParams = if ([string]::IsNullOrWhiteSpace($postIniSrvSlot)) { '' } else { "$postIniSrvSlot = IniParams$([Environment]::NewLine)" }
        $unbindIniParams = if ([string]::IsNullOrWhiteSpace($postIniSrvSlot)) { '' } else { "$postIniSrvSlot = null$([Environment]::NewLine)" }
        $gateBegin = if ([string]::IsNullOrWhiteSpace($postGate)) { '' } else { "if $postGate$([Environment]::NewLine)" }
        $gateEnd = if ([string]::IsNullOrWhiteSpace($postGate)) { '' } else { 'endif' }
        $sections.Add((@"
[$resourceName]
"@).Trim())
        $sections.Add((@"
[$runName]
handling = skip
draw = from_caller
${gateBegin}$resourceName = copy $postSourceSlot
$postSrvSlot = $resourceName
${bindIniParams}run = $postRunName
${unbindIniParams}$postSrvSlot = null
${gateEnd}
"@).Trim())
        $sections.Add((@"
[$postRunName]
$stage = $file
draw = from_caller
"@).Trim())
    }
    $sections -join "`r`n`r`n"
}

function New-OverrideText([object]$Previous, [object]$Current) {
    $previousRun = Get-RunName $Previous
    $currentRun = Get-RunName $Current
    $sections = [Collections.Generic.List[string]]::new()

    if ($Previous.shaderHash -eq $Current.shaderHash -and (Get-SpecStage $Previous) -eq (Get-SpecStage $Current)) {
        if ($previousRun -and $currentRun) {
            $sections.Add(@"
[ShaderOverrideRebirthABShared]
hash = $($Current.shaderHash)
allow_duplicate_hash = true
if `$rebirth_ab_current == 0
    run = $previousRun
else
    run = $currentRun
endif
"@.Trim())
        }
        elseif ($previousRun) {
            $sections.Add(@"
[ShaderOverrideRebirthABPrevious]
hash = $($Previous.shaderHash)
allow_duplicate_hash = true
if `$rebirth_ab_current == 0
    run = $previousRun
endif
"@.Trim())
        }
        elseif ($currentRun) {
            $sections.Add(@"
[ShaderOverrideRebirthABCurrent]
hash = $($Current.shaderHash)
allow_duplicate_hash = true
if `$rebirth_ab_current == 1
    run = $currentRun
endif
"@.Trim())
        }
    }
    else {
        if ($previousRun) {
            $sections.Add(@"
[ShaderOverrideRebirthABPrevious]
hash = $($Previous.shaderHash)
allow_duplicate_hash = true
if `$rebirth_ab_current == 0
    run = $previousRun
endif
"@.Trim())
        }
        if ($currentRun) {
            $sections.Add(@"
[ShaderOverrideRebirthABCurrent]
hash = $($Current.shaderHash)
allow_duplicate_hash = true
if `$rebirth_ab_current == 1
    run = $currentRun
endif
"@.Trim())
        }
    }

    $sections -join "`r`n`r`n"
}

function New-Block([object]$Previous, [object]$Current) {
    $customDefinitions = New-CustomDefinitions $Previous $Current
    $overrides = New-OverrideText $Previous $Current
    $text = @"
$beginMarker
; F3 toggles Previous <-> Current instantly. The displayed side never affects promotion.
; Previous: $(Get-SpecStage $Previous) $($Previous.mode) $($Previous.shaderHash)
; Current: $(Get-SpecStage $Current) $($Current.mode) $($Current.shaderHash)
[KeyRebirthRollingAB]
key = no_modifiers F3
type = cycle
smart = true
`$rebirth_ab_current = 0, 1

[CustomShaderRebirthABPSMagenta]
ps = RebirthSolidColorProbe_ps.hlsl
blend = disable
handling = skip
draw = from_caller

[CustomShaderRebirthABPSZero]
ps = RebirthZeroProbe_ps.hlsl
blend = disable
handling = skip
draw = from_caller

[CustomShaderRebirthABCSMagenta]
cs = RebirthSolidColorProbe_cs.hlsl
handling = skip
draw = from_caller

[CustomShaderRebirthABCSZero]
cs = RebirthZeroProbe_cs.hlsl
handling = skip
draw = from_caller

$customDefinitions

$overrides
$endMarker
"@
    ($text -replace "`r?`n", "`r`n").Trim()
}

function Set-Block([string]$Path, [string]$Block) {
    $text = [System.IO.File]::ReadAllText($Path)
    $pattern = '(?ms)^' + [regex]::Escape($beginMarker) + '\r?\n.*?^' + [regex]::Escape($endMarker) + '\r?$'
    $matches = [regex]::Matches($text, $pattern)
    if ($matches.Count -ne 1) {
        throw "Expected one rolling A/B block in $Path, found $($matches.Count)."
    }
    $updated = [regex]::Replace($text, $pattern, $Block, 1)
    [System.IO.File]::WriteAllText($Path, $updated, [System.Text.UTF8Encoding]::new($false))
}

function Copy-ProbeShaders {
    $sourceRoot = Join-Path $projectPath 'runtime\Intergrade\Mods'
    foreach ($name in @(
        'RebirthSolidColorProbe_ps.hlsl',
        'RebirthZeroProbe_ps.hlsl',
        'RebirthSolidColorProbe_cs.hlsl',
        'RebirthZeroProbe_cs.hlsl')) {
        $source = Join-Path $sourceRoot $name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Probe shader was not found: $source"
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path $liveMods $name) -Force
    }
}

function Copy-CustomShaders([object[]]$Specs, [string]$CurrentSource) {
    $projectMods = Join-Path $projectPath 'runtime\Intergrade\Mods'
    $current = $Specs[$Specs.Count - 1]
    if ([string](Get-SpecProperty $current 'mode') -in @('Custom', 'Post')) {
        $name = [string](Get-SpecProperty $current 'customShaderFile')
        $projectTarget = Join-Path $projectMods $name
        $sourceFull = [IO.Path]::GetFullPath($CurrentSource)
        $targetFull = [IO.Path]::GetFullPath($projectTarget)
        if (-not $sourceFull.Equals($targetFull, [StringComparison]::OrdinalIgnoreCase)) {
            Copy-Item -LiteralPath $sourceFull -Destination $projectTarget -Force
        }
    }

    foreach ($spec in $Specs) {
        if ([string](Get-SpecProperty $spec 'mode') -notin @('Custom', 'Post')) { continue }
        $name = [string](Get-SpecProperty $spec 'customShaderFile')
        $expectedSha = [string](Get-SpecProperty $spec 'customShaderSha256')
        $projectSource = Join-Path $projectMods $name
        if (-not (Test-Path -LiteralPath $projectSource -PathType Leaf)) {
            throw "Cached custom shader is missing: $projectSource"
        }
        $actualSha = Get-Sha256 $projectSource
        if ($actualSha -ne $expectedSha) {
            throw "Cached custom shader hash mismatch for $name. Expected $expectedSha; got $actualSha."
        }
        Copy-Item -LiteralPath $projectSource -Destination (Join-Path $liveMods $name) -Force
    }
}

function Write-State([object]$State) {
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    [System.IO.File]::WriteAllText(
        $statePath,
        ($State | ConvertTo-Json -Depth 8) + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false))
}

if (-not (Test-Path -LiteralPath $projectIni -PathType Leaf)) { throw "Project config was not found: $projectIni" }
if (-not (Test-Path -LiteralPath $liveIni -PathType Leaf)) { throw "Live config was not found: $liveIni" }

if ($Action -eq 'Status') {
    $state = Get-State
    [pscustomobject]@{
        action = 'Status'
        key = 'F3'
        previous = $state.previous
        current = $state.current
        promotionRule = 'Previous always receives old Current; runtime F3 selection is ignored.'
        projectLiveMatch = (Get-Sha256 $projectIni) -eq (Get-Sha256 $liveIni)
        projectSha256 = Get-Sha256 $projectIni
        liveSha256 = Get-Sha256 $liveIni
        statePath = $statePath
    }
    return
}

if ($Action -eq 'Restore') {
    $state = Get-State
    $baseBackupDir = if ($state.PSObject.Properties.Name -contains 'baseBackupDir') { $state.baseBackupDir } else { $state.backupDir }
    $projectBackup = Join-Path $baseBackupDir 'project.before.ini'
    $liveBackup = Join-Path $baseBackupDir 'live.before.ini'
    if (-not (Test-Path -LiteralPath $projectBackup -PathType Leaf)) { throw "Base project backup was not found: $projectBackup" }
    if (-not (Test-Path -LiteralPath $liveBackup -PathType Leaf)) { throw "Base live backup was not found: $liveBackup" }
    if ($PSCmdlet.ShouldProcess($liveIni, 'Restore the configuration from before rolling A/B was installed')) {
        Copy-Item -LiteralPath $projectBackup -Destination $projectIni -Force
        Copy-Item -LiteralPath $liveBackup -Destination $liveIni -Force
        $state.status = 'restored'
        $state | Add-Member -NotePropertyName restoredAtUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
        Write-State $state
    }
    [pscustomobject]@{ action = 'Restore'; restored = $true; projectLiveMatch = (Get-Sha256 $projectIni) -eq (Get-Sha256 $liveIni) }
    return
}

if ([string]::IsNullOrWhiteSpace($ShaderHash)) { throw '-ShaderHash is required for Stage.' }
$customSource = $null
$customFile = $null
$customSha256 = $null
if ($Mode -in @('Custom', 'Post')) {
    if ([string]::IsNullOrWhiteSpace($CustomShaderPath)) { throw "-CustomShaderPath is required for $Mode mode." }
    $customSource = (Resolve-Path -LiteralPath $CustomShaderPath).Path
    if (-not (Test-Path -LiteralPath $customSource -PathType Leaf)) { throw "Custom shader was not found: $customSource" }
    if ([IO.Path]::GetExtension($customSource) -ine '.hlsl') {
        throw 'Custom and Post modes require HLSL source (.hlsl), not a compiled shader object.'
    }
    $header = [IO.File]::ReadAllBytes($customSource)
    if ($header.Length -ge 4 -and $header[0] -eq 0x44 -and $header[1] -eq 0x58 -and $header[2] -eq 0x42 -and $header[3] -eq 0x43) {
        throw 'Custom shader input contains a DXBC binary header; provide HLSL source instead.'
    }
    $customSha256 = Get-Sha256 $customSource
    $customFile = "RebirthAB${Mode}_$($customSha256.Substring(0, 16))_$ShaderStage.hlsl"
} elseif (-not [string]::IsNullOrWhiteSpace($CustomShaderPath)) {
    throw '-CustomShaderPath is only valid with Custom or Post mode.'
}
$oldState = Get-State
$previous = Copy-Spec $oldState.current
$current = New-Spec $ShaderHash $Mode $ShaderStage $customFile $customSha256 $PostSource $PostSrv $PostIniSrv $PostGate
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$backupDir = Join-Path $stateRoot $timestamp
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
Copy-Item -LiteralPath $projectIni -Destination (Join-Path $backupDir 'project.before.ini') -Force
Copy-Item -LiteralPath $liveIni -Destination (Join-Path $backupDir 'live.before.ini') -Force
$block = New-Block $previous $current

if ($PSCmdlet.ShouldProcess($liveIni, "Stage Current $ShaderStage $Mode $($current.shaderHash), promoting old Current to Previous")) {
    Copy-ProbeShaders
    Copy-CustomShaders -Specs @($previous, $current) -CurrentSource $customSource
    Set-Block $projectIni $block
    Set-Block $liveIni $block
}

$baseBackupDir = if ($oldState.PSObject.Properties.Name -contains 'baseBackupDir') { $oldState.baseBackupDir } else { $oldState.backupDir }
$newState = [ordered]@{
    schemaVersion = 8
    status = 'staged-awaiting-f10'
    key = 'F3'
    previous = $previous
    current = $current
    promotionRule = 'Previous receives old Current regardless of which side F3 displays.'
    baseBackupDir = $baseBackupDir
    lastStageBackupDir = $backupDir
    projectIniSha256 = Get-Sha256 $projectIni
    liveIniSha256 = Get-Sha256 $liveIni
    stagedAtUtc = [DateTime]::UtcNow.ToString('o')
}
Write-State $newState

[pscustomobject]@{
    action = 'Stage'
    previous = $previous
    current = $current
    promotionInvariantSatisfied = (
        $previous.mode -eq $oldState.current.mode -and
        $previous.shaderHash -eq $oldState.current.shaderHash -and
        $previous.stage -eq (Get-SpecStage $oldState.current))
    projectLiveMatch = $newState.projectIniSha256 -eq $newState.liveIniSha256
    reloadRequired = $true
    key = 'F3'
    statePath = $statePath
    backupDir = $backupDir
}