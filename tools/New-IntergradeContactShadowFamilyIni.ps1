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

$acceptedRoot = Join-Path $repositoryRoot 'working-code\Frustum Fix\20260831-v1\accepted-runtime\ShaderFixes'
$originalRoot = Join-Path $repositoryRoot 'working-code\Contact shadows - Rebirth Mod - Code worked\original-remake'
$checkpointManifestPath = Join-Path $repositoryRoot 'working-code\Frustum Fix\20260831-v1\manifest.json'
$auditIniPath = Join-Path $repositoryRoot 'src\Adapters\FF7RemakeIntergrade\ContactShadowFamilyAudit.ini'
$utf8 = [Text.UTF8Encoding]::new($false)

$variants = @(
    [ordered]@{ Hash='08bb8764f1840179'; Temps=31; Index='r14'; IndexComponent='w'; Diffuse='r24'; Specular='r23'; SpecularMask='xyz'; Depth='t5'; LightList='t12'; SceneColor='t9' },
    [ordered]@{ Hash='0e97888f9a8767da'; Temps=30; Index='r20'; IndexComponent='w'; Diffuse='r22'; Specular='r21'; SpecularMask='yzw'; Depth='t5'; LightList='t12'; SceneColor='t9' },
    [ordered]@{ Hash='5a9fbefe0ab6f815'; Temps=29; Index='r21'; IndexComponent='x'; Diffuse='r22'; Specular='r21'; SpecularMask='xzw'; Depth='t4'; LightList='t11'; SceneColor='t8' },
    [ordered]@{ Hash='62b33a2d1e505241'; Temps=24; Index='r16'; IndexComponent='w'; Diffuse='r18'; Specular='r17'; SpecularMask='yzw'; Depth='t4'; LightList='t11'; SceneColor='t8' },
    [ordered]@{ Hash='c30cdc8365df9840'; Temps=39; Index='r29'; IndexComponent='x'; Diffuse='r30'; Specular='r29'; SpecularMask='xzw'; Depth='t5'; LightList='t12'; SceneColor='t9' }
)

function Get-InstructionLines([string]$Path, [switch]$Comparable) {
    $lines = @(Get-Content -LiteralPath $Path | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('//') })
    if ($Comparable) {
        $lines = @($lines | Where-Object {
            $_ -notmatch '^dcl_temps ' -and
            $_ -ne 'dcl_resource_texture1d (float,float,float,float) t120' -and
            $_ -ne 'dcl_tgsm_structured g0, 4, 256'
        })
    }
    return ,$lines
}

