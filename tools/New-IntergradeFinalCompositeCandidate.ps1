[CmdletBinding()]
param(
    [string]$OriginalShaderPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\final-composite-study-20260830-220038-889\41f1bf8b79d01319-ps.bin'),
    [string]$AssemblerPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\shader-assembler-build\bin\cmd_Decompiler.exe'),
    [Parameter(Mandatory)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$allowed = Join-Path $repo 'artifacts'
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if (-not $output.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Candidate output must stay below workspace artifacts.' }
if (Test-Path -LiteralPath $output) { throw 'Candidate output exists; preserve previous evidence.' }
$originalPath = (Resolve-Path -LiteralPath $OriginalShaderPath).Path
$assembler = (Resolve-Path -LiteralPath $AssemblerPath).Path
$expectedHash = '8B7DB294C666E296D4974929E41892BE44D2BF6984B0BF1511788117A6E4C263'
if ((Get-FileHash -LiteralPath $originalPath -Algorithm SHA256).Hash -ne $expectedHash) { throw 'Final-composite original fingerprint changed.' }

function Get-DxbcSections([byte[]]$Bytes) {
    if ($Bytes.Length -lt 32 -or [Text.Encoding]::ASCII.GetString($Bytes,0,4) -ne 'DXBC') { throw 'Invalid DXBC header.' }
    if ([BitConverter]::ToUInt32($Bytes,24) -ne $Bytes.Length) { throw 'DXBC size mismatch.' }
    $count = [BitConverter]::ToUInt32($Bytes,28)
    if ($count -gt (($Bytes.Length-32)/4)) { throw 'Invalid DXBC section count.' }
    $sections = [ordered]@{}
    for ($i=0; $i -lt $count; $i++) {
        $offset = [long][BitConverter]::ToUInt32($Bytes,32+4*$i)
        if ($offset -lt (32+4*$count) -or $offset+8 -gt $Bytes.Length) { throw 'Invalid DXBC section offset.' }
        $tag = [Text.Encoding]::ASCII.GetString($Bytes,[int]$offset,4)
        $length = [long][BitConverter]::ToUInt32($Bytes,[int]$offset+4)
        if ($length -lt 1 -or $offset+8+$length -gt $Bytes.Length -or $sections.Contains($tag)) { throw 'Invalid or duplicate DXBC section.' }
        $sections[$tag] = [byte[]]$Bytes[($offset+8)..($offset+7+$length)]
    }
    return $sections
}

function Get-ShaderInstructions([byte[]]$Section) {
    if ($Section.Length -lt 8 -or ($Section.Length % 4) -ne 0 -or [BitConverter]::ToUInt32($Section,4)*4 -ne $Section.Length) { throw 'Invalid shader token length.' }
    $instructions = [Collections.Generic.List[object]]::new()
    $offset = 8
    while ($offset -lt $Section.Length) {
        $token = [BitConverter]::ToUInt32($Section,$offset)
        $length = (($token -shr 24) -band 127)*4
        if ($length -eq 0 -or $offset+$length -gt $Section.Length) { throw 'Unsupported or invalid instruction length.' }
        $instructions.Add([Convert]::ToHexString([byte[]]$Section[$offset..($offset+$length-1)]))
        $offset += $length
    }
    return ,$instructions.ToArray()
}

function Invoke-Assembler([string[]]$Arguments, [string]$LogPath) {
    $messages = & $assembler @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    [IO.File]::WriteAllText($LogPath, ($messages | Out-String), [Text.UTF8Encoding]::new($false))
    if ($exitCode -ne 0) { throw "Assembler failed; see $LogPath" }
}

[IO.Directory]::CreateDirectory($output) | Out-Null
$originalCopy = Join-Path $output 'original.bin'
Copy-Item -LiteralPath $originalPath -Destination $originalCopy
Invoke-Assembler @('-d','-V',$originalCopy) (Join-Path $output 'disassembly-validation.log')
$originalAsm = Join-Path $output 'original.asm'
Invoke-Assembler @('-a','--copy-reflection',$originalCopy,$originalAsm) (Join-Path $output 'neutral-assembly.log')
$neutral = Join-Path $output 'original.shdr'
if ((Get-FileHash -LiteralPath $neutral -Algorithm SHA256).Hash -ne $expectedHash) { throw 'Neutral round trip is not byte-identical.' }
$source = [IO.File]::ReadAllText($originalAsm).Replace("`r`n", "`n")
$anchor = '  mul r0.w, r1.w, cb0[25].y'
$insertion = '  mul r2.xyz, r2.xyzx, l(0.500000, 0.500000, 0.500000, 0.000000)'
if ([regex]::Matches($source,[regex]::Escape($anchor)).Count -ne 1) { throw 'Scene/overlay boundary is not unique.' }
if ($source -notmatch 'sample_l_indexable\(texture2d\).*r1.xyzw, r1.xyxx, t4.xyzw' -or $source -notmatch 'mad_sat r1.xyz, r2.xyzx, r0.wwww, r1.xyzx') { throw 'Expected overlay path is missing.' }
$modified = $source.Replace($anchor, $insertion + "`n" + $anchor)
$modifiedAsm = Join-Path $output 'scene-half.asm'
[IO.File]::WriteAllText($modifiedAsm,$modified,[Text.UTF8Encoding]::new($false))
Invoke-Assembler @('-a','--copy-reflection',$originalCopy,$modifiedAsm) (Join-Path $output 'scene-half-assembly.log')
$candidate = Join-Path $output 'scene-half.shdr'
# Disassemble in a separate basename: never overwrite the authored assembly.
$verifyBinary = Join-Path $output 'scene-half-verified.bin'
Copy-Item -LiteralPath $candidate -Destination $verifyBinary
Invoke-Assembler @('-d','-V',$verifyBinary) (Join-Path $output 'scene-half-validation.log')
$verifiedSource = [IO.File]::ReadAllText((Join-Path $output 'scene-half-verified.asm')).Replace("`r`n", "`n")
$getLines = { param($text) @($text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('//') }) }
$beforeLines = & $getLines $source
$afterLines = & $getLines $verifiedSource
$expectedLines = & $getLines $modified
if (($afterLines -join "`n") -cne ($expectedLines -join "`n")) { throw 'Assembled candidate differs from the one-instruction edit.' }
$instructionIndex = [Array]::IndexOf($beforeLines,$anchor.Trim()) - 1 # Exclude ps_5_0 version line.
if ($instructionIndex -lt 0) { throw 'Cannot locate insertion instruction index.' }
$originalSections = Get-DxbcSections ([IO.File]::ReadAllBytes($originalCopy))
$candidateSections = Get-DxbcSections ([IO.File]::ReadAllBytes($candidate))
if (($originalSections.Keys -join ',') -cne ($candidateSections.Keys -join ',')) { throw 'DXBC section layout changed.' }
$shaderTag = if ($originalSections.Contains('SHEX')) { 'SHEX' } elseif ($originalSections.Contains('SHDR')) { 'SHDR' } else { throw 'Missing shader code section.' }
foreach ($tag in $originalSections.Keys) {
    if ($tag -ne $shaderTag -and [Convert]::ToHexString($originalSections[$tag]) -cne [Convert]::ToHexString($candidateSections[$tag])) { throw "Non-code section changed: $tag" }
}
if ([BitConverter]::ToUInt32($originalSections[$shaderTag],0) -ne [BitConverter]::ToUInt32($candidateSections[$shaderTag],0)) { throw 'Shader version changed.' }
$beforeTokens = Get-ShaderInstructions $originalSections[$shaderTag]
$afterTokens = Get-ShaderInstructions $candidateSections[$shaderTag]
if ($afterTokens.Count -ne $beforeTokens.Count+1) { throw 'Expected exactly one added shader instruction.' }
for ($i=0; $i -lt $beforeTokens.Count; $i++) {
    $j = if ($i -lt $instructionIndex) { $i } else { $i+1 }
    if ($beforeTokens[$i] -cne $afterTokens[$j]) { throw "Original instruction bytes changed at index $i." }
}
$files = @(foreach ($file in @(Get-ChildItem -LiteralPath $output -File)) {
    [ordered]@{ name=$file.Name; size=$file.Length; sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
})
$manifest = [ordered]@{
    schemaVersion=1
    shaderHash='41f1bf8b79d01319'
    status='offline-verified-live-boundary-pending'
    diagnosticOnly=$true
    runtimeEligible=$false
    originalSha256=$expectedHash
    assemblerSha256=(Get-FileHash -LiteralPath $assembler -Algorithm SHA256).Hash
    neutralBinaryIdentical=$true
    changedOriginalInstructionCount=0
    addedInstructionCount=1
    addedInstructionIndex=$instructionIndex
    addedInstruction=$insertion.Trim()
    nonCodeSectionsIdentical=$true
    effect='scene-only-half-brightness-after-native-color-mapping-before-overlay'
    replacesNativeTonemapper=$false
    visualUiPreservation='pending'
    visualSceneResponse='pending'
    files=$files
}
$manifestPath = Join-Path $output 'candidate-manifest.json'
[IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Output=$output; Manifest=$manifestPath; NeutralBinaryIdentical=$true; UnchangedInstructions=$beforeTokens.Count; AddedInstructions=1; RuntimeEligible=$false }
