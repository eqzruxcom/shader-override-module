[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$StudyDirectory,
    [ValidateSet(8,16,32)][int]$Samples=16,
    [ValidateSet('Experimental','Rebirth')][string]$Implementation='Experimental',
    [ValidateSet('Raw','RecomputeQuad','SharedQuad')][string]$Reconstruction='Raw',
    [string]$SharedBoundaryDirectory,
    [string]$FxcPath='C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($Reconstruction -ne 'Raw' -and $Implementation -ne 'Rebirth') {throw 'Quad reconstruction requires the source-preserving Rebirth implementation.'}
$shared=$Reconstruction -eq 'SharedQuad'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if (-not $output.StartsWith((Join-Path $repo 'artifacts')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Candidate output must be below workspace artifacts.' }
if (Test-Path -LiteralPath $output) { throw 'Candidate output exists; preserve earlier evidence.' }
if (-not $StudyDirectory) { $StudyDirectory=Join-Path $repo 'artifacts\surface-lighting-study-20260830-v3' }
$study=Get-Content -LiteralPath (Join-Path $StudyDirectory 'study.json') -Raw | ConvertFrom-Json
$variants=@(
    @{Hash='c30cdc8365df9840';Temps=39;Depth=5;Index='r29.x';Diffuse='r30.xyz';Specular='r29.xzw';Anchor='add r27.xyz, r27.xyzx, r30.xyzx';Sha='0FF0D61014A447B4B9E133CDAD1C927F8A5ABFE8396151BED3E4A5D537483216'},
    @{Hash='62b33a2d1e505241';Temps=24;Depth=4;Index='r16.w';Diffuse='r18.xyz';Specular='r17.yzw';Anchor='add r15.xyz, r15.xyzx, r18.xyzx';Sha='1E290F68B5A07E8987A674384B955C0D6A8246A96B47506CD2E4CC6E6EED9551'},
    @{Hash='5a9fbefe0ab6f815';Temps=29;Depth=4;Index='r21.x';Diffuse='r22.xyz';Specular='r21.xzw';Anchor='add r19.xyz, r19.xyzx, r22.xyzx';Sha='45D1C022E89B58C9524E86F54901FCCB98D93448940B1E925CE53D133D36BA16'},
    @{Hash='0e97888f9a8767da';Temps=30;Depth=5;Index='r20.w';Diffuse='r22.xyz';Specular='r21.yzw';Anchor='add r19.xyz, r19.xyzx, r22.xyzx';Sha='B6D1E0A7EA8032F55EAA6017D39BF70B097669335951DBF437782C5804BCF283'},
    @{Hash='08bb8764f1840179';Temps=31;Depth=5;Index='r14.w';Diffuse='r24.xyz';Specular='r23.xyz';Anchor='add r21.xyz, r21.xyzx, r24.xyzx';Sha='CB9A9EE79FF8DB0B63B8DD6F239AF69FF23A83D786A46E51EB07D352DD7659EE'}
)
foreach ($v in $variants) {
    if ((Get-FileHash -LiteralPath (Join-Path $StudyDirectory ($v.Hash+'-cs.bin'))).Hash -ne $v.Sha) { throw "Original changed: $($v.Hash)" }
    $record=@($study.variants | Where-Object shaderHash -eq $v.Hash)
    if ($record.Count -ne 1 -or -not $record[0].byteIdenticalRoundTrip -or $record[0].originalSha256 -ne $v.Sha) { throw 'Unverified native study input.' }
}
$assembler=Join-Path $repo 'artifacts\shader-assembler-build\bin\cmd_Decompiler.exe'
$kernelSource=Join-Path $repo 'src\Adapters\FF7RemakeIntergrade\ContactShadowKernel_ps.hlsl'
$effectSource=Join-Path $repo 'src/Effects/Lighting/ContactShadows.hlsl'
if($Implementation -eq 'Rebirth') {
    $kernelSource=Join-Path $repo 'src/Adapters/FF7RemakeIntergrade/RebirthContactShadowKernel_ps.hlsl'
    $effectSource=Join-Path $repo 'src/Effects/Lighting/RebirthContactShadows.hlsl'
}
if($Reconstruction -eq 'RecomputeQuad') {$kernelSource=Join-Path $repo 'src/Adapters/FF7RemakeIntergrade/RebirthContactReconstructedKernel_ps.hlsl'}
if($shared) {
    $kernelSource=Join-Path $repo 'src/Adapters/FF7RemakeIntergrade/RebirthContactSharedKernel_cs.hlsl'
    if(-not $SharedBoundaryDirectory){throw 'SharedQuad requires the pinned native boundary audit.'}
    $boundary=Get-Content -LiteralPath (Join-Path $SharedBoundaryDirectory 'boundary.json') -Raw | ConvertFrom-Json
    if($boundary.result -ne 'verified-pinned-native-boundary' -or $boundary.variants.Count -ne 5 -or $boundary.scriptSha256 -ne (Get-FileHash -LiteralPath (Join-Path $repo 'tools/audit_rebirth_shared_boundary.py')).Hash){throw 'Stale or incomplete boundary audit.'}
}
$utf8=[Text.UTF8Encoding]::new($false)
$validation=Join-Path $output 'validation'
$null=New-Item -ItemType Directory -Path $validation
function Run-ContactTool([string]$Tool,[string[]]$Arguments,[string]$Log) {
    $messages=& $Tool @Arguments 2>&1
    $code=$LASTEXITCODE
    [IO.File]::WriteAllText($Log,($messages | Out-String),$utf8)
    if ($code -ne 0) { throw "Offline tool failed: $Log" }
}
function Read-Instructions([string]$Path) {
    return ,@(Get-Content -LiteralPath $Path | ForEach-Object {$_.Trim()} | Where-Object {$_ -and -not $_.StartsWith('//')})
}
function Read-DxbcSections([string]$Path) {
    $b=[IO.File]::ReadAllBytes($Path)
    if ([Text.Encoding]::ASCII.GetString($b,0,4) -ne 'DXBC') { throw 'Invalid DXBC' }
    $sections=[ordered]@{}
    for ($i=0;$i -lt [BitConverter]::ToUInt32($b,28);$i++) {
        $offset=[BitConverter]::ToUInt32($b,32+4*$i)
        $tag=[Text.Encoding]::ASCII.GetString($b,$offset,4)
        $length=[BitConverter]::ToUInt32($b,$offset+4)
        $sections[$tag]=[byte[]]$b[($offset+8)..($offset+7+$length)]
    }
    return $sections
}
function Read-InstructionTokens([byte[]]$Code) {
    $tokens=[Collections.Generic.List[string]]::new()
    $offset=8
    while ($offset -lt $Code.Length) {
        $length=(([BitConverter]::ToUInt32($Code,$offset) -shr 24) -band 127)*4
        if (-not $length -or $offset+$length -gt $Code.Length) { throw 'Invalid token length' }
        $tokens.Add([Convert]::ToHexString([byte[]]$Code[$offset..($offset+$length-1)]))
        $offset+=$length
    }
    return ,$tokens.ToArray()
}
$kernelBinary=Join-Path $validation 'contact-kernel.bin'
$profile=if($shared){'cs_5_0'}else{'ps_5_0'}
Run-ContactTool $FxcPath @('/nologo','/Ges','/Gis','/WX','/O3','/D',"REDX11_CONTACT_SAMPLES=$Samples",'/T',$profile,'/E','main','/Fo',$kernelBinary,$kernelSource) (Join-Path $validation 'kernel-compile.log')
Run-ContactTool $assembler @('-d','-V',$kernelBinary) (Join-Path $validation 'kernel-validation.log')
$kernelLines=Read-Instructions (Join-Path $validation 'contact-kernel.asm')
$requiredInterface=if($shared){@('cs_5_0','dcl_input vThreadIDInGroup.xy','dcl_tgsm_structured g0, 4, 256','dcl_resource_texture2d (float,float,float,float) t4')}else{@('ps_5_0','dcl_input_ps linear v0.xyz','dcl_output o0.x','dcl_resource_texture2d (float,float,float,float) t4')}
foreach ($required in $requiredInterface) {
    if (@($kernelLines | Where-Object {$_ -ceq $required}).Count -ne 1) { throw "Unexpected kernel interface: $required" }
}
$declarations=@($kernelLines | Where-Object {$_ -match '^dcl_'})
$expectedViewRows=if($Implementation -eq 'Rebirth'){140}else{127}
foreach ($d in $declarations) {
    $allowed='^dcl_(globalFlags refactoringAllowed|constantbuffer CB(?:0\[2\], immediateIndexed|1\['+$expectedViewRows+'\], immediateIndexed|4\[768\], dynamicIndexed)|resource_texture2d \(float,float,float,float\) t[124]|resource_texture1d \(float,float,float,float\) t120|input_ps linear v0.xyz|output o0.x|temps \d+)$'
    if($shared -and $d -match '^dcl_(constantbuffer CB13\[1\], immediateIndexed|input vThreadIDInGroup.xy|uav_structured u7, 4|tgsm_structured g0, 4, 256|thread_group 16, 16, 1)$'){continue}
    if ($d -notmatch $allowed) { throw "Unaudited kernel declaration: $d" }
}
$kernelTemps=[int]([regex]::Match(($kernelLines -join "`n"),'(?m)^dcl_temps (\d+)$').Groups[1].Value)
$kernelBody=@($kernelLines | Where-Object {$_ -ne $profile -and -not $_.StartsWith('dcl_')})
$loopDepth=0;$returns=0
foreach ($line in $kernelBody) {
    if ($line -eq 'loop') {$loopDepth++}
    if ($line -eq 'endloop') {$loopDepth--}
    if ($line -eq 'ret') { if ($loopDepth -ne 0) {throw 'Kernel return inside a loop cannot be safely lowered.'};$returns++ }
    elseif ($line -match '^ret') {throw 'Unaudited conditional return.'}
    if($shared -and ($line -eq 'sync_g_t' -or $line -match '^store_structured u7.x, r\d+\.[xyzw], l\(0\), r\d+\.[xyzw]$')){continue}
    if ($line -match '\b(?:v[1-9]|o[1-9]|u\d+|s\d+)\b|^(?:call|label|sync|discard|dcl_)') {throw "Unsupported kernel side effect: $line"}
}
if ($loopDepth -ne 0 -or $returns -lt 1 -or $kernelBody[-1] -ne 'ret') {throw 'Kernel return/loop structure is unsupported.'}
if($shared -and ($returns -ne 1 -or @($kernelBody | Where-Object {$_ -eq 'sync_g_t'}).Count -ne 1 -or @($kernelBody | Where-Object {$_ -match '^store_structured u7\.'}).Count -ne 1)){throw 'Unexpected shared kernel exits, barriers or output stores.'}
$records=@(foreach ($v in $variants) {
    $original=Join-Path $validation ($v.Hash+'-original.bin')
    Copy-Item -LiteralPath (Join-Path $StudyDirectory ($v.Hash+'-cs.bin')) -Destination $original
    Run-ContactTool $assembler @('-d','-V',$original) (Join-Path $validation ($v.Hash+'-original.log'))
    $before=Read-Instructions (Join-Path $validation ($v.Hash+'-original.asm'))
    if($shared) {
        $proof=@($boundary.variants | Where-Object shaderHash -eq $v.Hash)
        $instructionHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes(($before -join "`n"))))
        if($proof.Count -ne 1 -or $proof[0].originalSha256 -ne $v.Sha -or $proof[0].instructionsSha256 -ne $instructionHash -or $proof[0].insertion -ne $v.Anchor -or -not $proof[0].commonOuterLightLoop){throw 'Native shared boundary does not match this shader.'}
        if(($before -join "`n") -match '\bg0\b|\bcb13\b|\bu7\b'){throw 'Shared-kernel native binding conflict.'}
    }
    $temp='dcl_temps '+$v.Temps
    $indexAnchor='and '+$v.Index+', '+$v.Index+', l(255)'
    foreach ($anchor in @($temp,$indexAnchor,$v.Anchor)) {
        if (@($before | Where-Object {$_ -ceq $anchor}).Count -ne 1) {throw "Non-unique native anchor in $($v.Hash): $anchor"}
    }
    if (($before -join "`n") -match '\bt120\b') {throw 'Native t120 conflict.'}
    # Three isolated registers: persistent input/index, kernel result, branch
    # scratch. Kernel r0... are shifted beyond these and all native temporaries.
    $inputReg='r'+$v.Temps;$resultReg='r'+($v.Temps+1);$scratch='r'+($v.Temps+2)
    $newTemps='dcl_temps '+($v.Temps+3+$kernelTemps)
    $translated=@(foreach ($line in $kernelBody) {
        if ($line -eq 'ret') {'break';continue}
        $line=[regex]::Replace($line,'\br(\d+)\b',{param($m) 'r'+([int]$m.Groups[1].Value+$v.Temps+3)})
        if($shared) {
            $line=$line.Replace('cb13[0].',$inputReg+'.')
            if($line -match '^store_structured u7.x, r\d+\.[xyzw], l\(0\), (r\d+\.[xyzw])$'){$line='mov '+$resultReg+'.x, '+$Matches[1]}
        }
        $line=$line.Replace('v0.',$inputReg+'.').Replace('o0.',$resultReg+'.')
        if ($v.Depth -eq 5) {$line=[regex]::Replace($line,'\bt4\b','t5')}
        $line
    })
    $block=@(
        "ld_indexable(texture1d)(float,float,float,float) $scratch.x, l(31, 0, 0, 0), t120.xyzw"
        "eq $scratch.x, $scratch.x, l(1.000000)"
        "if_nz $scratch.x"
        "mov $resultReg.x, l(1.000000)"
        # Compare the SIX actual contribution lanes, not their sum or the
        # unmasked sentinel lanes. +/-zero both bypass; negative values do not.
        ('ne '+$scratch+'.xyz, '+$v.Diffuse+'x, l(0, 0, 0, 0)')
        "or $scratch.x, $scratch.x, $scratch.y"
        "or $scratch.x, $scratch.x, $scratch.z"
        ('ne '+$scratch+'.yzw, '+$v.Specular.Split('.')[0]+'.'+$v.Specular.Split('.')[1][0]+$v.Specular.Split('.')[1]+', l(0, 0, 0, 0)')
        "or $scratch.y, $scratch.y, $scratch.z"
        "or $scratch.y, $scratch.y, $scratch.w"
        "or $scratch.x, $scratch.x, $scratch.y"
        "if_nz $scratch.x"
        "utof $inputReg.xy, r1.xyxx"
        'loop'
    )+$translated+@(
        'endloop'
        # Avoid multiplying native values by one on fail-closed paths.
        "lt $scratch.x, $resultReg.x, l(1.000000)"
        "if_nz $scratch.x"
        # Destination masks select physical lanes, not packed RGB channels.
        # Always read identity lanes: xzw/xzw or yzw/yzw would permute values.
        ('mul '+$v.Diffuse+', '+$v.Diffuse.Split('.')[0]+'.xyzw, '+$resultReg+'.xxxx')
        ('mul '+$v.Specular+', '+$v.Specular.Split('.')[0]+'.xyzw, '+$resultReg+'.xxxx')
        'endif'
        'endif'
        'endif'
    )
    if($shared) {
        # Common native light-loop boundary, OUTSIDE the varying contribution
        # guard. Zero-contribution neighbors may supply another lane's ray.
        # FXC removes the helper's terminal barrier in a one-call wrapper;
        # explicitly restore it before the next native light can write g0.
        $sharedRun=@("iadd $inputReg.xy, r1.xyxx, -vThreadIDInGroup.xyxx",'loop')+$translated+@('endloop','sync_g_t')
        $gateStart=[array]::IndexOf($block,('ne '+$scratch+'.xyz, '+$v.Diffuse+'x, l(0, 0, 0, 0)'))
        $pixelInput=[array]::IndexOf($block,"utof $inputReg.xy, r1.xyxx")
        $applyStart=[array]::IndexOf($block,"lt $scratch.x, $resultReg.x, l(1.000000)")
        if($gateStart -lt 0 -or $pixelInput -lt $gateStart -or $applyStart -lt $pixelInput){throw 'Unexpected common block layout.'}
        $block=$block[0..($gateStart-1)]+$sharedRun+$block[$gateStart..($pixelInput-1)]+$block[$applyStart..($block.Count-1)]
    }
    $after=[Collections.Generic.List[string]]::new()
    $originMap=[Collections.Generic.List[int]]::new()
    for ($i=0;$i -lt $before.Count;$i++) {
        $line=$before[$i]
        if ($line -eq $temp) {
            $after.Add('dcl_resource_texture1d (float,float,float,float) t120');$originMap.Add(-1)
            if($shared){$after.Add('dcl_tgsm_structured g0, 4, 256');$originMap.Add(-1)}
            $line=$newTemps
        }
        if ($line -eq $v.Anchor) {foreach($insert in $block){$after.Add($insert);$originMap.Add(-1)}}
        $after.Add($line);$originMap.Add($i)
        if ($line -eq $indexAnchor) {$after.Add("mov $inputReg.z, $($v.Index)");$originMap.Add(-1)}
    }
    $candidateAsm=Join-Path $validation ($v.Hash+'-contact.asm')
    [IO.File]::WriteAllText($candidateAsm,($after -join "`n")+"`n",$utf8)
    Run-ContactTool $assembler @('-a','--copy-reflection',$original,$candidateAsm) (Join-Path $validation ($v.Hash+'-assemble.log'))
    $binary=Join-Path $validation ($v.Hash+'-contact.shdr')
    $verify=Join-Path $validation ($v.Hash+'-verify.bin')
    Copy-Item -LiteralPath $binary -Destination $verify
    Run-ContactTool $assembler @('-d','-V',$verify) (Join-Path $validation ($v.Hash+'-verify.log'))
    $verified=Read-Instructions (Join-Path $validation ($v.Hash+'-verify.asm'))
    if($shared -and (@($verified | Where-Object {$_ -eq 'sync_g_t'}).Count -ne 2 -or ($verified -join "`n") -match '\bcb13\b|\bu7\b')){throw 'Shared candidate barrier count or temporary binding elimination failed.'}
    foreach ($destination in @($v.Diffuse,$v.Specular)) {
        $identityMultiply='mul '+$destination+', '+$destination.Split('.')[0]+'.xyzw, '+$resultReg+'.xxxx'
        if (@($verified | Where-Object {$_ -ceq $identityMultiply}).Count -ne 1) {
            throw "Masked contribution identity-lane check failed: $identityMultiply"
        }
    }
    # The assembler expands short swizzles. Compare reassembled token streams,
    # not cosmetic source spelling, to check every untouched native instruction.
    $oldSections=Read-DxbcSections $original;$newSections=Read-DxbcSections $binary
    if (($oldSections.Keys -join ',') -cne ($newSections.Keys -join ',')) {throw 'DXBC sections changed.'}
    $codeTag=if($oldSections.Contains('SHEX')){'SHEX'}else{'SHDR'}
    foreach($name in $oldSections.Keys) {
        if ($name -ne $codeTag -and [Convert]::ToHexString($oldSections[$name]) -cne [Convert]::ToHexString($newSections[$name])) {throw "Native metadata changed: $name"}
    }
    $oldTokens=Read-InstructionTokens $oldSections[$codeTag]
    $newTokens=Read-InstructionTokens $newSections[$codeTag]
    if ($newTokens.Count -ne $after.Count-1 -or $verified.Count -ne $after.Count) {throw 'Instruction accounting mismatch.'}
    $preserved=0
    for($i=1;$i -lt $after.Count;$i++) {
        $originalIndex=$originMap[$i]
        if($originalIndex -lt 0 -or $before[$originalIndex] -eq $temp){continue}
        if($oldTokens[$originalIndex-1] -cne $newTokens[$i-1]) {throw "Native instruction changed: $($v.Hash) at $originalIndex"}
        $preserved++
    }
    if ($preserved -ne $oldTokens.Count-1) {throw 'Not all native instructions preserved.'}
    # Reassemble the verified listing and require binary equality as an
    # independent round-trip check of injected instructions, including precise.
    Run-ContactTool $assembler @('-a','--copy-reflection',$verify,(Join-Path $validation ($v.Hash+'-verify.asm'))) (Join-Path $validation ($v.Hash+'-roundtrip.log'))
    if ((Get-FileHash -LiteralPath (Join-Path $validation ($v.Hash+'-verify.shdr'))).Hash -ne (Get-FileHash -LiteralPath $binary).Hash) {throw 'Patched binary round trip changed.'}
    # Execute the EXACT injected instruction block separately from the native
    # tiled renderer. Distinct RGBA sentinels catch masked-lane permutations.
    $fixture=@('cs_5_0','dcl_globalFlags refactoringAllowed',
        'dcl_constantbuffer CB0[2], immediateIndexed',('dcl_constantbuffer CB1['+$expectedViewRows+'], immediateIndexed'),
        'dcl_constantbuffer CB4[768], dynamicIndexed','dcl_constantbuffer CB7[3], immediateIndexed',
        'dcl_resource_texture2d (float,float,float,float) t1',
        'dcl_resource_texture2d (float,float,float,float) t2',
        ('dcl_resource_texture2d (float,float,float,float) t'+$v.Depth),
        'dcl_resource_texture1d (float,float,float,float) t120','dcl_uav_structured u0, 4',
        $newTemps,$(if($shared){'dcl_input vThreadIDInGroup.xy';'dcl_tgsm_structured g0, 4, 256';'dcl_thread_group 16, 16, 1'}else{'dcl_thread_group 1, 1, 1'}),'ftou r1.xy, cb7[0].xyxx',
        $(if($shared){'iadd r1.xy, r1.xyxx, vThreadIDInGroup.xyxx'}),
        ('mov '+$v.Index+', cb7[0].zzzz'),$indexAnchor,
        ('mov '+$inputReg+'.z, '+$v.Index),
        ('mov '+$v.Diffuse.Split('.')[0]+'.xyzw, cb7[1].xyzw'),
        ('mov '+$v.Specular.Split('.')[0]+'.xyzw, cb7[2].xyzw'),
        ('mov '+$resultReg+'.x, l(1.000000)'))+$block+@(
        ('store_structured u0.x, l(0), l(0), '+$resultReg+'.xxxx'))
    $lanes='xyzw'
    for($lane=0;$lane -lt 4;$lane++) {
        $swizzle=[string]$lanes[$lane]*4
        $fixture+=('store_structured u0.x, l('+($lane+1)+'), l(0), '+$v.Diffuse.Split('.')[0]+'.'+$swizzle)
        $fixture+=('store_structured u0.x, l('+($lane+5)+'), l(0), '+$v.Specular.Split('.')[0]+'.'+$swizzle)
    }
    if($shared) {
        # Each native 16x16 lane has a separate nine-float output record.
        $fixture=@($fixture | Where-Object {$_} | ForEach-Object {
            if($_ -match '^store_structured u0.x, l\((\d+)\), l\(0\), (.+)$') {
                $slot=[int]$Matches[1];$value=$Matches[2]
                "imad $scratch.w, vThreadIDInGroup.y, l(16), vThreadIDInGroup.x"
                "imad $scratch.w, $scratch.w, l(9), l($slot)"
                "store_structured u0.x, $scratch.w, l(0), $value"
            } else {$_}
        })
    } else {$fixture=@($fixture | Where-Object {$_})}
    $fixture+='ret'
    $fixtureAsm=Join-Path $validation ($v.Hash+'-fixture.asm')
    [IO.File]::WriteAllText($fixtureAsm,($fixture -join "`n")+"`n",$utf8)
    Run-ContactTool $assembler @('-a',$fixtureAsm) (Join-Path $validation ($v.Hash+'-fixture.log'))
    if($shared) {
        # A real loop within ONE dispatch reuses g0 for eight light evaluations.
        # The persistent loop register exists only in this fixture, beyond every
        # native/translated temporary. The exact production block is unchanged.
        $repeatReg='r'+($v.Temps+3+$kernelTemps)
        $repeatMixedInitialized=$false
        $repeatFixture=@(foreach($line in $fixture) {
            if($line -eq $newTemps) { 'dcl_temps '+($v.Temps+4+$kernelTemps);continue }
            if($line -eq ('mov '+$v.Index+', cb7[0].zzzz')) {
                "mov $repeatReg.x, l(0)"
                'loop'
                "uge $repeatReg.y, $repeatReg.x, l(8)"
                "breakc_nz $repeatReg.y"
                "and $repeatReg.z, $repeatReg.x, l(1)"
                ('iadd '+$v.Index+', cb7[0].zzzz, '+$repeatReg+'.zzzz')
                continue
            }
            if(-not $repeatMixedInitialized -and $line -eq ('mov '+$resultReg+'.x, l(1.000000)')) {
                $repeatMixedInitialized=$true
                "iadd $repeatReg.y, vThreadIDInGroup.x, vThreadIDInGroup.y"
                "iadd $repeatReg.y, $repeatReg.y, $repeatReg.x"
                "and $repeatReg.y, $repeatReg.y, l(3)"
                "ieq $repeatReg.z, $repeatReg.y, l(0)"
                "if_nz $repeatReg.z"
                ('mov '+$v.Diffuse+', l(0, 0, 0, 0)')
                'endif'
                "ieq $repeatReg.z, $repeatReg.y, l(1)"
                "if_nz $repeatReg.z"
                ('mov '+$v.Specular+', l(0, 0, 0, 0)')
                'endif'
                "ieq $repeatReg.z, $repeatReg.y, l(2)"
                "if_nz $repeatReg.z"
                ('mov '+$v.Diffuse+', l(0x80000000, 0x80000000, 0x80000000, 0x80000000)')
                ('mov '+$v.Specular+', l(0x80000000, 0x80000000, 0x80000000, 0x80000000)')
                'endif'
            }
            if($line -match '^store_structured u0.x, r\d+\.w, l\(0\),') {
                "imad $scratch.w, $repeatReg.x, l(2304), $scratch.w"
            }
            if($line -eq 'ret') {
                "iadd $repeatReg.x, $repeatReg.x, l(1)"
                'endloop'
            }
            $line
        })
        if(-not ($repeatFixture -join "`n").Contains($block -join "`n")){throw 'Repeated fixture changed the exact production injection block.'}
        $repeatAsm=Join-Path $validation ($v.Hash+'-repeat-fixture.asm')
        [IO.File]::WriteAllText($repeatAsm,($repeatFixture -join "`n")+"`n",$utf8)
        Run-ContactTool $assembler @('-a',$repeatAsm) (Join-Path $validation ($v.Hash+'-repeat-fixture.log'))
    }
    [ordered]@{
        shaderHash=$v.Hash;stage='cs';originalSha256=$v.Sha
        candidateSha256=(Get-FileHash -LiteralPath $binary).Hash
        originalInstructionsPreserved=$preserved;originalTemporaryCount=$v.Temps;newTemporaryCount=($v.Temps+3+$kernelTemps)
        depthSlot=$v.Depth;indexCapture=$indexAnchor;insertion=$v.Anchor
        diffuse=$v.Diffuse;specular=$v.Specular;maskedContributionIdentityLanes=$true;roundTripByteIdentical=$true
        binary=('validation/'+$v.Hash+'-contact.shdr');assembly=('validation/'+$v.Hash+'-contact.asm')
        injectionFixture=('validation/'+$v.Hash+'-fixture.shdr');fixtureInputRows=3;zeroNativeContributionGate=$true
        sharedGroup=$shared;fixtureThreads=$(if($shared){256}else{1});fixtureOutputFloats=$(if($shared){2304}else{9});sharedMemoryBytes=$(if($shared){1024}else{0})
        repeatedFixture=$(if($shared){'validation/'+$v.Hash+'-repeat-fixture.shdr'}else{$null})
        repeatedLightIterations=$(if($shared){8}else{0});repeatedOutputFloats=$(if($shared){18432}else{0})
    }
})
$report=[ordered]@{
    schemaVersion=1;generatedAtUtc=[DateTime]::UtcNow.ToString('o');purpose='Offline per-light contact-shadow integration'
    status='assembled-native-runtime-unverified';runtimeEligible=$false;installed=$false
    implementation=$Implementation;reconstruction=$Reconstruction
    sourceKernelSha256=(Get-FileHash -LiteralPath $kernelSource).Hash
    effectSourceSha256=(Get-FileHash -LiteralPath $effectSource).Hash
    sources=@(foreach($path in @('src/Effects/Lighting/ContactShadowCommon.hlsl','src/Effects/Lighting/ContactShadows.hlsl','src/Effects/Lighting/RebirthContactShadows.hlsl','src/ThirdParty/ShaderInjector/RebirthContactRay.hlsl','src/ThirdParty/ShaderInjector/RebirthContactNoise.hlsl','src/ThirdParty/ShaderInjector/provenance.json','src/Adapters/FF7RemakeIntergrade/ContactShadowKernel_ps.hlsl','src/Adapters/FF7RemakeIntergrade/RebirthContactShadowKernel_ps.hlsl')) {
        @{path=$path;sha256=(Get-FileHash -LiteralPath (Join-Path $repo $path)).Hash}
    })
    sampleCount=$Samples;variants=$records;generatorSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    zeroNativeContributionGate=$(if($shared){'Zero native lanes bypass multiplication; their threads still participate in shared ray evaluation and barriers'}else{'Skip ray evaluation only when all six native diffuse/specular contribution lanes compare equal to zero'})
    control='IniParams row31: x=enabled(1), y=light index(-1 means all), z=strength, w=ray length'
    baseline='All native instruction tokens retained except temporary declaration; branch off skips contribution writes. Index snapshot uses isolated added register.'
    preserved=@('native BRDF','shadow maps','material/screen/capsule occlusion','per-light attenuation','diffuse-luminance output alpha calculation','tile specialization')
    remaining=@('D3D11 shader creation validation','adapter numeric/resource tests','live view/light constants and reprojection check','selected-light capture and visible contribution','neutral live comparison','motion and GPU-cost testing')
}
$report.sources+=@(@{path='src/Adapters/FF7RemakeIntergrade/RebirthContactInputMapping.hlsl';sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'src/Adapters/FF7RemakeIntergrade/RebirthContactInputMapping.hlsl')).Hash})
$report.sources+=@(foreach($path in @('src/ThirdParty/ShaderInjector/RebirthContactReconstruction.hlsl','src/Adapters/FF7RemakeIntergrade/RebirthContactReconstructedKernel_ps.hlsl')) {
    @{path=$path;sha256=(Get-FileHash -LiteralPath (Join-Path $repo $path)).Hash}
})
$report.reconstructionLimits='RecomputeQuad is offline: provisional phase uses native mod8, neighbors use explicit depth/normal reconstruction; no raster-helper coverage or live cost equivalence. Up to two neighbor traces for untraced pixels; no thread barriers.'
if($shared) {
    $report.sources+=@(foreach($path in @('src/Adapters/FF7RemakeIntergrade/RebirthContactShared.hlsl','src/Adapters/FF7RemakeIntergrade/RebirthContactSharedKernel_cs.hlsl','tools/audit_rebirth_shared_boundary.py')){@{path=$path;sha256=(Get-FileHash -LiteralPath (Join-Path $repo $path)).Hash}})
    $report.sharedBoundarySha256=(Get-FileHash -LiteralPath (Join-Path $SharedBoundaryDirectory 'boundary.json')).Hash
    $report.reconstructionLimits='SharedQuad is offline: requires audited group-uniform boundary, 16x16 threads and even viewport origin (odd is neutral). All lanes participate before contribution gating. One compiled barrier plus explicit terminal barrier protects reuse by next light. Native mod8 phase/raster-helper equivalence and live cost unverified.'
    $report.remaining=@('Exact 256-thread assembled fixture execution including repeated light iterations','Matched captured shared-vs-recomputed replay','Odd-origin neutrality and partial-group checks','Native temporal phase progression','Live quality and hardware cost; prior motion regression is not resolved')
}
[IO.File]::WriteAllText((Join-Path $output 'candidate.json'),(($report | ConvertTo-Json -Depth 8)+"`n"),$utf8)
[pscustomobject]@{Result='offline-contact-candidate-assembled';Variants=$records.Count;Samples=$Samples;RuntimeEligible=$false;Output=$output}
