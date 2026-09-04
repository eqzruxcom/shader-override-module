[CmdletBinding()]
param(
    [string]$AcceptedFamilyRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\accepted-contact-family-rebuild-20260904-v2-portable'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\intergrade-native-light-profile-capture-pack-v1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$familyRoot = [IO.Path]::GetFullPath($AcceptedFamilyRoot).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$utf8 = [Text.UTF8Encoding]::new($false)
foreach ($path in @($familyRoot,$output)) {
    if (-not $path.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "Capture-pack paths must remain below workspace artifacts: $path" }
}
if (Test-Path -LiteralPath $output) { throw "OutputRoot already exists; preserve prior evidence: $output" }

$generationPath = Join-Path $familyRoot 'family-generation.json'
$familyIniPath = Join-Path $familyRoot 'ContactShadowFamily.ini'
foreach ($path in @($generationPath,$familyIniPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Accepted family evidence is missing: $path" }
}
$generation = Get-Content -Raw -LiteralPath $generationPath | ConvertFrom-Json
if ($generation.schemaVersion -ne 2 -or $generation.kind -ne 'ff7-remake-accepted-contact-shadow-family-generator' -or
    @($generation.variants).Count -ne 5 -or @($generation.automaticFamilies).Count -ne 3 -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $familyIniPath).Hash -ne [string]$generation.outputIniSha256 -or
    [string]$generation.outputIniSha256 -ne 'F86A81DEE319C6A6E98933D4AC99C0477B6E5D8B43E6F7D29272FDDA476B5478') {
    throw 'Accepted family-generation evidence failed its closed contract.'
}

$expectedMembers = @('08bb8764f1840179','0e97888f9a8767da','5a9fbefe0ab6f815','62b33a2d1e505241','c30cdc8365df9840')
if ((@($generation.variants.shaderHash | Sort-Object) -join '|') -cne ($expectedMembers -join '|')) { throw 'Accepted five-shader member set changed.' }
$allFamilyMembers = @($generation.automaticFamilies | ForEach-Object { @($_.members) } | Sort-Object)
if (($allFamilyMembers -join '|') -cne ($expectedMembers -join '|')) { throw 'Automatic 3+1+1 family membership changed.' }
foreach ($variant in @($generation.variants)) {
    $assembly = Join-Path $root ('working-code\Contact shadows - Rebirth Mod - Code worked\original-remake\' + [string]$variant.shaderHash + '-cs.asm')
    if (-not (Test-Path -LiteralPath $assembly -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $assembly).Hash -ne [string]$variant.originalAssemblySha256) {
        throw "Original assembly is missing or drifted: $($variant.shaderHash)"
    }
}

$classifierAssembly = Join-Path $root 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\assembly\f97a821dddaa328a-cs.asm'
$classifierSha256 = '34F3B094F719C9729ECA1E150DF134E712C1B6A3E5E87F3EB9FD6EA4CBE6F305'
if (-not (Test-Path -LiteralPath $classifierAssembly -PathType Leaf) -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $classifierAssembly).Hash -ne $classifierSha256) {
    throw 'Pinned tile classifier assembly is missing or drifted.'
}

$mods = Join-Path $output 'Mods'
[void][IO.Directory]::CreateDirectory($mods)
$iniPath = Join-Path $mods 'IntergradeNativeLightProfileCapture.ini'
$lines = [Collections.Generic.List[string]]::new()
$lines.Add('; Read-only native angular/IES-style profile activation capture.')
$lines.Add('; Generated from the accepted 3+1+1 tiled-light family; no replacement, binding, draw, dispatch, or key mutation.')
$lines.Add('; Use the existing F8 frame-analysis key beside a visibly patterned local light or the current beacon.')
$lines.Add('')
$lines.Add('[ShaderOverrideUE4FXNativeLightProfileClassifierF97]')
$lines.Add('hash = f97a821dddaa328a')
$lines.Add('allow_duplicate_hash = true')
$lines.Add('analyse_options = dump_rt dump_tex dump_cb mono desc')
$lines.Add('')
foreach ($family in @($generation.automaticFamilies)) {
    foreach ($hash in @($family.members)) {
        $sectionHash = ([string]$hash).ToUpperInvariant()
        $familySuffix = ([string]$family.name).Replace('ShaderRegexUE4FXRemakeContact','')
        $lines.Add("[ShaderOverrideUE4FXNativeLightProfile${familySuffix}${sectionHash}]")
        $lines.Add("hash = $hash")
        $lines.Add('allow_duplicate_hash = true')
        $lines.Add('analyse_options = dump_rt dump_tex dump_cb mono desc')
        $lines.Add('')
    }
}
[IO.File]::WriteAllText($iniPath,($lines -join [Environment]::NewLine) + [Environment]::NewLine,$utf8)

$families = @($generation.automaticFamilies | ForEach-Object {
    [ordered]@{ name=[string]$_.name; members=@($_.members); memberCount=@($_.members).Count }
})
$variants = @($generation.variants | Sort-Object shaderHash | ForEach-Object {
    $variant = $_
    [ordered]@{
        hash = [string]$variant.shaderHash
        stage = 'cs'
        family = [string](@($generation.automaticFamilies | Where-Object { $_.members -contains $variant.shaderHash })[0].name)
        nativeInstructionCount = [int]$variant.nativeInstructionCount
        depthBinding = [string]$variant.depth
        lightListBinding = [string]$variant.lightList
        priorLightingBinding = [string]$variant.sceneColor
        originalAssemblySha256 = [string]$variant.originalAssemblySha256
    }
})
$manifest = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    packId = 'ff7-remake-native-light-profile-activation-capture-v1'
    purpose = 'Capture native constant buffers and resources for the classifier plus the exact accepted 3+1+1 tiled-light family to prove whether a visible light activates the integrated angular-profile branch.'
    source = [ordered]@{
        acceptedFamilyGeneration = [IO.Path]::GetRelativePath($root,$generationPath).Replace('\','/')
        acceptedFamilyGenerationSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $generationPath).Hash
        acceptedFamilyIniSha256 = [string]$generation.outputIniSha256
        classifierAssembly = [IO.Path]::GetRelativePath($root,$classifierAssembly).Replace('\','/')
        classifierAssemblySha256 = $classifierSha256
    }
    classifier = [ordered]@{ hash='f97a821dddaa328a'; stage='cs'; role='tile material/light-list classifier preceding the five stable dispatch buckets' }
    automaticFamilies = $families
    variants = $variants
    capture = [ordered]@{
        trigger = 'existing F8 frame-analysis key'
        options = @('dump_rt','dump_tex','dump_cb','mono','desc')
        scene = 'visibly patterned local light preferred; current red beacon is acceptable for proving inactive-versus-active profile state'
        evidenceGoal = 'Resolve the low-two-bit native profile-enable flags and profile-row index used by the executing per-light record; do not infer activation from glow alone.'
    }
    invariants = [ordered]@{
        exactFamilyCardinality = '3+1+1'
        shaderReplacement = $false
        renderStateMutation = $false
        resourceBindingMutation = $false
        drawOrDispatchMutation = $false
        keyBinding = $false
        F10 = 'unchanged shader reload'
        F2 = 'unchanged indirect-light toggle'
        PageUp = 'unchanged foreground test cycle'
        PageDown = 'unchanged graduated master toggle'
    }
    files = @([ordered]@{ path='Mods/IntergradeNativeLightProfileCapture.ini'; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $iniPath).Hash })
    runtimeEligible = $false
    installed = $false
    liveCapturePerformed = $false
    gameFilesModified = $false
    nextGate = 'Install only through a guarded transition while the game is closed; capture one fixed scene with F8; parse dumped cb3/cb4 values before any native-light transform.'
    generatedUtc = [DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),($manifest | ConvertTo-Json -Depth 14) + [Environment]::NewLine,$utf8)
[pscustomobject]@{Result='pass';Output=$output;Families=$families.Count;Shaders=$variants.Count;Classifier=1;RenderingMutated=$false;Installed=$false}