function Get-AddedRuns([string[]]$Original, [string[]]$Accepted, [string]$Hash) {
    $originalIndex = 0
    $runs = [Collections.Generic.List[object]]::new()
    $run = [Collections.Generic.List[string]]::new()
    foreach ($line in $Accepted) {
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
    if ($run.Count) {
        $runs.Add(@($run))
    }
    if ($originalIndex -ne $Original.Count) {
        throw "Accepted shader does not preserve every original instruction in order: $Hash"
    }
    if ($runs.Count -ne 2 -or $runs[0].Count -ne 1 -or $runs[1].Count -ne 1971) {
        throw "Unexpected accepted insertion layout for ${Hash}: $($runs.Count) runs"
    }
    return ,$runs
}

function Convert-AddedLine(
    [string]$Line,
    [Collections.IDictionary]$Variant,
    [ValidateSet('Index','Contact')][string]$Kind) {
    for ($offset = 15; $offset -ge 0; $offset--) {
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
        $Line = [regex]::Replace(
            $Line,
            '\b' + [regex]::Escape($Variant.Diffuse) + '(?=\.)',
            '${diffuse}')
        $Line = [regex]::Replace(
            $Line,
            '\b' + [regex]::Escape($Variant.Specular) + '(?=\.)',
            '${specular}')
        $Line = [regex]::Replace(
            $Line,
            '\$\{specular\}\.' + $Variant.SpecularMask + '(?=,)',
            '${specular}.${specular_mask}')
    }

    $Line = [regex]::Replace(
        $Line,
        '\b' + [regex]::Escape($Variant.Depth) + '\b',
        '${depth}')
    return $Line
}

$checkpoint = Get-Content -Raw -LiteralPath $checkpointManifestPath | ConvertFrom-Json
$normalisedTemplates = [ordered]@{}
$variantEvidence = [Collections.Generic.List[object]]::new()
foreach ($variant in $variants) {
    $acceptedPath = Join-Path $acceptedRoot ($variant.Hash + '-cs.txt')
    $originalPath = Join-Path $originalRoot ($variant.Hash + '-cs.asm')
    foreach ($requiredPath in @($acceptedPath, $originalPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Required shader evidence is missing: $requiredPath"
        }
    }

    $manifestRelativePath = 'accepted-runtime\ShaderFixes\' + $variant.Hash + '-cs.txt'
    $checkpointEntry = @($checkpoint.files | Where-Object { $_.path -eq $manifestRelativePath })
    $acceptedSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $acceptedPath).Hash
    if ($checkpointEntry.Count -ne 1 -or $checkpointEntry[0].sha256 -ne $acceptedSha) {
        throw "Accepted checkpoint hash mismatch: $($variant.Hash)"
    }

    $original = Get-InstructionLines -Path $originalPath -Comparable
    $accepted = Get-InstructionLines -Path $acceptedPath -Comparable
    $runs = Get-AddedRuns -Original $original -Accepted $accepted -Hash $variant.Hash
    $normalisedIndex = @(foreach ($line in $runs[0]) {
        Convert-AddedLine -Line $line -Variant $variant -Kind Index
    })
    $normalisedContact = @(foreach ($line in $runs[1]) {
        Convert-AddedLine -Line $line -Variant $variant -Kind Contact
    })
    $template = @($normalisedIndex + $normalisedContact)
    $templateText = $template -join "`n"
    $normalisedTemplates[$variant.Hash] = $templateText
    $variantEvidence.Add([ordered]@{
        shaderHash = $variant.Hash
        acceptedSha256 = $acceptedSha
        originalAssemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $originalPath).Hash
        originalComparableLines = $original.Count
        acceptedComparableLines = $accepted.Count
        indexInsertionLines = $normalisedIndex.Count
        contactInsertionLines = $normalisedContact.Count
        depth = $variant.Depth
        lightList = $variant.LightList
        sceneColor = $variant.SceneColor
    })
}

$referenceHash = $variants[0].Hash
$referenceTemplate = $normalisedTemplates[$referenceHash]
foreach ($variant in $variants) {
    if ($normalisedTemplates[$variant.Hash] -cne $referenceTemplate) {
        throw "Accepted insertion does not normalise to the common family template: $($variant.Hash)"
    }
}
$templateLines = @($referenceTemplate -split "`n")
$indexInsertion = $templateLines[0]
$contactBlock = @($templateLines[1..($templateLines.Count - 1)])
if ($indexInsertion -cne 'mov ${t00}.z, ${light_index}.${light_index_component}' -or
    $contactBlock.Count -ne 1971) {
    throw 'Normalised accepted template has an unexpected boundary.'
}

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

function New-Replacement([string]$Depth) {
    $resolvedIndex = $indexInsertion.Replace('${depth}', $Depth)
    $resolvedContact = @($contactBlock | ForEach-Object { $_.Replace('${depth}', $Depth) })
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('${before_index}' + $resolvedIndex + '\n')
    $lines.Add('${between_index_and_contact}' + $resolvedContact[0] + '\n')
    for ($index = 1; $index -lt $resolvedContact.Count; $index++) {
        $lines.Add($resolvedContact[$index] + '\n')
    }
    $lines.Add('${after_contact}')
    return $lines -join "`r`n"
}

