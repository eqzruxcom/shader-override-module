[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-strength-review'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if (-not $output.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase)) {
    throw "Strength-review output escaped the project: $output"
}

$compositePath = Join-Path $root 'src\Adapters\FF7RemakeIntergrade\R3DSSGICompositeE2AA_ps.hlsl'
$r3dEnvironmentPath = Join-Path $root 'reference\external\r3d\include\r3d\r3d_environment.h'
$rebirthReferencePath = Join-Path $root 'reference\ShaderInjector\ModifiedShaders\Includes\ComputeShaderPass_ReflectionEnvironment.hlsl'
$provenancePath = Join-Path $root 'reference\external\r3d-provenance.json'
$licensePath = Join-Path $root 'licenses\R3D-Zlib.txt'

$expectedHashes = [ordered]@{
    $compositePath = '6FA6F547AED1E490FD8D85DB465B7C70E9FEBD00B2319AF1B86AB9767199AA95'
    $r3dEnvironmentPath = '882340E9D75B7E2C9F0596FB6B41D592CE8040082681A1D1D5DCBA1EEB4685A0'
    $rebirthReferencePath = 'CEBA077018F2ACBD48A86AEF82CD603B8F219C71E501947AE3E88129A715164B'
    $provenancePath = 'D068EEFF8DC2EBB8C998AEB727874DAA651943997C36FC677B6927B80CF83249'
    $licensePath = '203D6697D1855CBF133B06D0C940B3CE956E06523C933AC423463249AA4666BB'
}

foreach ($entry in $expectedHashes.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Key -PathType Leaf)) { throw "Required strength-review input is missing: $($entry.Key)" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Key).Hash
    if ($actual -ne $entry.Value) { throw "Strength-review input drifted: $($entry.Key) expected $($entry.Value), found $actual" }
}
if (-not (Test-Path -LiteralPath $FxcPath -PathType Leaf)) { throw "FXC is missing: $FxcPath" }

$provenance = Get-Content -Raw -LiteralPath $provenancePath | ConvertFrom-Json
if ($provenance.commit -ne '3cb964171a0b90f1d0ec97e061b25021648eec65' -or $provenance.license -ne 'Zlib') {
    throw 'Pinned R3D provenance changed.'
}
$r3dEnvironment = Get-Content -Raw -LiteralPath $r3dEnvironmentPath
if ($r3dEnvironment -notmatch '(?s)\.ssgi\s*=\s*\{.*?\.intensity\s*=\s*1\.0f' -or
    $r3dEnvironment -notmatch 'Brightness of the indirect lighting.*default:\s*1\.0') {
    throw 'Pinned R3D donor-neutral SSGI intensity evidence changed.'
}
$rebirthReference = Get-Content -Raw -LiteralPath $rebirthReferencePath
if ($rebirthReference -notmatch 'float\s+ssgiBoost\s*=\s*MATH_PI' -or
    $rebirthReference -notmatch '(?s)SHADINGMODELID_HAIR.*?SHADINGMODELID_EYE.*?SHADINGMODELID_PREINTEGRATED_SKIN.*?ssgiBoost\s*=\s*1\.0f') {
    throw 'Pinned Rebirth material-specific SSGI boost evidence changed.'
}

$source = Get-Content -Raw -LiteralPath $compositePath
$strengthDeclaration = 'static const float AGENT2_DIAGNOSTIC_STRENGTH = 1.25;'
if ([regex]::Matches($source,[regex]::Escape($strengthDeclaration)).Count -ne 1) {
    throw 'Canonical Strong composite strength declaration changed.'
}
$oldComment = "    // F2 ON remains an intentionally visible diagnostic until live exposure,`r`n    // motion/disocclusion, and GPU timing captures support a promoted strength."
if (-not $source.Contains($oldComment)) {
    $oldComment = "    // F2 ON remains an intentionally visible diagnostic until live exposure,`n    // motion/disocclusion, and GPU timing captures support a promoted strength."
}
if (-not $source.Contains($oldComment)) { throw 'Canonical Strong composite review comment changed.' }

$balancedSource = $source.Replace($strengthDeclaration,'static const float AGENT2_DIAGNOSTIC_STRENGTH = 1.00;')
$balancedSource = $balancedSource.Replace($oldComment,"    // Offline Balanced review uses R3D's donor-neutral 1.0 intensity.`n    // This source has no INI or runtime binding.")

[IO.Directory]::CreateDirectory($output) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$variants = @(
    [ordered]@{ name='Balanced'; strength=1.0; source=$balancedSource; rationale='R3D documented default SSGI intensity' },
    [ordered]@{ name='Strong'; strength=1.25; source=$source; rationale='existing Agent 2 visible diagnostic; 25 percent above donor-neutral' }
)
$compiled = [Collections.Generic.List[object]]::new()

