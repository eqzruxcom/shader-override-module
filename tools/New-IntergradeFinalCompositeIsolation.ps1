[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$allowed = Join-Path $repo 'artifacts\generated-runtime'
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if (-not $output.StartsWith($allowed+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Isolation output must stay below generated-runtime.' }
if (Test-Path -LiteralPath $output) { throw 'Isolation output exists; preserve previous evidence.' }
$validation = Join-Path $output 'validation'
$null = & (Join-Path $PSScriptRoot 'New-IntergradeFinalCompositeCandidate.ps1') -OutputDirectory $validation
$assembler = Join-Path $repo 'artifacts\shader-assembler-build\bin\cmd_Decompiler.exe'
$utf8 = [Text.UTF8Encoding]::new($false)
$source = [IO.File]::ReadAllText((Join-Path $validation 'original.asm')).Replace("`r`n","`n")
$declaration = 'dcl_resource_texture1d (float,float,float,float) t120'
$anchor = '  mul r0.w, r1.w, cb0[25].y'
$block = @'
  ld_indexable(texture1d)(float,float,float,float) r12.x, l(30, 0, 0, 0), t120.xyzw
  eq r12.x, r12.x, l(1.000000)
  if_nz r12.x
    mul r2.xyz, r2.xyzx, l(0.500000, 0.500000, 0.500000, 0.000000)
  endif
'@
$block = $block.Replace("`r`n","`n")
foreach ($unique in @('dcl_temps 12','dcl_input_ps_siv linear noperspective v0.xy, position',$anchor)) {
    if ([regex]::Matches($source,[regex]::Escape($unique)).Count -ne 1) { throw "Expected unique assembly anchor: $unique" }
}
if ($source -match '\b(?:r12|t120)\b') { throw 'Reserved diagnostic register is already used.' }
$modified = $source.Replace('dcl_input_ps_siv linear noperspective v0.xy, position',$declaration+"`n"+'dcl_input_ps_siv linear noperspective v0.xy, position').Replace('dcl_temps 12','dcl_temps 13').Replace($anchor,$block+"`n"+$anchor)
$authored = Join-Path $validation 'scene-toggle.asm'
[IO.File]::WriteAllText($authored,$modified,$utf8)
$messages = & $assembler -a --copy-reflection (Join-Path $validation 'original.bin') $authored 2>&1
if ($LASTEXITCODE -ne 0) { throw "Toggle assembly failed: $messages" }
[IO.File]::WriteAllText((Join-Path $validation 'toggle-assembly.log'),($messages | Out-String),$utf8)
$candidate = Join-Path $validation 'scene-toggle.shdr'
$verify = Join-Path $validation 'scene-toggle-verified.bin'
Copy-Item -LiteralPath $candidate -Destination $verify
$messages = & $assembler -d -V $verify 2>&1
if ($LASTEXITCODE -ne 0) { throw "Toggle bytecode validation failed: $messages" }
[IO.File]::WriteAllText((Join-Path $validation 'toggle-validation.log'),($messages | Out-String),$utf8)
$verified = [IO.File]::ReadAllText((Join-Path $validation 'scene-toggle-verified.asm'))
function Get-Lines([string]$Text) {
    return ,@($Text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('//') })
}
$before = Get-Lines $source
$after = Get-Lines $verified
$expected = Get-Lines $modified
if (($after -join "`n") -cne ($expected -join "`n")) { throw 'Toggle disassembly differs from authored instructions.' }
$removed = $modified.Replace($declaration+"`n",'').Replace('dcl_temps 13','dcl_temps 12').Replace($block+"`n",'')
if ($removed -cne $source) { throw 'Off-path reconstruction changed original assembly.' }
# Preserve the exact original instruction bytes, except the declared temp count.
function Get-Sections([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ([Text.Encoding]::ASCII.GetString($bytes,0,4) -ne 'DXBC') { throw 'Invalid DXBC.' }
    $result = [ordered]@{}
    $count = [BitConverter]::ToUInt32($bytes,28)
    for ($i=0; $i -lt $count; $i++) {
        $offset = [BitConverter]::ToUInt32($bytes,32+4*$i)
        $tag = [Text.Encoding]::ASCII.GetString($bytes,$offset,4)
        $length = [BitConverter]::ToUInt32($bytes,$offset+4)
        $result[$tag] = [byte[]]$bytes[($offset+8)..($offset+7+$length)]
    }
    return $result
}
function Get-Tokens([byte[]]$Code) {
    $result = [Collections.Generic.List[string]]::new()
    $offset = 8
    while ($offset -lt $Code.Length) {
        $length = (([BitConverter]::ToUInt32($Code,$offset) -shr 24) -band 127)*4
        if ($length -eq 0 -or $offset+$length -gt $Code.Length) { throw 'Invalid instruction size.' }
        $result.Add([Convert]::ToHexString([byte[]]$Code[$offset..($offset+$length-1)]))
        $offset += $length
    }
    return ,$result.ToArray()
}
$originalSections = Get-Sections (Join-Path $validation 'original.bin')
$patchedSections = Get-Sections $candidate
if (($originalSections.Keys -join ',') -cne ($patchedSections.Keys -join ',')) { throw 'DXBC section set changed.' }
$tag = if ($originalSections.Contains('SHEX')) { 'SHEX' } else { 'SHDR' }
foreach ($name in $originalSections.Keys) {
    if ($name -ne $tag -and [Convert]::ToHexString($originalSections[$name]) -cne [Convert]::ToHexString($patchedSections[$name])) { throw "Metadata changed: $name" }
}
$beforeTokens = Get-Tokens $originalSections[$tag]
$afterTokens = Get-Tokens $patchedSections[$tag]
$skip = [Collections.Generic.HashSet[int]]::new()
$null = $skip.Add([Array]::IndexOf($after,$declaration)-1)
$blockStart = [Array]::IndexOf($after,(Get-Lines $block)[0])-1
if ($blockStart -lt 0) { throw 'Cannot locate diagnostic block.' }
for ($i=0; $i -lt 5; $i++) { $null = $skip.Add($blockStart+$i) }
$j=0
$verifiedOriginalTokens=0
for ($i=0; $i -lt $afterTokens.Count; $i++) {
    if ($skip.Contains($i)) { continue }
    if ($before[$j+1] -ne 'dcl_temps 12') {
        if ($beforeTokens[$j] -cne $afterTokens[$i]) { throw "Original instruction bytes changed: $j" }
        $verifiedOriginalTokens++
    } elseif ($after[$i+1] -ne 'dcl_temps 13') { throw 'Unexpected temporary-register declaration.' }
    $j++
}
if ($j -ne $beforeTokens.Count -or $afterTokens.Count -ne $beforeTokens.Count+6 -or $verifiedOriginalTokens -ne 134) { throw 'Unexpected toggle instruction count.' }
$ini = @'
; Diagnostic only. OFF executes original mathematics within an ASM replacement.
; Not a true native-shader switch, not a replacement for the native tonemapper.
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
$payloads = [ordered]@{
    'Mods/UE4EffectsGenerated.ini' = $ini
    'ShaderFixes/41f1bf8b79d01319-ps.txt' = $modified
}
$files = @(foreach ($relative in $payloads.Keys) {
    $path = Join-Path $output $relative
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    [IO.File]::WriteAllText($path,$payloads[$relative].Replace("`r`n","`n").Replace("`n","`r`n")+"`r`n",$utf8)
    [ordered]@{ relativePath=$relative; size=(Get-Item -LiteralPath $path).Length; sha256=(Get-FileHash -LiteralPath $path).Hash }
})
$manifest = [ordered]@{
    schemaVersion=1; adapterId='FF7RemakeIntergradeFinalCompositeIsolation'; renderer='D3D11'
    executable=[ordered]@{ name='ff7remake_.exe'; sha256='25B54C345C94EE9F6C6876B9C7537A69E6B0EEF25F322207C32A8DDCEE816635' }
    licensedRegexDependency=$false; diagnosticOnly=$true; runtimeEligible=$false; failClosed=$true
    status='offline-verified-live-boundary-pending'; shaderHash='41f1bf8b79d01319'
    offState='original-math-in-assembly-replacement'; trueNativeShaderToggle=$false
    offMathOriginalTokensPreserved=$true; neutralRoundTripBinaryIdentical=$true
    originalTokensByteIdentical=$verifiedOriginalTokens; addedInstructionOrDeclarationCount=6
    alteredOriginalDeclarations=@('dcl_temps 12 -> 13'); originalMathChanges=0
    effect='half-numeric-scene-brightness-after-native-color-mapping-before-overlay'
    replacesNativeTonemapper=$false; visualUiPreservation='pending'; visualSceneResponse='pending'
    control=[ordered]@{ key='VK_PAGEDOWN'; variable='$ue4fx_final_scene_ab'; default=0; values=@(0,1); labels=@('original-math','scene-half'); iniParam='x30' }
    requiredLivePreconditions=@('no other active mod INIs','no other ShaderFixes replacements','preserve existing d3dx hunting settings','F10 then verify exact ASM reload succeeded')
    candidateSha256=(Get-FileHash -LiteralPath $candidate).Hash
    originalSha256=(Get-FileHash -LiteralPath (Join-Path $validation 'original.bin')).Hash
    files=$files
}
$manifestPath = Join-Path $output 'runtime-manifest.json'
[IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 8)+[Environment]::NewLine,$utf8)
[pscustomobject]@{ Output=$output; Manifest=$manifestPath; VerifiedOriginalTokens=$verifiedOriginalTokens; TrueNativeShaderToggle=$false; CandidateSha256=$manifest.candidateSha256 }
