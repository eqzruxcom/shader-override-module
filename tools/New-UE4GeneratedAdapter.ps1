[CmdletBinding()]
param(
    [string]$BindingPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Adapters\FF7RemakeIntergrade\adapter-bindings.json'),
    [string]$SemanticReport = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ue4-semantic-all-captured.json'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\generated-adapters\FF7RemakeIntergrade')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')

function Resolve-WorkspacePath([string]$Path) {
    $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $repoRoot ($Path -replace '/', '\'))) }
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must remain inside the project workspace: $full"
    }
    $full
}

function Assert-PropertySet([object]$Object, [string[]]$Required, [string[]]$Allowed, [string]$Context) {
    $names = @($Object.PSObject.Properties.Name)
    foreach ($name in $Required) {
        if ($names -notcontains $name) { throw "$Context is missing required property '$name'." }
    }
    foreach ($name in $names) {
        if ($Allowed -notcontains $name) { throw "$Context contains unsupported property '$name'." }
    }
}

function Assert-Near([double]$Actual, [double]$Expected, [string]$Context) {
    if ([Math]::Abs($Actual - $Expected) -gt 0.000001) {
        throw "$Context mismatch: expected $Expected, got $Actual."
    }
}

$bindingFull = (Resolve-Path -LiteralPath $BindingPath).Path
$reportFull = (Resolve-Path -LiteralPath $SemanticReport).Path
$outputFull = Resolve-WorkspacePath $OutputDirectory
$binding = Get-Content -Raw -LiteralPath $bindingFull | ConvertFrom-Json
$report = Get-Content -Raw -LiteralPath $reportFull | ConvertFrom-Json

Assert-PropertySet $binding @('schemaVersion','adapterId','game','engineFamily','renderer','executable','passes') @('schemaVersion','adapterId','game','engineFamily','renderer','executable','passes') 'adapter binding'
if ([int]$binding.schemaVersion -ne 1) { throw 'Adapter binding schemaVersion must be 1.' }
if ([string]$binding.renderer -ne 'D3D11') { throw 'Only D3D11 adapter bindings are currently supported.' }
if ([string]$binding.executable.sha256 -notmatch '^[0-9A-F]{64}$') { throw 'Executable SHA-256 is invalid.' }
if ($report.licensedRegexDependency -ne $false) { throw 'Semantic report depends on licensed regex input.' }
if (@($report.matchTimeouts).Count) { throw 'Semantic report contains regex timeouts.' }