foreach ($variant in $variants) {
    $baseName = "Agent2R3DSSGIComposite$($variant.name)_ps"
    $sourceOut = Join-Path $output ($baseName + '.hlsl')
    $objectOut = Join-Path $output ($baseName + '.obj')
    $assemblyOut = Join-Path $output ($baseName + '.asm')
    $temporaryObject = Join-Path $output ('.' + $baseName + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($sourceOut,[string]$variant.source,$utf8)
    try {
        $messages = & $FxcPath /nologo /T ps_5_0 /E main /Ges /WX /O3 /Fo $temporaryObject /Fc $assemblyOut $sourceOut 2>&1
        if ($LASTEXITCODE -ne 0) { throw "FXC failed for $($variant.name): $($messages -join ' ')" }
        $bytes = [IO.File]::ReadAllBytes($temporaryObject)
        if ($bytes.Length -lt 4 -or [Text.Encoding]::ASCII.GetString($bytes,0,4) -ne 'DXBC') {
            throw "$($variant.name) output is not a DXBC container."
        }
        [IO.File]::Copy($temporaryObject,$objectOut,$true)
    }
    finally {
        if (Test-Path -LiteralPath $temporaryObject -PathType Leaf) { Remove-Item -LiteralPath $temporaryObject -Force }
    }

    $assembly = Get-Content -Raw -LiteralPath $assemblyOut
    foreach ($binding in @('Agent2FilteredSSGI','Agent2CompositeNormal','Agent2CompositeDepth','Agent2CompositeMaterial','Agent2CompositeAlbedo','RemakeView')) {
        if ($assembly -notmatch ('(?m)^//\s+' + [regex]::Escape($binding) + '\s+')) {
            throw "$($variant.name) compiled composite is missing reflected binding $binding."
        }
    }
    if ($assembly -notmatch '(?m)^//\s+SV_Target\s+0\s+xyzw') { throw "$($variant.name) is missing SV_Target0." }

    $compiled.Add([ordered]@{
        name = [string]$variant.name
        strength = [double]$variant.strength
        rationale = [string]$variant.rationale
        source = [IO.Path]::GetFileName($sourceOut)
        sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceOut).Hash
        object = [IO.Path]::GetFileName($objectOut)
        objectSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectOut).Hash
        assembly = [IO.Path]::GetFileName($assemblyOut)
        assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assemblyOut).Hash
    })
}

if ($compiled[0].objectSha256 -eq $compiled[1].objectSha256) { throw 'Balanced and Strong compiled to the same object.' }

$payload = @(Get-ChildItem -LiteralPath $output -File | Where-Object Name -ne 'manifest.json' | Sort-Object Name | ForEach-Object {
    [ordered]@{ name=$_.Name; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash; bytes=[long]$_.Length }
})
$compilerInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($FxcPath)
$manifest = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    classification = 'offline-indirect-lighting-strength-review-no-bindings'
    algorithm = 'altered R3D horizon SSGI, Remake e2aa additive diffuse composite'
    strengths = [ordered]@{
        Balanced = 1.0
        Strong = 1.25
        balancedToStrongRatio = 0.8
        selection = 'Balanced is donor-neutral; Strong preserves the existing diagnostic unchanged'
    }
    separation = [ordered]@{
        ambientOcclusionChanged = $false
        indirectDiffuseOnly = $true
        scalarStrengthPreservesBounceHue = $true
        receiverDiffuse = 'e2aa t2.rgb * (1 - e2aa t1.x metallic) / pi'
    }
    evidence = [ordered]@{
        r3d = [ordered]@{ commit=[string]$provenance.commit; license=[string]$provenance.license; environmentSha256=$expectedHashes[$r3dEnvironmentPath]; defaultIntensity=1.0 }
        rebirth = [ordered]@{ sourceSha256=$expectedHashes[$rebirthReferencePath]; generalBoost='MATH_PI'; characterBoost=1.0; directlyTransplanted=$false }
        canonicalStrongSourceSha256 = $expectedHashes[$compositePath]
    }
    variants = @($compiled)
    files = $payload
    compiler = [ordered]@{ profile='ps_5_0'; entryPoint='main'; version=$compilerInfo.FileVersion; flags=@('/Ges','/WX','/O3') }
    policy = [ordered]@{
        iniEmitted = $false
        keyBindingsEmitted = $false
        liveTestsPerformed = $false
        runtimeEligible = $false
        installed = $false
        gameFilesTouched = $false
    }
}
$manifestPath = Join-Path $output 'manifest.json'
[IO.File]::WriteAllText($manifestPath,(($manifest | ConvertTo-Json -Depth 12)+[Environment]::NewLine),$utf8)

[pscustomobject]@{
    Result = 'pass'
    Classification = $manifest.classification
    Balanced = 1.0
    Strong = 1.25
    CompiledVariants = $compiled.Count
    PayloadFiles = $payload.Count
    RuntimeEligible = $false
    Output = $manifestPath
}
