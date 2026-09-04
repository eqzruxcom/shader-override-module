[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$FxcPath='C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe',
    [ValidateSet('None','GT7')][string]$ToneMap='None'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if (-not $output.StartsWith((Join-Path $repo 'artifacts\generated-runtime')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Output must stay below generated-runtime.' }
if (Test-Path -LiteralPath $output) { throw 'Output exists; preserve previous evidence.' }
$authorPath=Join-Path $repo 'reference\ShaderInjector\ModifiedShaders\Includes\PixelShaderPass_PostProcessFinal.hlsl'
$authorHash='F2EAA2D047776D43AD9D8266516E9B27B0D386E7CDDB8D999CE6600AB91A4726'
if ((Get-FileHash -LiteralPath $authorPath).Hash -ne $authorHash) { throw 'Pinned author source changed.' }
$author=[IO.File]::ReadAllText($authorPath).Replace("`r`n","`n")
$colorPath=Join-Path $repo 'reference\ShaderInjector\ModifiedShaders\Includes\LibraryColor.hlsl'
$color=[IO.File]::ReadAllText($colorPath).Replace("`r`n","`n")
$function=[regex]::Match($author,'(?s)float3 AdjustImage\(float3 inputColor\)\s*\{.*?\n\}')
$luma=[regex]::Match($color,'(?s)float LuminanceRec709\(float3 linearColor\)\s*\{.*?\n\}')
$defines=@([regex]::Matches($author,'(?m)^#define ADJUSTMENT_\w+[^\n]*') | ForEach-Object Value)
if (-not $function.Success -or -not $luma.Success -or $defines.Count -ne 10) { throw 'Author adjustment extraction failed.' }
if ($author -notmatch '(?m)^#define ADJUSTMENT_BRIGHTNESS_EV -0\.45\s*$' -or $author -notmatch '(?m)^#define ADJUSTMENT_GAMMA 1\.15\s*$') { throw 'Audited author preset changed.' }
$license=[IO.File]::ReadAllText((Join-Path $repo 'reference\ShaderInjector\LICENSE'))
$kernel="/*`n$license`n*/`n// AdjustImage and defaults from frostbone25/ShaderInjector, bab25809b375f028b7c0fb603d804426f38c9b8e.`n"+($defines -join "`n")+"`n"+$luma.Value+"`n"+$function.Value+"`nfloat3 main(float3 inputColor : TEXCOORD0) : SV_Target0 { return AdjustImage(inputColor); }`n"
$validation=Join-Path $output 'validation'
$null=& (Join-Path $PSScriptRoot 'New-IntergradeFinalCompositeCandidate.ps1') -OutputDirectory $validation
$utf8=[Text.UTF8Encoding]::new($false)
$kernelPath=Join-Path $validation 'author-adjustments.hlsl'
[IO.File]::WriteAllText($kernelPath,$kernel,$utf8)
$kernelBin=Join-Path $validation 'author-adjustments.bin'
$messages=& $FxcPath /nologo /T ps_5_0 /E main /Ges /WX /O3 /Fo $kernelBin $kernelPath 2>&1
if ($LASTEXITCODE -ne 0) { throw "Author SM5 kernel failed: $messages" }
[IO.File]::WriteAllText((Join-Path $validation 'author-kernel-compile.log'),($messages | Out-String),$utf8)
$assembler=Join-Path $repo 'artifacts\shader-assembler-build\bin\cmd_Decompiler.exe'
function Invoke-Assembler([string[]]$Arguments,[string]$Log) {
    $messages=& $assembler @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Assembler failed: $messages" }
    [IO.File]::WriteAllText((Join-Path $validation $Log),($messages | Out-String),$utf8)
}
function Get-Lines([string]$Text) { return ,@($Text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('//') }) }
Invoke-Assembler @('-d','-V',$kernelBin) 'author-kernel-validation.log'
$kernelAsm=[IO.File]::ReadAllText((Join-Path $validation 'author-adjustments.asm'))
$kernelLines=Get-Lines $kernelAsm
if ($kernelAsm -match '(?m)^dcl_(?:resource|sampler|constantbuffer|uav)' -or $kernelAsm -notmatch '(?m)^dcl_input_ps linear v0.xyz\s*$' -or $kernelAsm -notmatch '(?m)^dcl_output o0.xyz\s*$') { throw 'Kernel is not a self-contained RGB transform.' }
$tempMatch=[regex]::Match($kernelAsm,'(?m)^dcl_temps (\d+)\s*$')
if (-not $tempMatch.Success) { throw 'Kernel temporary count unavailable.' }
$kernelTemps=[int]$tempMatch.Groups[1].Value
$body=@($kernelLines | Where-Object { $_ -ne 'ps_5_0' -and $_ -ne 'ret' -and -not $_.StartsWith('dcl_') })
foreach ($line in $body) {
    if ($line -notmatch '^(?:add|mul|mad|max|min|dp3|log|exp|mov|div|rcp|sqrt|lt|ge|eq|ne|movc)(?:_sat)?\s') { throw "Unaudited kernel opcode: $line" }
}
# One final output assignment prevents overwriting the original input mid-kernel.
if (@($body | Where-Object { $_ -match '\bo0\.' }).Count -ne 1 -or $body[-1] -notmatch '^\w+ o0\.xyz,') { throw 'Kernel output is not a single final RGB assignment.' }
if (($kernelLines -join "`n") -match '\b(?:v[1-9]|o[1-9])\.') { throw 'Unexpected kernel input/output register.' }
$translated=@(foreach ($line in $body) {
    $line=[regex]::Replace($line,'\br(\d+)\b',{param($match) 'r'+([int]$match.Groups[1].Value+13)})
    '    '+$line.Replace('v0.','r2.').Replace('o0.','r2.')
})
$source=[IO.File]::ReadAllText((Join-Path $validation 'original.asm')).Replace("`r`n","`n")
$anchor='  mul r3.xyz, r2.xyzx, l(0.010000, 0.010000, 0.010000, 0.000000)'
$declaration='dcl_resource_texture1d (float,float,float,float) t120'
$inputDeclaration='dcl_input_ps_siv linear noperspective v0.xy, position'
foreach ($a in @($anchor,'dcl_temps 12',$inputDeclaration)) {
    if ([regex]::Matches($source,[regex]::Escape($a)).Count -ne 1) { throw "Original assembly anchor is not unique: $a" }
}
if ($source -match '\b(?:r12|t120)\b') { throw 'Diagnostic registers conflict with original.' }
$block=@(
    '  ld_indexable(texture1d)(float,float,float,float) r12.x, l(30, 0, 0, 0), t120.xyzw'
    '  eq r12.x, r12.x, l(1.000000)'
    '  if_nz r12.x'
)+$translated+@('  endif')
$blockText=$block -join "`n"
$tempDeclaration='dcl_temps '+(13+$kernelTemps)
$toneBlock=@()
$toneBody=@()
$toneAnchor='  log r2.xyz, |r2.xyzx|'
$toneSourceHash=$null
if ($ToneMap -eq 'GT7') {
    $tonePath=Join-Path $repo 'reference\ShaderInjector\ModifiedShaders\Includes\LibraryTonemaps.hlsl'
    $toneSourceHash='4D50BAE948D41B38E673336863FB9B5E886E4528AAE914288ADFAC5ECF3E8CB5'
    if ((Get-FileHash -LiteralPath $tonePath).Hash -ne $toneSourceHash) { throw 'Pinned tone library changed.' }
    $toneSource=[IO.File]::ReadAllText($tonePath).Replace("`r`n","`n")
    $gtStart=$toneSource.IndexOf('struct GTToneMappingCurveV2')
    $gtEndMatch=[regex]::Match($toneSource,'(?s)float3 ApplyTonemap_GranTurismo7\(float3 color\)\s*\{.*?\n\}')
    $inverseStart=$author.IndexOf('static const float3x3 ACESInputMatInv =')
    $inverseEndMatch=[regex]::Match($author,'(?s)float3 ApplyTonemap_AcesFitted_Inv\(float3 color\)\s*\{.*?\n\}')
    if ($gtStart -lt 0 -or -not $gtEndMatch.Success -or $inverseStart -lt 0 -or -not $inverseEndMatch.Success) { throw 'Tone source extraction failed.' }
    $gtFunctions=$toneSource.Substring($gtStart,$gtEndMatch.Index+$gtEndMatch.Length-$gtStart)
    # FXC cannot prove these domains through the source structs/functions.
    # Both are nonnegative on this inverse-ACES -> SDR GT7 call path.
    $gtFunctions=$gtFunctions.Replace('float ym = pow(y, m1);','float ym = pow(max(y, 0.0f), m1);').Replace('pow(x / curve.midPoint_, curve.toeStrength_)','pow(max(x / curve.midPoint_, 0.0f), curve.toeStrength_)')
    $inverseFunctions=$author.Substring($inverseStart,$inverseEndMatch.Index+$inverseEndMatch.Length-$inverseStart)
    $paperWhite=[regex]::Match($toneSource,'(?m)^#define TONEMAP_GRAN_TURISMO_7_SDR_PAPER_WHITE 100\.0\s*$')
    $acesExposure=[regex]::Match($author,'(?m)^#define ORIGINAL_GAME_ACES_EXPOSURE 2\.0\s*$')
    if (-not $paperWhite.Success -or -not $acesExposure.Success) { throw 'Audited SDR/reference exposure defaults changed.' }
    $toneKernel="/*`n$license`n*/`n// GT7 source: https://blog.selfshadow.com/publications/s2025-shading-course/pdi/supplemental/gt7_tone_mapping.cpp`n"+$paperWhite.Value+"`n"+$acesExposure.Value+"`n"+$gtFunctions+"`n"+$inverseFunctions+"`nfloat3 main(float3 inputColor : TEXCOORD0) : SV_Target0 { return ApplyTonemap_GranTurismo7(ApplyTonemap_AcesFitted_Inv(inputColor) / ORIGINAL_GAME_ACES_EXPOSURE); }`n"
    $toneKernelPath=Join-Path $validation 'author-gt7.hlsl'
    $toneKernelBin=Join-Path $validation 'author-gt7.bin'
    [IO.File]::WriteAllText($toneKernelPath,$toneKernel,$utf8)
    $messages=& $FxcPath /nologo /T ps_5_0 /E main /Ges /WX /O3 /Fo $toneKernelBin $toneKernelPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Author GT7 SM5 compilation failed: $messages" }
    [IO.File]::WriteAllText((Join-Path $validation 'author-gt7-compile.log'),($messages | Out-String),$utf8)
    Invoke-Assembler @('-d','-V',$toneKernelBin) 'author-gt7-validation.log'
    $toneAssembly=[IO.File]::ReadAllText((Join-Path $validation 'author-gt7.asm'))
    $toneLines=Get-Lines $toneAssembly
    if ($toneAssembly -match '(?m)^dcl_(?:resource|sampler|constantbuffer|uav)' -or $toneAssembly -notmatch '(?m)^dcl_input_ps linear v0.xyz\s*$' -or $toneAssembly -notmatch '(?m)^dcl_output o0.xyz\s*$') { throw 'Tone kernel has unhandled resources or signature.' }
    $toneTempsMatch=[regex]::Match($toneAssembly,'(?m)^dcl_temps (\d+)\s*$')
    if (-not $toneTempsMatch.Success -or @($toneLines | Where-Object { $_ -eq 'ret' }).Count -ne 1 -or $toneLines[-1] -ne 'ret') { throw 'Unhandled tone kernel temporaries or return flow.' }
    $toneBody=@($toneLines | Where-Object { $_ -ne 'ps_5_0' -and $_ -ne 'ret' -and -not $_.StartsWith('dcl_') })
    $depth=0
    foreach ($line in $toneBody) {
        if ($line -match '^if_(?:nz|z) ') { $depth++; continue }
        if ($line -eq 'endif') { $depth--; if ($depth -lt 0) { throw 'Unbalanced tone condition.' }; continue }
        if ($line -eq 'else') { if ($depth -lt 1) { throw 'Unbalanced tone else.' }; continue }
        if ($line -notmatch '^(?:add|mul|mad|max|min|dp2|dp3|dp4|log|exp|mov|div|rcp|sqrt|rsq|lt|ge|eq|ne|movc|and|or|not)(?:_sat)?\s') { throw "Unaudited tone opcode: $line" }
    }
    if ($depth -ne 0 -or ($toneLines -join "`n") -match '\b(?:v[1-9]|o[1-9])\.') { throw 'Unbalanced flow or unsupported tone input/output register.' }
    $toneTranslated=@(foreach ($line in $toneBody) {
        $line=[regex]::Replace($line,'\br(\d+)\b',{param($match) 'r'+([int]$match.Groups[1].Value+16)})
        '    '+$line.Replace('v0.','r14.').Replace('o0.','r15.')
    })
    # Original, previous author preset, and author preset + GT7 are separate modes.
    $block=@(
        '  ld_indexable(texture1d)(float,float,float,float) r12.x, l(30, 0, 0, 0), t120.xyzw'
        '  eq r12.y, r12.x, l(1.000000)'
        '  eq r12.z, r12.x, l(2.000000)'
        '  or r12.x, r12.y, r12.z'
        '  if_nz r12.x'
    )+$translated+@('  endif')
    $blockText=$block -join "`n"
    $toneBlock=@(
        '  ld_indexable(texture1d)(float,float,float,float) r12.x, l(30, 0, 0, 0), t120.xyzw'
        '  eq r12.x, r12.x, l(2.000000)'
        '  if_nz r12.x'
        '    mov r14.xyz, r2.xyzx'
    )+$toneTranslated+@('    mov r2.xyz, r15.xyzx','  endif')
    $tempDeclaration='dcl_temps '+[Math]::Max(13+$kernelTemps,16+[int]$toneTempsMatch.Groups[1].Value)
    if ([regex]::Matches($source,[regex]::Escape($toneAnchor)).Count -ne 1) { throw 'Post-LUT linear insertion boundary is not unique.' }
}
$modified=$source.Replace($inputDeclaration,$declaration+"`n"+$inputDeclaration).Replace('dcl_temps 12',$tempDeclaration).Replace($anchor,$blockText+"`n"+$anchor)
if ($toneBlock.Count) { $modified=$modified.Replace($toneAnchor,($toneBlock -join "`n")+"`n"+$toneAnchor) }
$reconstructed=$modified.Replace($declaration+"`n",'').Replace($tempDeclaration,'dcl_temps 12').Replace($blockText+"`n",'')
if ($toneBlock.Count) { $reconstructed=$reconstructed.Replace(($toneBlock -join "`n")+"`n",'') }
if ($reconstructed -cne $source) { throw 'Original source reconstruction failed.' }
$authored=Join-Path $validation 'author-final.asm'
[IO.File]::WriteAllText($authored,$modified,$utf8)
Invoke-Assembler @('-a','--copy-reflection',(Join-Path $validation 'original.bin'),$authored) 'author-final-assembly.log'
$candidate=Join-Path $validation 'author-final.shdr'
$verify=Join-Path $validation 'author-final-verified.bin'
Copy-Item -LiteralPath $candidate -Destination $verify
Invoke-Assembler @('-d','-V',$verify) 'author-final-validation.log'
$after=Get-Lines ([IO.File]::ReadAllText((Join-Path $validation 'author-final-verified.asm')))
$before=Get-Lines $source
if (($after -join "`n") -cne ((Get-Lines $modified) -join "`n")) { throw 'Authored instructions changed on reassembly.' }
function Get-Sections([string]$Path) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    if ([Text.Encoding]::ASCII.GetString($bytes,0,4) -ne 'DXBC') { throw 'Invalid DXBC.' }
    $sections=[ordered]@{}
    for ($i=0; $i -lt [BitConverter]::ToUInt32($bytes,28); $i++) {
        $offset=[BitConverter]::ToUInt32($bytes,32+4*$i)
        $tag=[Text.Encoding]::ASCII.GetString($bytes,$offset,4)
        $length=[BitConverter]::ToUInt32($bytes,$offset+4)
        $sections[$tag]=[byte[]]$bytes[($offset+8)..($offset+7+$length)]
    }
    return $sections
}
function Get-Tokens([byte[]]$Code) {
    $result=[Collections.Generic.List[string]]::new()
    $offset=8
    while ($offset -lt $Code.Length) {
        $length=(([BitConverter]::ToUInt32($Code,$offset) -shr 24) -band 127)*4
        if ($length -eq 0 -or $offset+$length -gt $Code.Length) { throw 'Invalid instruction size.' }
        $result.Add([Convert]::ToHexString([byte[]]$Code[$offset..($offset+$length-1)])); $offset+=$length
    }
    return ,$result.ToArray()
}
$originalSections=Get-Sections (Join-Path $validation 'original.bin')
$patchedSections=Get-Sections $candidate
if (($originalSections.Keys -join ',') -cne ($patchedSections.Keys -join ',')) { throw 'DXBC sections changed.' }
$tag=if ($originalSections.Contains('SHEX')) { 'SHEX' } else { 'SHDR' }
foreach ($name in $originalSections.Keys) {
    if ($name -ne $tag -and [Convert]::ToHexString($originalSections[$name]) -cne [Convert]::ToHexString($patchedSections[$name])) { throw "Metadata changed: $name" }
}
$originalTokens=Get-Tokens $originalSections[$tag]
$patchedTokens=Get-Tokens $patchedSections[$tag]
$skip=[Collections.Generic.HashSet[int]]::new()
$null=$skip.Add([Array]::IndexOf($after,$declaration)-1)
$blockStart=[Array]::IndexOf($after,$block[0].Trim())-1
if ($blockStart -lt 0) { throw 'Missing author block.' }
for ($i=0; $i -lt $block.Count; $i++) { $null=$skip.Add($blockStart+$i) }
if ($toneBlock.Count) {
    $toneStart=[Array]::IndexOf($after,$toneAnchor.Trim())-1-$toneBlock.Count
    if ($toneStart -le $blockStart+$block.Count) { throw 'Tone block is not downstream of input adjustments.' }
    for ($i=0; $i -lt $toneBlock.Count; $i++) { $null=$skip.Add($toneStart+$i) }
}
$j=0; $preserved=0
for ($i=0; $i -lt $patchedTokens.Count; $i++) {
    if ($skip.Contains($i)) { continue }
    if ($before[$j+1] -ne 'dcl_temps 12') {
        if ($originalTokens[$j] -cne $patchedTokens[$i]) { throw "Original instruction token changed: $j" }
        $preserved++
    } elseif ($after[$i+1] -ne $tempDeclaration) { throw 'Wrong temp declaration.' }
    $j++
}
if ($preserved -ne 134 -or $j -ne $originalTokens.Count) { throw 'Original instruction preservation incomplete.' }
$ini=@'
; First author-effect port: exact pinned AdjustImage settings, before native tone mapping.
; OFF retains original calculations inside the replacement, not the native shader object.
[Constants]
global $ue4fx_final_scene_ab = 0

[KeyUE4FXFinalSceneAB]
key = no_modifiers VK_PAGEDOWN
type = cycle
smart = true
$ue4fx_final_scene_ab = 0, 1

[ShaderOverrideUE4FXFinalSceneAB]
hash = 41f1bf8b79d01319
x30 = $ue4fx_final_scene_ab
'@
if ($ToneMap -eq 'GT7') {
    $ini=$ini.Replace('; First author-effect port: exact pinned AdjustImage settings, before native tone mapping.','; Author preset and experimental inverse-ACES + GT7. Modes: original, previous preset, preset + GT7.').Replace('$ue4fx_final_scene_ab = 0, 1','$ue4fx_final_scene_ab = 0, 1, 2')
}
$licenseComments=($license -split "`r?`n" | ForEach-Object { '// '+$_ }) -join "`n"
$payloads=[ordered]@{'Mods/UE4EffectsGenerated.ini'=$ini; 'ShaderFixes/41f1bf8b79d01319-ps.txt'=('// AdjustImage port from frostbone25/ShaderInjector; original Remake shader preserved below.'+"`n"+$licenseComments+"`n"+$modified)}
$files=@(foreach ($relative in $payloads.Keys) {
    $path=Join-Path $output $relative
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    [IO.File]::WriteAllText($path,$payloads[$relative].Replace("`r`n","`n").Replace("`n","`r`n")+"`r`n",$utf8)
    [ordered]@{relativePath=$relative; size=(Get-Item -LiteralPath $path).Length; sha256=(Get-FileHash -LiteralPath $path).Hash}
})
$manifest=[ordered]@{
    schemaVersion=1; adapterId='FF7RemakeIntergradeAuthorImageAdjustments'; renderer='D3D11'
    executable=[ordered]@{name='ff7remake_.exe'; sha256='25B54C345C94EE9F6C6876B9C7537A69E6B0EEF25F322207C32A8DDCEE816635'}
    licensedRegexDependency=$false; diagnosticOnly=$true; runtimeEligible=$false
    status='author-port-compiled-live-pending'; shaderHash='41f1bf8b79d01319'
    sourceAuthor='frostbone25 / David Matos'; sourceCommit='bab25809b375f028b7c0fb603d804426f38c9b8e'
    authorSourceSha256=$authorHash; colorLibrarySha256=(Get-FileHash -LiteralPath $colorPath).Hash
    license='MIT'; extractedAuthorFunction='AdjustImage'; extractedAuthorDefines=$defines
    settings=[ordered]@{brightnessEV=-0.45; gamma=1.15; allOtherAdjustments='pinned neutral defaults'}
    placement='after final scene sample, before original PQ encoding / LUT mapping / alternate branch'
    originalTonemappingRetained=$true; nativeToneReplacement=$false
    notIncluded=@('auto exposure','custom tone operator','inverse-ACES color-grade recovery','bloom changes','sharpening','lighting/shadows/GI')
    offState='original-math-in-assembly-replacement'; trueNativeShaderToggle=$false
    originalTokensByteIdentical=$preserved; kernelInstructions=$body.Count; addedInstructionOrDeclarationCount=($block.Count+1)
    control=[ordered]@{key='VK_PAGEDOWN'; variable='$ue4fx_final_scene_ab'; default=0; values=@(0,1); labels=@('original-math','author-image-adjustments')}
    candidateSha256=(Get-FileHash -LiteralPath $candidate).Hash
    sourceKernelSha256=(Get-FileHash -LiteralPath $kernelPath).Hash
    visualStatus='pending'; files=$files
}
if ($ToneMap -eq 'GT7') {
    $manifest.adapterId='FF7RemakeIntergradeAuthorGT7'
    $manifest.status='author-gt7-compiled-live-pending'
    $manifest.toneOperator='source-author GT7, SDR, 100-nit paper-white parameter'
    $manifest.colorGradeRecovery='source-author inverse ACES fitted, divided by original-game exposure 2.0'
    $manifest.colorGradeRecoveryValidatedForRemake=$false
    $manifest.toneLibrarySha256=$toneSourceHash
    $manifest.sm5DomainGuards=@('nonnegative PQ power input','nonnegative toe power input')
    $manifest.toneKernelInstructions=$toneBody.Count
    $manifest.addedInstructionOrDeclarationCount=$block.Count+$toneBlock.Count+1
    $manifest.tonePlacement='after original LUT/alternate mapping and sRGB decoding; before original device gamma, saturation, UI blend, and output transfer'
    $manifest.originalTonemappingRetained='modes 0/1: unchanged; mode 2: original LUT evaluated then inverse-and-remap attempt'
    $manifest.notIncluded=@('auto exposure','bloom changes','sharpening','lighting/shadows/GI','HDR testing')
    $manifest.control.values=@(0,1,2)
    $manifest.control.labels=@('original-math','author-image-adjustments','author-image-adjustments-plus-GT7')
    $manifest.sourceGamutAssumption='source GT7 wrapper receives inverse-ACES result without an additional Rec709/Rec2020 conversion, matching the pinned author call path'
}
$manifestPath=Join-Path $output 'runtime-manifest.json'
[IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 9)+[Environment]::NewLine,$utf8)
[pscustomobject]@{Output=$output; Manifest=$manifestPath; OriginalTokensPreserved=$preserved; KernelInstructions=$body.Count; CandidateSha256=$manifest.candidateSha256}