$generatedPasses = [Collections.Generic.List[object]]::new()
$blockedPasses = [Collections.Generic.List[object]]::new()
$seenDescriptors = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($pass in @($binding.passes)) {
    Assert-PropertySet $pass @('descriptorId','integration','stage','shaderHash','bindings','controlPack','evidence') @('descriptorId','integration','stage','shaderHash','bindings','controlPack','evidence') "adapter pass $($pass.descriptorId)"
    if (-not $seenDescriptors.Add([string]$pass.descriptorId)) { throw "Duplicate adapter descriptor '$($pass.descriptorId)'." }
    if ([string]$pass.shaderHash -notmatch '^[0-9a-f]{16}$') { throw "Invalid shader hash for $($pass.descriptorId)." }

    $descriptorRecord = @($report.descriptors | Where-Object id -eq $pass.descriptorId)
    if ($descriptorRecord.Count -ne 1) { throw "Expected one descriptor record for $($pass.descriptorId), found $($descriptorRecord.Count)." }
    $descriptorPath = (Resolve-Path -LiteralPath ([string]$descriptorRecord[0].file)).Path
    $descriptorHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $descriptorPath).Hash
    if ($descriptorHash -ne [string]$descriptorRecord[0].sha256) { throw "Semantic report is stale for descriptor $($pass.descriptorId)." }
    $descriptor = Get-Content -Raw -LiteralPath $descriptorPath | ConvertFrom-Json

    $semanticMatch = @($report.matches | Where-Object {
        $_.descriptor -eq $pass.descriptorId -and $_.hash -eq $pass.shaderHash -and $_.stage -eq $pass.stage
    })
    if ($semanticMatch.Count -ne 1) { throw "Expected one semantic match for $($pass.descriptorId) $($pass.shaderHash), found $($semanticMatch.Count)." }
    if (@($semanticMatch[0].evidence | Where-Object { -not $_.satisfied }).Count) { throw "Semantic match has unsatisfied evidence for $($pass.descriptorId)." }

    $controlPackPath = Resolve-WorkspacePath ([string]$pass.controlPack)
    if (-not (Test-Path -LiteralPath $controlPackPath -PathType Leaf)) { throw "Control pack is missing: $controlPackPath" }
    $controlPack = Get-Content -Raw -LiteralPath $controlPackPath | ConvertFrom-Json
    if ($controlPack.semanticDescriptor -ne $pass.descriptorId -or $controlPack.shaderHash -ne $pass.shaderHash) {
        throw "Control pack identity does not match $($pass.descriptorId)."
    }
    $eligibilityProperty = $controlPack.PSObject.Properties['runtimeAdapterEligible']
    if ($null -ne $eligibilityProperty -and $eligibilityProperty.Value -isnot [bool]) {
        throw "Control-pack runtimeAdapterEligible must be boolean for $($pass.descriptorId)."
    }
    $runtimeAdapterEligible = if ($null -eq $eligibilityProperty) { $true } else { [bool]$eligibilityProperty.Value }
    if ($runtimeAdapterEligible -and $null -ne $eligibilityProperty) {
        if ([string]$controlPack.status -notmatch '^live-verified') {
            throw "Runtime-eligible control pack lacks live-verified status for $($pass.descriptorId)."
        }
        if ([string]$controlPack.liveGate -notmatch '^Passed:') {
            throw "Runtime-eligible control pack lacks a passed live gate for $($pass.descriptorId)."
        }
        $liveLevels = @($controlPack.levels | Where-Object { [string]$_.verification -like 'live-verified*' })
        if ($liveLevels.Count -lt 2) {
            throw "Runtime-eligible control pack needs at least two live-verified levels for $($pass.descriptorId)."
        }
        foreach ($level in $liveLevels) {
            if ([string]::IsNullOrWhiteSpace([string]$level.liveEvidence)) {
                throw "Runtime-eligible control pack has a live-verified level without evidence for $($pass.descriptorId)."
            }
            $liveEvidencePath = Resolve-WorkspacePath ([string]$level.liveEvidence)
            if (-not (Test-Path -LiteralPath $liveEvidencePath -PathType Leaf)) {
                throw "Runtime live-evidence file is missing for $($pass.descriptorId): $liveEvidencePath"
            }
        }
    }

    $evidenceRequired = @('shaderMap','passId')
    $evidenceAllowed = @('shaderMap','passId')
    if ([string]$pass.integration -eq 'temporal-volume-post') {
        $evidenceRequired += 'temporalBlendContract'
        $evidenceAllowed += 'temporalBlendContract'
    }
    Assert-PropertySet $pass.evidence $evidenceRequired $evidenceAllowed "evidence for $($pass.descriptorId)"

    $shaderMapPath = Resolve-WorkspacePath ([string]$pass.evidence.shaderMap)
    $shaderMap = Get-Content -Raw -LiteralPath $shaderMapPath | ConvertFrom-Json
    $mapPass = @($shaderMap.passes | Where-Object id -eq $pass.evidence.passId)
    if ($mapPass.Count -ne 1) { throw "Shader-map pass '$($pass.evidence.passId)' was not found exactly once." }
    if ($mapPass[0].stage -ne $pass.stage -or @($mapPass[0].hashes) -notcontains $pass.shaderHash) {
        throw "Shader-map identity mismatch for $($pass.descriptorId)."
    }

    $bindings = $pass.bindings
    switch ([string]$pass.integration) {
        'temporal-volume-post' {
            Assert-PropertySet $bindings @('originalOutput','snapshotSrv','threadGroup','temporalCurrentWeight','temporalHistoryWeight') @('originalOutput','snapshotSrv','threadGroup','gridResolution','temporalCurrentWeight','temporalHistoryWeight') "bindings for $($pass.descriptorId)"
            $outputSlot = ([string]$bindings.originalOutput -replace '^cs-','')
            $mapOutput = @($mapPass[0].renderTargets | Where-Object slot -eq $outputSlot)
            if ($mapOutput.Count -ne 1 -or $mapOutput[0].dimension -ne 'RWTexture3D') { throw "Shader-map output binding mismatch for $($pass.descriptorId)." }
            if ($controlPack.wrapperContract.copySource -ne $bindings.originalOutput -or $controlPack.wrapperContract.bindSnapshot -ne $bindings.snapshotSrv) { throw "Control-pack wrapper binding mismatch for $($pass.descriptorId)." }
            Assert-Near ([double]$bindings.temporalCurrentWeight) ([double]$descriptor.runtimeContract.temporalCurrentWeight) 'descriptor current weight'
            Assert-Near ([double]$bindings.temporalHistoryWeight) ([double]$descriptor.runtimeContract.temporalHistoryWeight) 'descriptor history weight'
            Assert-Near ([double]$bindings.temporalCurrentWeight) ([double]$mapPass[0].temporalBlend.currentWeight) 'shader-map current weight'
            Assert-Near ([double]$bindings.temporalHistoryWeight) ([double]$mapPass[0].temporalBlend.historyWeight) 'shader-map history weight'
            Assert-Near ([double]$bindings.temporalCurrentWeight) ([double]$controlPack.temporalBlend.current) 'control-pack current weight'
            Assert-Near ([double]$bindings.temporalHistoryWeight) ([double]$controlPack.temporalBlend.history) 'control-pack history weight'
            $contractPath = Resolve-WorkspacePath ([string]$pass.evidence.temporalBlendContract)
            if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) { throw "Temporal blend contract is missing for $($pass.descriptorId): $contractPath" }
            $temporalContract = Get-Content -Raw -LiteralPath $contractPath | ConvertFrom-Json
            if ([string]$temporalContract.analyzer -ne 'independent-temporal-blend-contract') { throw "Temporal blend contract analyzer mismatch for $($pass.descriptorId)." }
            if ([string]$temporalContract.shader.hash -ne [string]$pass.shaderHash -or [string]$temporalContract.shader.stage -ne [string]$pass.stage) { throw "Temporal blend contract identity mismatch for $($pass.descriptorId)." }
            $contractSourcePath = Resolve-WorkspacePath ([string]$temporalContract.shader.source)
            if (-not (Test-Path -LiteralPath $contractSourcePath -PathType Leaf)) { throw "Temporal blend contract source is missing for $($pass.descriptorId): $contractSourcePath" }
            if ((Get-FileHash -Algorithm SHA256 -LiteralPath $contractSourcePath).Hash -ne [string]$temporalContract.shader.sourceSha256) { throw "Temporal blend contract source hash mismatch for $($pass.descriptorId)." }
            if ([string]$temporalContract.temporalBlend.status -ne 'fixed' -or $temporalContract.temporalBlend.steadyStateCompensationEligible -ne $true) { throw "Temporal blend contract is not fixed and compensation-eligible for $($pass.descriptorId)." }
            Assert-Near ([double]$bindings.temporalCurrentWeight) ([double]$temporalContract.temporalBlend.currentWeight) 'temporal-contract current weight'
            Assert-Near ([double]$bindings.temporalHistoryWeight) ([double]$temporalContract.temporalBlend.historyWeight) 'temporal-contract history weight'
            $descriptorThreads = @($descriptor.runtimeContract.verifiedThreadGroup | ForEach-Object { [int]$_ })
            $bindingThreads = @($bindings.threadGroup | ForEach-Object { [int]$_ })
            if (($descriptorThreads -join ',') -ne ($bindingThreads -join ',')) { throw "Thread-group mismatch for $($pass.descriptorId)." }
            if ($null -ne $bindings.gridResolution) {
                $mapGrid = [string]$mapOutput[0].derivedGridResolution
                if (($bindings.gridResolution -join 'x') -ne $mapGrid) { throw "Grid-resolution mismatch for $($pass.descriptorId)." }
            }
        }
        'scene-saturation-replacement' {
            if ($pass.stage -ne 'ps') { throw 'Scene-saturation integration requires a pixel shader.' }
            Assert-PropertySet $bindings @('sceneColorInput','auxiliaryInputs','constantBuffers','output','alphaBehavior') @('sceneColorInput','auxiliaryInputs','constantBuffers','output','alphaBehavior') "bindings for $($pass.descriptorId)"
            if ($bindings.sceneColorInput -ne 'ps-t0' -or (@($bindings.auxiliaryInputs) -join ',') -ne 'ps-t1,ps-t2' -or (@($bindings.constantBuffers) -join ',') -ne 'ps-cb0,ps-cb1' -or $bindings.alphaBehavior -ne 'zero') { throw "Scene-saturation binding contract mismatch for $($pass.descriptorId)." }
            $outputSlot = ([string]$bindings.output -replace '^ps-','')
            $mapOutput = @($mapPass[0].renderTargets | Where-Object slot -eq $outputSlot)
            if ($mapOutput.Count -ne 1) { throw "Shader-map output binding mismatch for $($pass.descriptorId)." }
            foreach ($input in @('t0','t1','t2','cb0','cb1')) {
                if (@($controlPack.passContract.inputs) -notcontains $input) { throw "Control-pack input binding mismatch for $($pass.descriptorId): $input" }
            }
            if ($controlPack.passContract.output -ne 'SV_Target0' -or $controlPack.passContract.preserveAlphaBehavior -ne 'o0.w = 0') { throw "Control-pack output contract mismatch for $($pass.descriptorId)." }
            if ($controlPack.formula -ne $descriptor.runtimeContract.postControlSynthesis.formula) { throw "Scene-saturation formula mismatch for $($pass.descriptorId)." }
            for ($index = 0; $index -lt 3; $index++) { Assert-Near ([double]$controlPack.luminanceWeights[$index]) ([double]$descriptor.runtimeContract.postControlSynthesis.luminanceWeights[$index]) "luminance weight $index" }
            if ($mapPass[0].controlIntegration.controlPack -ne [string]$pass.controlPack) { throw "Shader-map control-pack reference mismatch for $($pass.descriptorId)." }
        }
        'packed-ao-strength-replacement' {
            if ($pass.stage -ne 'ps') { throw 'Packed AO-strength integration requires a pixel shader.' }
            Assert-PropertySet $bindings @('output','controlledChannels','preservedChannels','neutralVisibility') @('output','controlledChannels','preservedChannels','neutralVisibility') "bindings for $($pass.descriptorId)"
            $outputSlot = ([string]$bindings.output -replace '^ps-','')
            $mapOutput = @($mapPass[0].renderTargets | Where-Object slot -eq $outputSlot)
            if ($mapOutput.Count -ne 1) { throw "Shader-map output binding mismatch for $($pass.descriptorId)." }
            if ((@($bindings.controlledChannels) -join ',') -ne 'x,y' -or (@($bindings.preservedChannels) -join ',') -ne 'z,w') { throw "AO binding channel contract mismatch for $($pass.descriptorId)." }
            if ((@($controlPack.controlledChannels) -join ',') -ne (@($bindings.controlledChannels) -join ',') -or (@($controlPack.preservedChannels) -join ',') -ne (@($bindings.preservedChannels) -join ',')) { throw "AO control-pack channel contract mismatch for $($pass.descriptorId)." }
            Assert-Near ([double]$bindings.neutralVisibility) ([double]$controlPack.neutralVisibility) 'AO neutral visibility'
            if ($controlPack.formula -ne 'xy = lerp(1.0, original.xy, strength); zw = original.zw') { throw "AO control formula mismatch for $($pass.descriptorId)." }
            if ($mapPass[0].controlIntegration.controlPack -ne [string]$pass.controlPack) { throw "Shader-map control-pack reference mismatch for $($pass.descriptorId)." }
        }
        'ssr-radiance-strength-replacement' {
            if ($pass.stage -ne 'ps') { throw 'SSR radiance-strength integration requires a pixel shader.' }
            Assert-PropertySet $bindings @('output','controlledChannels','preservedChannels','alphaBehavior') @('output','controlledChannels','preservedChannels','alphaBehavior') "bindings for $($pass.descriptorId)"
            $outputSlot = ([string]$bindings.output -replace '^ps-','')
            $mapOutput = @($mapPass[0].renderTargets | Where-Object slot -eq $outputSlot)
            if ($mapOutput.Count -ne 1) { throw "Shader-map output binding mismatch for $($pass.descriptorId)." }
            if ((@($bindings.controlledChannels) -join ',') -ne 'x,y,z' -or (@($bindings.preservedChannels) -join ',') -ne 'w' -or $bindings.alphaBehavior -ne 'preserve') { throw "SSR binding channel contract mismatch for $($pass.descriptorId)." }
            if ((@($controlPack.controlledChannels) -join ',') -ne (@($bindings.controlledChannels) -join ',') -or (@($controlPack.preservedChannels) -join ',') -ne (@($bindings.preservedChannels) -join ',')) { throw "SSR control-pack channel contract mismatch for $($pass.descriptorId)." }
            if ($controlPack.formula -ne 'rgb = original.rgb * strength; a = original.a') { throw "SSR control formula mismatch for $($pass.descriptorId)." }
            if ($mapPass[0].controlIntegration.controlPack -ne [string]$pass.controlPack) { throw "Shader-map control-pack reference mismatch for $($pass.descriptorId)." }
        }
        'ssr-composite-strength-replacement' {
            if ($pass.stage -ne 'ps') { throw 'SSR composite-strength integration requires a pixel shader.' }
            Assert-PropertySet $bindings @('ssrInput','reflectionEnvironmentInput','output','controlledTerm','preserveHitMask') @('ssrInput','reflectionEnvironmentInput','output','controlledTerm','preserveHitMask') "bindings for $($pass.descriptorId)"
            if ($bindings.ssrInput -ne 'ps-t11' -or $bindings.reflectionEnvironmentInput -ne 'ps-t10' -or $bindings.output -ne 'ps-o0' -or $bindings.controlledTerm -ne 'additive-ssr-radiance-rgb' -or $bindings.preserveHitMask -ne $true) { throw "SSR composite binding contract mismatch for $($pass.descriptorId)." }
            $ssrSlot = ([string]$bindings.ssrInput -replace '^ps-','')
            $environmentSlot = ([string]$bindings.reflectionEnvironmentInput -replace '^ps-','')
            $outputSlot = ([string]$bindings.output -replace '^ps-','')
            $mapSsr = @($mapPass[0].resources | Where-Object slot -eq $ssrSlot)
            $mapEnvironment = @($mapPass[0].resources | Where-Object slot -eq $environmentSlot)
            $mapOutput = @($mapPass[0].renderTargets | Where-Object slot -eq $outputSlot)
            if ($mapSsr.Count -ne 1 -or $mapSsr[0].dimension -ne 'Texture2D' -or $mapEnvironment.Count -ne 1 -or $mapEnvironment[0].dimension -ne 'TextureCubeArray' -or $mapOutput.Count -ne 1) { throw "Shader-map SSR composite binding mismatch for $($pass.descriptorId)." }
            if ($controlPack.formula -ne $descriptor.runtimeContract.strengthControlFormula) { throw "SSR composite control formula mismatch for $($pass.descriptorId)." }
            if ($controlPack.controlledTerm -ne $descriptor.runtimeContract.strengthControl.controlledTerm) { throw "SSR composite controlled-term mismatch for $($pass.descriptorId)." }
            foreach ($requiredTerm in @($descriptor.runtimeContract.strengthControl.requiredPreservedTerms)) {
                if (@($controlPack.preservedTerms) -notcontains $requiredTerm) { throw "SSR composite preserved-term mismatch for $($pass.descriptorId): $requiredTerm" }
            }
            if ($mapPass[0].discoveryHints.strengthControlPack -ne [string]$pass.controlPack) { throw "Shader-map strength-control reference mismatch for $($pass.descriptorId)." }
            $resourceFlowEvidence = Resolve-WorkspacePath ([string]$controlPack.resourceFlowEvidence)
            if (-not (Test-Path -LiteralPath $resourceFlowEvidence -PathType Leaf)) { throw "SSR composite resource-flow evidence is missing for $($pass.descriptorId): $resourceFlowEvidence" }
            $variantIsolationPath = Resolve-WorkspacePath ([string]$controlPack.variantIsolationReport)
            if (-not (Test-Path -LiteralPath $variantIsolationPath -PathType Leaf)) { throw "SSR composite variant-isolation report is missing for $($pass.descriptorId): $variantIsolationPath" }
            $variantIsolation = Get-Content -Raw -LiteralPath $variantIsolationPath | ConvertFrom-Json
            if ($variantIsolation.shaderHash -ne $pass.shaderHash -or $variantIsolation.stage -ne $pass.stage -or $variantIsolation.result -ne 'pass' -or $variantIsolation.uniqueNormalizedBodies -ne 1 -or @($variantIsolation.levels).Count -ne 5) { throw "SSR composite variant-isolation evidence mismatch for $($pass.descriptorId)." }
        }
        default { throw "Unsupported adapter integration '$($pass.integration)'." }
    }

    if (-not $runtimeAdapterEligible) {
        $blockedPasses.Add([ordered]@{
            descriptorId = [string]$pass.descriptorId
            shaderHash = [string]$pass.shaderHash
            stage = [string]$pass.stage
            integration = [string]$pass.integration
            reason = 'control-pack-runtime-adapter-ineligible'
            controlPack = [string]$pass.controlPack
            controlPackSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $controlPackPath).Hash
            status = [string]$controlPack.status
            liveGate = [string]$controlPack.liveGate
        })
        continue
    }
    $generatedEvidence = [ordered]@{
        shaderMap = [string]$pass.evidence.shaderMap
        shaderMapSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $shaderMapPath).Hash
        passId = [string]$pass.evidence.passId
    }
    if ([string]$pass.integration -eq 'temporal-volume-post') {
        $generatedEvidence.temporalBlendContract = [string]$pass.evidence.temporalBlendContract
        $generatedEvidence.temporalBlendContractSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $contractPath).Hash
    }
    $generatedPasses.Add([ordered]@{
        descriptorId = [string]$pass.descriptorId
        descriptorSha256 = $descriptorHash
        integration = [string]$pass.integration
        shaderHash = [string]$pass.shaderHash
        stage = [string]$pass.stage
        semanticChecksPassed = [int]$semanticMatch[0].semanticChecksPassed
        bindings = $bindings
        controlPack = [string]$pass.controlPack
        controlPackSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $controlPackPath).Hash
        levels = @($controlPack.levels)
        evidence = $generatedEvidence
    })
}

New-Item -ItemType Directory -Path $outputFull -Force | Out-Null
$generated = [ordered]@{
    schemaVersion = 1
    adapterId = [string]$binding.adapterId
    game = [string]$binding.game
    engineFamily = [string]$binding.engineFamily
    renderer = [string]$binding.renderer
    executable = $binding.executable
    sourceBindingSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $bindingFull).Hash
    sourceSemanticReportSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $reportFull).Hash
    licensedRegexDependency = $false
    configuredPasses = @($binding.passes).Count
    passes = @($generatedPasses)
    blockedPasses = @($blockedPasses)
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$outputPath = Join-Path $outputFull 'adapter.json'
[IO.File]::WriteAllText($outputPath,(($generated | ConvertTo-Json -Depth 12)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Adapter = [string]$binding.adapterId
    Passes = $generatedPasses.Count
    BlockedPasses = $blockedPasses.Count
    Output = $outputPath
    Sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash
}
