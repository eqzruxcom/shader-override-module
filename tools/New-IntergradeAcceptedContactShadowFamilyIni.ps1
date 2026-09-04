[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$artifactRoot = (Join-Path $repositoryRoot 'artifacts').TrimEnd('\') + '\'
if (-not $outputRoot.StartsWith($artifactRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Family output must be below workspace artifacts.'
}
if (Test-Path -LiteralPath $outputRoot) {
    throw 'Family output already exists; preserve prior evidence.'
}

$baseRoot = Join-Path $repositoryRoot 'working-code\Contact shadows - Rebirth Mod - Code worked\working-remake-port\payload\ShaderFixes'
$frustumRoot = Join-Path $repositoryRoot 'working-code\Frustum Fix\20260831-v1\accepted-runtime\ShaderFixes'
$originalRoot = Join-Path $repositoryRoot 'working-code\Contact shadows - Rebirth Mod - Code worked\original-remake'
$timelinePath = Join-Path $repositoryRoot 'docs\contact-softness-current-plan.md'
$utf8 = [Text.UTF8Encoding]::new($false)

function Get-CanonicalTextSha256([string]$Path) {
    $text = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($text)))
}

$variants = @(
    [ordered]@{ Hash='08bb8764f1840179'; Temps=31; Index='r14'; IndexComponent='w'; Diffuse='r24'; Specular='r23'; SpecularMask='xyz'; Depth='t5'; LightList='t12'; SceneColor='t9'; Instructions=657; Target='Base' },
    [ordered]@{ Hash='0e97888f9a8767da'; Temps=30; Index='r20'; IndexComponent='w'; Diffuse='r22'; Specular='r21'; SpecularMask='yzw'; Depth='t5'; LightList='t12'; SceneColor='t9'; Instructions=645; Target='Base' },
    [ordered]@{ Hash='5a9fbefe0ab6f815'; Temps=29; Index='r21'; IndexComponent='x'; Diffuse='r22'; Specular='r21'; SpecularMask='xzw'; Depth='t4'; LightList='t11'; SceneColor='t8'; Instructions=631; Target='Base' },
    [ordered]@{ Hash='62b33a2d1e505241'; Temps=24; Index='r16'; IndexComponent='w'; Diffuse='r18'; Specular='r17'; SpecularMask='yzw'; Depth='t4'; LightList='t11'; SceneColor='t8'; Instructions=478; Target='Frustum' },
    [ordered]@{ Hash='c30cdc8365df9840'; Temps=39; Index='r29'; IndexComponent='x'; Diffuse='r30'; Specular='r29'; SpecularMask='xzw'; Depth='t5'; LightList='t12'; SceneColor='t9'; Instructions=1008; Target='Base' }
)
$expectedBaseSha = @{
    '08bb8764f1840179' = 'CE61BDC44960A642348DAD91710524CA166363B10325394195B9E5101DE87939'
    '0e97888f9a8767da' = 'A0005099446203611C56438B1A4459D661F76D3B2C81C38021432A4E57E26BDD'
    '5a9fbefe0ab6f815' = '4E2E1AE9D91342D483D09FB71EEE62FF40AABC17FF8FC569F2D096E5511EB68F'
    '62b33a2d1e505241' = '55DAD282FD3690E59C076BEDB431FC73D10B99B7218C337A75E9DFB01E9B2C5C'
    'c30cdc8365df9840' = '876F6E27D7F216002C58CD4666868FE909CBFBF9169D855B73D202581BC3D5CA'
}
$expectedFrustum62bSha = 'A381CB443608CA44528B20C8BE6657B74FC2A7AB340C4C0E23282780A17A8D3D'

function Get-ComparableLines([string]$Path) {
    return @(Get-Content -LiteralPath $Path | ForEach-Object { $_.Trim() } | Where-Object {
        $_ -and
        -not $_.StartsWith('//') -and
        $_ -notmatch '^dcl_temps ' -and
        $_ -ne 'dcl_resource_texture1d (float,float,float,float) t120' -and
        $_ -ne 'dcl_tgsm_structured g0, 4, 256'
    })
}

function Get-AddedRuns([string[]]$Original, [string[]]$Modified, [string]$Label) {
    $originalIndex = 0
    $runs = [Collections.Generic.List[object]]::new()
    $run = [Collections.Generic.List[string]]::new()
    foreach ($line in $Modified) {
        if ($originalIndex -lt $Original.Count -and $line -ceq $Original[$originalIndex]) {
            if ($run.Count) {
                $runs.Add(@($run))
                $run.Clear()
            }
            $originalIndex++
        }
        else {
            $run.Add($line)
        }
    }
    if ($run.Count) { $runs.Add(@($run)) }
    if ($originalIndex -ne $Original.Count) {
        throw "Modified shader does not preserve every original instruction in order: $Label"
    }
    if ($runs.Count -ne 2 -or $runs[0].Count -ne 1) {
        throw "Unexpected insertion boundaries for ${Label}: $($runs.Count) runs"
    }
    return ,$runs
}

function Convert-AddedLine(
    [string]$Line,
    [Collections.IDictionary]$Variant,
    [ValidateSet('Index','Contact')][string]$Kind,
    [int]$TemporaryCount) {
    for ($offset = $TemporaryCount - 1; $offset -ge 0; $offset--) {
        $physicalRegister = $Variant.Temps + $offset
        $temporaryName = '${t' + $offset.ToString('00') + '}'
        $Line = [regex]::Replace($Line, '\br' + $physicalRegister + '\b', $temporaryName)
    }
    if ($Kind -eq 'Index') {
        $Line = $Line.Replace(
            $Variant.Index + '.' + $Variant.IndexComponent,
            '${light_index}.${light_index_component}')
    }
    else {
        $specularFirst = $Variant.SpecularMask.Substring(0, 1)
        $Line = $Line.Replace(
            $Variant.Specular + '.' + $specularFirst + $Variant.SpecularMask,
            '${specular}.${specular_first}${specular_mask}')
        $Line = [regex]::Replace($Line, '\b' + [regex]::Escape($Variant.Diffuse) + '(?=\.)', '${diffuse}')
        $Line = [regex]::Replace($Line, '\b' + [regex]::Escape($Variant.Specular) + '(?=\.)', '${specular}')
        $Line = [regex]::Replace(
            $Line,
            '\$\{specular\}\.' + $Variant.SpecularMask + '(?=,)',
            '${specular}.${specular_mask}')
    }
    return [regex]::Replace($Line, '\b' + [regex]::Escape($Variant.Depth) + '\b', '${depth}')
}

function Get-NormalisedTemplate(
    [string]$ModifiedPath,
    [Collections.IDictionary]$Variant,
    [int]$TemporaryCount,
    [int]$ExpectedContactLines,
    [string]$Label) {
    $originalPath = Join-Path $originalRoot ($Variant.Hash + '-cs.asm')
    $original = Get-ComparableLines -Path $originalPath
    $modified = Get-ComparableLines -Path $ModifiedPath
    $runs = Get-AddedRuns -Original $original -Modified $modified -Label $Label
    if ($runs[1].Count -ne $ExpectedContactLines) {
        throw "Unexpected contact insertion size for ${Label}: $($runs[1].Count)"
    }
    $normalisedIndex = @(foreach ($line in $runs[0]) {
        Convert-AddedLine -Line $line -Variant $Variant -Kind Index -TemporaryCount $TemporaryCount
    })
    $normalisedContact = @(foreach ($line in $runs[1]) {
        Convert-AddedLine -Line $line -Variant $Variant -Kind Contact -TemporaryCount $TemporaryCount
    })
    if ($normalisedIndex.Count -ne 1 -or
        $normalisedIndex[0] -cne 'mov ${t00}.z, ${light_index}.${light_index_component}') {
        throw "Unexpected normalised index capture for $Label"
    }
    return [ordered]@{
        text = @($normalisedIndex + $normalisedContact) -join "`n"
        originalLines = $original.Count
        modifiedLines = $modified.Count
        indexLines = $normalisedIndex.Count
        contactLines = $normalisedContact.Count
    }
}

$baseTemplates = [ordered]@{}
$variantEvidence = [Collections.Generic.List[object]]::new()
foreach ($variant in $variants) {
    $basePath = Join-Path $baseRoot ($variant.Hash + '-cs.txt')
    $originalPath = Join-Path $originalRoot ($variant.Hash + '-cs.asm')
    foreach ($requiredPath in @($basePath, $originalPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Required shader evidence is missing: $requiredPath"
        }
    }
    $baseSha = Get-CanonicalTextSha256 -Path $basePath
    if ($baseSha -ne $expectedBaseSha[$variant.Hash]) {
        throw "First-working checkpoint hash mismatch: $($variant.Hash)"
    }
    $baseTemplate = Get-NormalisedTemplate `
        -ModifiedPath $basePath `
        -Variant $variant `
        -TemporaryCount 15 `
        -ExpectedContactLines 1372 `
        -Label ($variant.Hash + '-first-working')
    $baseTemplates[$variant.Hash] = $baseTemplate.text
    $variantEvidence.Add([ordered]@{
        shaderHash = $variant.Hash
        target = $variant.Target
        nativeInstructionCount = $variant.Instructions
        originalAssemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $originalPath).Hash
        firstWorkingSha256 = $baseSha
        firstWorkingCanonicalLfSha256 = $baseSha
        firstWorkingWorkingTreeSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $basePath).Hash
        targetSha256 = if ($variant.Target -eq 'Frustum') { $expectedFrustum62bSha } else { $baseSha }
        depth = $variant.Depth
        lightList = $variant.LightList
        sceneColor = $variant.SceneColor
    })
}

$baseReference = $baseTemplates[$variants[0].Hash]
foreach ($variant in $variants) {
    if ($baseTemplates[$variant.Hash] -cne $baseReference) {
        throw "First-working insertion does not normalise to one base family: $($variant.Hash)"
    }
}
$baseTemplateLines = @($baseReference -split "`n")

$frustumVariant = $variants | Where-Object Hash -eq '62b33a2d1e505241'
$frustumPath = Join-Path $frustumRoot '62b33a2d1e505241-cs.txt'
if ((Get-CanonicalTextSha256 -Path $frustumPath) -ne $expectedFrustum62bSha) {
    throw 'Accepted 62b-only Frustum Fix hash mismatch.'
}
$frustumTemplate = Get-NormalisedTemplate `
    -ModifiedPath $frustumPath `
    -Variant $frustumVariant `
    -TemporaryCount 16 `
    -ExpectedContactLines 1971 `
    -Label '62b33a2d1e505241-frustum'
$frustumTemplateLines = @($frustumTemplate.text -split "`n")

$patternTemplate = @'
(?m)^(?P<before_index>[ \t]*uge (?P<light_index>r\d+)\.(?P<light_index_component>[xyzw]), (?P<light_loop>r\d+)\.w, r0\.w\n
^[ \t]*breakc_nz (?P=light_index)\.(?P=light_index_component)\n
^[ \t]*and (?P=light_index)\.(?P=light_index_component), (?P=light_loop)\.w, l\(-4\)\n
^[ \t]*iadd (?P=light_index)\.(?P=light_index_component), (?P=light_index)\.(?P=light_index_component), l\(16\)\n
^[ \t]*ld_structured_indexable\(structured_buffer, stride=80\)\(mixed,mixed,mixed,mixed\) (?P=light_index)\.(?P=light_index_component), r0\.x, (?P=light_index)\.(?P=light_index_component), __LIGHT_LIST__\.xxxx\n
^[ \t]*bfi (?P<light_shift>r\d+)\.(?P<light_shift_component>[xyzw]), l\(2\), l\(3\), (?P=light_loop)\.w, l\(0\)\n
^[ \t]*ushr (?P=light_index)\.(?P=light_index_component), (?P=light_index)\.(?P=light_index_component), (?P=light_shift)\.(?P=light_shift_component)\n
^[ \t]*and (?P=light_index)\.(?P=light_index_component), (?P=light_index)\.(?P=light_index_component), l\(255\)\n)
(?P<between_index_and_contact>(?:[^\n]*\n)*?
^[ \t]*mov (?P<diffuse>r\d+)\.xyz, l\(0,0,0,0\)\n
^[ \t]*mov (?P<specular>r\d+)\.(?P<specular_mask>(?P<specular_first>[xyzw])[xyzw]{2}), l\(0,0,0,0\)\n
^[ \t]*endif[ \t]*\n
^[ \t]*else[ \t]*\n
^[ \t]*mov (?P=diffuse)\.xyz, l\(0,0,0,0\)\n
^[ \t]*mov (?P=specular)\.(?P=specular_mask), l\(0,0,0,0\)\n
^[ \t]*endif[ \t]*\n)
(?P<after_contact>^[ \t]*add (?P<diffuse_accumulator>r\d+)\.xyz, (?P=diffuse_accumulator)\.xyzx, (?P=diffuse)\.xyzx\n
^[ \t]*add (?P<specular_accumulator>r\d+)\.xyz, (?P=specular_accumulator)\.xyzx, (?P=specular)\.(?P<specular_pack>[xyzw]{4})\n
^[ \t]*iadd (?P=light_loop)\.w, (?P=light_loop)\.w, l\(1\)\n
^[ \t]*endloop[ \t]*\n
^[ \t]*ult r0\.xy, r1\.xyxx, cb0\[1\]\.zwzz\n
^[ \t]*and r0\.x, r0\.y, r0\.x\n
^[ \t]*if_nz r0\.x\n
^[ \t]*ld_indexable\(texture2d\)\(float,float,float,float\) r0\.xyzw, r1\.xyzz, __SCENE_COLOR__\.xyzw\n
^[ \t]*add r2\.xyz, (?P=diffuse_accumulator)\.xyzx, (?P=specular_accumulator)\.xyzx\n
^[ \t]*dp3 r2\.w, (?P=diffuse_accumulator)\.xyzx, l\(0\.212600, 0\.715200, 0\.072200, 0\.000000\)\n
^[ \t]*mad r0\.xyzw, r0\.xyzw, cb1\[128\]\.yyyy, r2\.xyzw\n
^[ \t]*mul r0\.xyzw, r0\.xyzw, cb1\[128\]\.xxxx\n
^[ \t]*store_uav_typed u0\.xyzw, r1\.xyyy, r0\.xyzw\n
^[ \t]*endif[ \t]*\n
^[ \t]*ret[ \t]*\n)
'@

function New-Replacement([string[]]$TemplateLines, [string]$Depth) {
    $resolved = @($TemplateLines | ForEach-Object { $_.Replace('${depth}', $Depth) })
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('${before_index}' + $resolved[0] + '\n')
    $lines.Add('${between_index_and_contact}' + $resolved[1] + '\n')
    for ($index = 2; $index -lt $resolved.Count; $index++) {
        $lines.Add($resolved[$index] + '\n')
    }
    $lines.Add('${after_contact}')
    return $lines -join "`r`n"
}

function New-FamilySection(
    [string]$Name,
    [string]$Depth,
    [string]$LightList,
    [string]$SceneColor,
    [string[]]$TemplateLines,
    [int]$TemporaryCount,
    [int]$MinimumInstructions,
    [int]$MaximumInstructions,
    [string]$EnableVariable) {
    $temps = (0..($TemporaryCount - 1) | ForEach-Object { 't' + $_.ToString('00') }) -join ' '
    $requiredTextures = if ($Depth -eq 't5') {
        't0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12'
    }
    else {
        't0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11'
    }
    $pattern = $patternTemplate.Replace('__LIGHT_LIST__', $LightList).Replace('__SCENE_COLOR__', $SceneColor)
    $replacement = New-Replacement -TemplateLines $TemplateLines -Depth $Depth
    return @"
[$Name]
shader_model = cs_5_0
temps = $temps
family_mode = automatic
required_bindings = b0, b1, b2, b3, b4, s0, s1, s2, s3, $requiredTextures, u0, vThreadGroupID, vThreadIDInGroup
forbidden_bindings = t120, g0, cb13, u7
min_instructions = $MinimumInstructions
max_instructions = $MaximumInstructions
x29 = `$ue4fx_contact_edge_width_v2
y29 = `$ue4fx_contact_edge_cutoff_v2
x31 = `$ue4fx_master_injected_v1 * $EnableVariable
y31 = -1
z31 = 1
w31 = 100

[$Name.InsertDeclarations]
dcl_resource_texture1d (float,float,float,float) t120
dcl_tgsm_structured g0, 4, 256

[$Name.Pattern]
$pattern
[$Name.Pattern.Replace]
$replacement
"@
}

$header = @"
; Generated automatic equivalent of the accepted FF7 Remake contact-shadow state.
; Four variants retain the first-working Rebirth contact code; only 62b retains //Frustum Fix.
; F10 remains native reload. Page Down is the accepted-code master. Page Up and F2 remain free.
; Number row 1/2/3 independently identify the Base-T5/Base-T4/Frustum-T4 families.
[Constants]
global `$ue4fx_master_injected_v1 = 1
global `$ue4fx_contact_edge_width_v2 = 0.06
global `$ue4fx_contact_edge_cutoff_v2 = 0
global `$ue4fx_contact_base_t5_enabled_v1 = 1
global `$ue4fx_contact_base_t4_enabled_v1 = 1
global `$ue4fx_contact_frustum_t4_enabled_v1 = 1

[KeyUE4FXMasterPageDown]
key = no_modifiers VK_NEXT
type = cycle
smart = true
`$ue4fx_master_injected_v1 = 0, 1

[KeyUE4FXContactBaseT5Number1]
key = no_modifiers 1
type = cycle
smart = true
`$ue4fx_contact_base_t5_enabled_v1 = 0, 1

[KeyUE4FXContactBaseT4Number2]
key = no_modifiers 2
type = cycle
smart = true
`$ue4fx_contact_base_t4_enabled_v1 = 0, 1

[KeyUE4FXContactFrustumT4Number3]
key = no_modifiers 3
type = cycle
smart = true
`$ue4fx_contact_frustum_t4_enabled_v1 = 0, 1
"@
$sections = @(
    New-FamilySection -Name 'ShaderRegexUE4FXRemakeContactBaseT5' -Depth 't5' -LightList 't12' -SceneColor 't9' -TemplateLines $baseTemplateLines -TemporaryCount 15 -MinimumInstructions 645 -MaximumInstructions 1008 -EnableVariable '$ue4fx_contact_base_t5_enabled_v1'
    New-FamilySection -Name 'ShaderRegexUE4FXRemakeContactBaseT4' -Depth 't4' -LightList 't11' -SceneColor 't8' -TemplateLines $baseTemplateLines -TemporaryCount 15 -MinimumInstructions 631 -MaximumInstructions 631 -EnableVariable '$ue4fx_contact_base_t4_enabled_v1'
    New-FamilySection -Name 'ShaderRegexUE4FXRemakeContactFrustumT4' -Depth 't4' -LightList 't11' -SceneColor 't8' -TemplateLines $frustumTemplateLines -TemporaryCount 16 -MinimumInstructions 478 -MaximumInstructions 478 -EnableVariable '$ue4fx_contact_frustum_t4_enabled_v1'
)

[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$familyIniPath = Join-Path $outputRoot 'ContactShadowFamily.ini'
$familyText = $header + "`r`n" + ($sections -join "`r`n")
[IO.File]::WriteAllText($familyIniPath, $familyText, $utf8)

$baseTemplateSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($baseReference)))
$frustumTemplateSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($frustumTemplate.text)))
$report = [ordered]@{
    schemaVersion = 2
    kind = 'ff7-remake-accepted-contact-shadow-family-generator'
    source = 'four-first-working-rebirth-contact-plus-62b-only-left-frustum-fix'
    timeline = $timelinePath
    timelineSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $timelinePath).Hash
    baseCheckpoint = $baseRoot
    frustumCheckpoint = $frustumPath
    frustumCheckpointCanonicalLfSha256 = Get-CanonicalTextSha256 -Path $frustumPath
    frustumCheckpointWorkingTreeSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $frustumPath).Hash
    baseNormalisedTemplateSha256 = $baseTemplateSha
    frustumNormalisedTemplateSha256 = $frustumTemplateSha
    baseIndexInsertionLines = 1
    baseContactInsertionLines = 1372
    frustumIndexInsertionLines = 1
    frustumContactInsertionLines = 1971
    baseTemporaryRegisters = 15
    frustumTemporaryRegisters = 16
    automaticFamilies = @(
        [ordered]@{ name='ShaderRegexUE4FXRemakeContactBaseT5'; members=@('08bb8764f1840179','0e97888f9a8767da','c30cdc8365df9840') },
        [ordered]@{ name='ShaderRegexUE4FXRemakeContactBaseT4'; members=@('5a9fbefe0ab6f815') },
        [ordered]@{ name='ShaderRegexUE4FXRemakeContactFrustumT4'; members=@('62b33a2d1e505241') }
    )
    diagnosticKeys = [ordered]@{
        number1 = 'ShaderRegexUE4FXRemakeContactBaseT5'
        number2 = 'ShaderRegexUE4FXRemakeContactBaseT4'
        number3 = 'ShaderRegexUE4FXRemakeContactFrustumT4'
    }
    variants = @($variantEvidence)
    outputIni = $familyIniPath
    outputIniSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $familyIniPath).Hash
    liveFilesModified = $false
}
$reportPath = Join-Path $outputRoot 'family-generation.json'
[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine, $utf8)

Write-Host "FAMILY_INI=$familyIniPath"
Write-Host "REPORT=$reportPath"
Write-Host 'PASS: all five first-working shaders normalised to one base family; the accepted 62b-only Frustum Fix normalised to its guarded subtype.'
