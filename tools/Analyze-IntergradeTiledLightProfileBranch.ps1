[CmdletBinding()]
param(
    [string]$ComputeMirrorManifest = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-live-compute-census-20260903-v3\manifest.json'),
    [string]$TiledLightReport = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-tiled-light-dispatch-sequence-20260904.json'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\intergrade-tiled-light-profile-branch-20260904.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must remain under artifacts: $output"
}
foreach ($path in @($ComputeMirrorManifest,$TiledLightReport)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required input is missing: $path" }
}

$manifest = Get-Content -Raw -LiteralPath $ComputeMirrorManifest | ConvertFrom-Json
$dispatch = Get-Content -Raw -LiteralPath $TiledLightReport | ConvertFrom-Json
if ($dispatch.detector -ne 'ff7-remake-tiled-light-dispatch-sequence-v1') { throw 'Unexpected tiled-light dispatch report' }
$hashes = @($dispatch.canonicalSequence.hash)
if ($hashes.Count -ne 5) { throw "Expected five tiled-light variants; found $($hashes.Count)" }

$variants = foreach ($hash in $hashes) {
    $record = @($manifest.shaders | Where-Object shader -eq "$hash-cs")
    if ($record.Count -ne 1) { throw "Expected one compute mirror for $hash; found $($record.Count)" }
    $path = [IO.Path]::GetFullPath($record[0].mirror)
    $text = Get-Content -Raw -LiteralPath $path

    $profileSamples = [regex]::Matches($text,'(?m)^\s*sample_l_indexable\(texture2d\)\(float,float,float,float\) r(?<sampleReg>\d+)\.[xyzw], r(?<coordReg>\d+)\.xyxx, t(?<slot>\d+)\.yzwx, s(?<sampler>\d+), l\(0\.000000\)$')
    if ($profileSamples.Count -eq 0) { throw "No angular profile-atlas sample found in $hash" }
    $profileSample = $profileSamples[$profileSamples.Count-1]
    $slot = [int]$profileSample.Groups['slot'].Value
    $sampleRegister = [int]$profileSample.Groups['sampleReg'].Value
    $coordRegister = [int]$profileSample.Groups['coordReg'].Value
    $sampler = [int]$profileSample.Groups['sampler'].Value

    $checks = [ordered]@{
        lightRecordStride80 = $text -match '(?m)^dcl_resource_structured t\d+, 80$'
        profileTextureDeclared = $text -match "(?m)^dcl_resource_texture2d \(float,float,float,float\) t$slot`$"
        profileFlagLowTwoBits = $text -match '(?m)^\s*and r\d+\.[xyzw], l\(3\), cb3\[r\d+\.[xyzw] \+ 768\]\.x$'
        conditionalProfileBranch = $text -match '(?m)^\s*and r\d+\.[xyzw], l\(3\), cb3\[r\d+\.[xyzw] \+ 768\]\.x\r?\n\s*if_nz r\d+\.[xyzw]$'
        lightDirectionDot = $text -match '(?m)^\s*dp3 r\d+\.[xyzw], r\d+\.xyzx, -cb3\[r\d+\.[xyzw] \+ 0\]\.xyzx$'
        angularAcosApproximation = $text -match '(?m)^\s*mad r\d+\.[xyzw], -r\d+\.[xyzw], l\(0\.318309873\), l\(1\.000000\)$'
        profileIndexFromLightRecord = $text -match '(?m)^\s*utof r\d+\.[xyzw], cb3\[r\d+\.[xyzw] \+ 768\]\.z$'
        profileRowCenterOffset = $text -match '(?m)^\s*add r\d+\.[xyzw], r\d+\.[xyzw], l\(0\.500000\)$'
        profileAtlasHeightScale = $text -match '(?m)^\s*mul r\d+\.[xyzw], r\d+\.[xyzw], cb0\[0\]\.w$'
        profileSample = $profileSample.Success
        sampleModulatesLightColor = $text -match "(?m)^\s*mul r\d+\.xyz, r$sampleRegister\.[xyzw]{4}, cb4\[r\d+\.[xyzw] \+ 512\]\.xyzx`$"
    }
    if ($checks.Values -contains $false) { throw "Profile-branch invariant failed for $hash" }

    $priorLightingMatch = [regex]::Match($text,'(?m)^\s*ld_indexable\(texture2d\)\(float,float,float,float\) r0\.xyzw, r\d+\.xyzz, t(?<slot>\d+)\.xyzw\r?\n\s*add r\d+\.xyz[\s\S]{0,240}?^\s*mad r0\.xyzw, r0\.xyzw, cb1\[128\]\.yyyy, r\d+\.xyzw$')
    if (-not $priorLightingMatch.Success) { throw "Prior-lighting read/modify/write chain not found in $hash" }
    $priorLightingSlot = [int]$priorLightingMatch.Groups['slot'].Value

    [ordered]@{
        hash = $hash
        profileTextureSlot = $slot
        profileSamplerSlot = $sampler
        profileCoordinateRegister = "r$coordRegister.xy"
        outputComposition = 'read-modify-write-existing-lighting'
        priorLightingTextureSlot = $priorLightingSlot
        checks = $checks
        assemblyPath = [IO.Path]::GetRelativePath($root,$path).Replace('\','/')
        assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    }
}

$lowerRegister = @($variants | Where-Object profileTextureSlot -eq 7)
$higherRegister = @($variants | Where-Object profileTextureSlot -eq 8)
if (@($variants | Where-Object outputComposition -ne 'read-modify-write-existing-lighting').Count -ne 0) { throw 'All five variants must read, blend, and rewrite existing lighting' }
if ($lowerRegister.Count -ne 2 -or (@($lowerRegister.priorLightingTextureSlot | Sort-Object -Unique) -join ',') -ne '8') { throw 'Lower-register profile/prior-lighting pair changed' }
if ($higherRegister.Count -ne 3 -or (@($higherRegister.priorLightingTextureSlot | Sort-Object -Unique) -join ',') -ne '9') { throw 'Higher-register profile/prior-lighting pair changed' }
if (@($variants | Where-Object { $_.priorLightingTextureSlot -ne ($_.profileTextureSlot + 1) }).Count -ne 0) { throw 'Profile and prior-lighting slots are no longer adjacent' }

$report = [ordered]@{
    schemaVersion = 1
    detector = 'ff7-remake-tiled-light-angular-profile-branch-v1'
    scope = 'Read-only proof of the data-driven angular light-profile branch and prior-lighting composition shared by all five accepted tiled surface-light evaluators.'
    variantCount = $variants.Count
    variants = @($variants)
    familyInvariant = [ordered]@{
        conditionalFlag = 'low two bits of per-light cb3[index+768].x'
        angularCoordinate = 'acos-like mapping of dot(pixel-to-light, negative light direction) into normalized profile U'
        profileIndex = 'per-light cb3[index+768].z plus half-texel center, scaled by cb0[0].w into profile-atlas V'
        modulation = 'sampled scalar multiplies cb4[index+512].xyz light color'
        outputComposition = 'all five variants read, blend, and rewrite existing lighting'
        lowerRegisterPair = 'profile atlas t7, prior lighting t8 (two variants)'
        higherRegisterPair = 'profile atlas t8, prior lighting t9 (three variants)'
        slotRelationship = 'prior lighting is always profile atlas slot plus one'
    }
    classification = [ordered]@{
        provenRole = 'data-driven angular light-profile atlas evaluation inside the shared tiled-light family'
        iesRelationship = 'This is the native structural mechanism required for UE4 IES-style profiled local lights; it is integrated per light rather than compiled as a separate shader family.'
        runtimeActivation = 'not proven for the current red beacon because the per-light flag values and indirect tile-list contents were not captured'
        directionalOwnership = 'unchanged and still unproven; the profile branch does not identify the infinite/non-radial branch as directional'
    }
    conclusions = @(
        'Do not search for a separate Remake IES shader hash before checking the shared evaluator light-record flags.',
        'Do not label t9 as an IES texture in the three higher-register variants; t9 is prior lighting there, while the profile atlas is t8.',
        'The other two variants retain the same operations with register-shifted bindings: profile atlas t7 and prior lighting t8.',
        'All five variants read, blend, and rewrite existing lighting; the prior two-versus-three composition split was a hard-coded-register analysis error.',
        'Any automatic contact or falloff transform must preserve the conditional profile sample, light-color modulation, and prior-lighting blend in all five variants.'
    )
    nextEvidenceGate = 'Capture or instrument the per-light cb3[index+768].x and .z values for a visibly patterned local light to prove live IES/profile activation.'
}

[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,(($report | ConvertTo-Json -Depth 14)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Variants=$variants.Count; LowerRegister=$lowerRegister.Count; HigherRegister=$higherRegister.Count; ReadModifyWrite=@($variants).Count; Output=$output }