function New-FamilySection([Collections.IDictionary]$Layout) {
    $name = 'ShaderRegexUE4FXRemakeTiledSurfaceLightContact' + $Layout.Depth.ToUpperInvariant()
    $temps = (0..15 | ForEach-Object { 't' + $_.ToString('00') }) -join ' '
    $requiredTextures = if ($Layout.Depth -eq 't5') {
        't0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12'
    }
    else {
        't0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11'
    }
    $pattern = $patternTemplate.Replace('__LIGHT_LIST__', $Layout.LightList).
        Replace('__SCENE_COLOR__', $Layout.SceneColor)
    $replacement = New-Replacement -Depth $Layout.Depth
    return @"
[$name]
shader_model = cs_5_0
temps = $temps
family_mode = automatic
required_bindings = b0, b1, b2, b3, b4, s0, s1, s2, s3, $requiredTextures, u0, vThreadGroupID, vThreadIDInGroup
forbidden_bindings = t120, g0, cb13, u7
min_instructions = 478
max_instructions = 1008
x29 = `$ue4fx_contact_edge_width_v2
y29 = `$ue4fx_contact_edge_cutoff_v2
x31 = `$ue4fx_master_injected_v1
y31 = -1
z31 = 1
w31 = 100

[$name.InsertDeclarations]
dcl_resource_texture1d (float,float,float,float) t120
dcl_tgsm_structured g0, 4, 256

[$name.Pattern]
$pattern
[$name.Pattern.Replace]
$replacement
"@
}

$layouts = @(
    [ordered]@{ Depth='t4'; LightList='t11'; SceneColor='t8' },
    [ordered]@{ Depth='t5'; LightList='t12'; SceneColor='t9' }
)
$header = @"
; Generated automatic family equivalent of the accepted FF7 Remake contact-shadow checkpoint.
; Source of truth: working-code\Frustum Fix\20260831-v1\accepted-runtime.
; F10 remains native reload. Page Down is the accepted-code master. Page Up remains free for tests.
; The two groups differ only where Remake's compatible variants bind depth/light-list/scene-color.
[Constants]
global `$ue4fx_master_injected_v1 = 1
global `$ue4fx_contact_edge_width_v2 = 0.06
global `$ue4fx_contact_edge_cutoff_v2 = 0

[KeyUE4FXMasterPageDown]
key = no_modifiers VK_NEXT
type = cycle
smart = true
`$ue4fx_master_injected_v1 = 0, 1
"@

[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$familyIniPath = Join-Path $outputRoot 'ContactShadowFamily.ini'
$familyText = $header + "`r`n" +
    (New-FamilySection -Layout $layouts[0]) + "`r`n" +
    (New-FamilySection -Layout $layouts[1])
[IO.File]::WriteAllText($familyIniPath, $familyText, $utf8)

$templateSha = [Convert]::ToHexString(
    [Security.Cryptography.SHA256]::HashData($utf8.GetBytes($referenceTemplate)))
$report = [ordered]@{
    schemaVersion = 1
    kind = 'ff7-remake-contact-shadow-family-generator'
    source = 'accepted-16-sample-shared-quad-rebirth-contact-with-left-frustum-fix'
    checkpointManifest = $checkpointManifestPath
    checkpointManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $checkpointManifestPath).Hash
    auditIniSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $auditIniPath).Hash
    normalisedTemplateSha256 = $templateSha
    indexInsertionLines = 1
    contactInsertionLines = $contactBlock.Count
    temporaryRegisters = 16
    layouts = $layouts
    variants = @($variantEvidence)
    outputIni = $familyIniPath
    outputIniSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $familyIniPath).Hash
    liveFilesModified = $false
}
$reportPath = Join-Path $outputRoot 'family-generation.json'
[IO.File]::WriteAllText(
    $reportPath,
    ($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine,
    $utf8)

Write-Host "FAMILY_INI=$familyIniPath"
Write-Host "REPORT=$reportPath"
Write-Host 'PASS: all five accepted contact shaders normalised to one generated two-layout ShaderRegex transformation.'
