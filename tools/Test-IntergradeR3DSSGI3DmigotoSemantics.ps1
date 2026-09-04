[CmdletBinding()]
param(
    [string]$PackDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-f2-owner-integration-pack'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\agent2-r3d-ssgi-3dmigoto-semantics.json'),
    [string]$IniName = 'RebirthEffectsDX11.ini',
    [string]$OverrideSectionName = 'ShaderOverrideRebirthABShared'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$iniPath = Join-Path ([IO.Path]::GetFullPath($PackDirectory)) ('Mods\' + $IniName)
$commandListPath = Join-Path $root 'reference\external\3dmigoto-source-official\DirectX11\CommandList.cpp'
$commandListHeaderPath = Join-Path $root 'reference\external\3dmigoto-source-official\DirectX11\CommandList.h'
$iniHandlerPath = Join-Path $root 'reference\external\3dmigoto-source-official\DirectX11\IniHandler.cpp'
$officialExamplePath = Join-Path $root 'reference\external\3dmigoto-source-official\Dependencies\ShaderFixes\3dvision2sbs.ini'

foreach ($required in @($iniPath, $commandListPath, $commandListHeaderPath, $iniHandlerPath, $officialExamplePath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required semantics input is missing: $required" }
}

$ini = Get-Content -Raw -LiteralPath $iniPath
$commandList = Get-Content -Raw -LiteralPath $commandListPath
$header = Get-Content -Raw -LiteralPath $commandListHeaderPath
$iniHandler = Get-Content -Raw -LiteralPath $iniHandlerPath
$officialExample = Get-Content -Raw -LiteralPath $officialExamplePath

function Assert-Pattern([string]$Text, [string]$Pattern, [string]$Label) {
    if ($Text -notmatch $Pattern) { throw "3Dmigoto semantics assertion failed: $Label" }
}

function Get-Section([string]$Name) {
    $match = [regex]::Match($ini, "(?ms)^\[$([regex]::Escape($Name))\]\r?\n(?<body>.*?)(?=^\[|\z)")
    if (-not $match.Success) { throw "Generated pack section is missing: $Name" }
    return $match.Groups['body'].Value
}

# Injector implementation assertions.
Assert-Pattern $header 'COPY_DESC\s*=\s*0x00000080' 'copy_desc is a supported resource-copy option'
Assert-Pattern $commandList 'if \(options & ResourceCopyOptions::COPY_DESC\)' 'copy_desc reaches compatible-resource creation'
Assert-Pattern $commandList 'dst->custom_resource->OverrideTexDesc\(&new_desc\)' 'custom resource size overrides apply during copy_desc'
Assert-Pattern $commandList 'custom_resource->bind_flags \| operation->dst\.BindFlags' 'custom resources accumulate downstream RTV/SRV bind flags'
Assert-Pattern $commandList 'save_om_state\(state->mOrigContext1, &om_state\)' 'CustomShader saves RTV/UAV/DSV state'
Assert-Pattern $commandList 'restore_om_state\(mOrigContext1, &om_state\)' 'CustomShader restores RTV/UAV/DSV state'
Assert-Pattern $commandList 'RSGetViewports\(&num_viewports, saved_viewports\)' 'CustomShader saves viewport state'
Assert-Pattern $commandList 'RSSetViewports\(num_viewports, saved_viewports\)' 'CustomShader restores viewport state'
Assert-Pattern $commandList 'PSGetSamplers\(0, num_sampler, saved_sampler_states\)' 'CustomShader saves pixel samplers'
Assert-Pattern $commandList 'PSSetSamplers\(0, num_sampler, saved_sampler_states\)' 'CustomShader restores pixel samplers'
Assert-Pattern $iniHandler 'D3D11_FILTER_COMPARISON_MIN_MAG_MIP_LINEAR' 'linear_filter selects linear min/mag/mip filtering'
Assert-Pattern $iniHandler 'AddressU = D3D11_TEXTURE_ADDRESS_CLAMP' 'custom sampler clamps U'
Assert-Pattern $iniHandler 'AddressV = D3D11_TEXTURE_ADDRESS_CLAMP' 'custom sampler clamps V'
Assert-Pattern $officialExample 'height_multiply = 0\.5' 'official example supports half-height resources'
Assert-Pattern $officialExample 'width_multiply = 0\.5' 'official example supports half-width resources'
Assert-Pattern $officialExample 'copy_desc bb' 'official example creates resized compatible resources'
Assert-Pattern $officialExample 'o0 = set_viewport Resource' 'official example binds custom RTV and viewport together'
Assert-Pattern $officialExample 'Resource\w+BackupTexture = reference ps-t\d+' 'official example saves a texture slot by reference'
Assert-Pattern $officialExample 'post ps-t\d+ = reference Resource\w+BackupTexture' 'official example restores a texture slot by reference'

# Generated resource and pass graph assertions.
foreach ($resourceName in @('ResourceAgent2SSGIPing', 'ResourceAgent2SSGIPong')) {
    $body = Get-Section $resourceName
    Assert-Pattern $body '(?m)^width_multiply = 0\.5\r?$' "$resourceName is half width"
    Assert-Pattern $body '(?m)^height_multiply = 0\.5\r?$' "$resourceName is half height"
}

$expectedPasses = [ordered]@{
    'CustomShaderAgent2R3DSSGITrace' = @('ResourceAgent2SSGIPing = copy_desc ResourceAgent2SSGITarget', 'o0 = set_viewport ResourceAgent2SSGIPing', 'ps-t110 = ResourceAgent2SSGIScene', 'ps-t111 = ResourceAgent2SSGINormal', 'ps-t112 = ResourceAgent2SSGIDepth')
    'CustomShaderAgent2R3DSSGIDenoise16' = @('o0 = set_viewport ResourceAgent2SSGIPong', 'ps-t110 = ResourceAgent2SSGIPing')
    'CustomShaderAgent2R3DSSGIDenoise8' = @('o0 = set_viewport ResourceAgent2SSGIPing', 'ps-t110 = ResourceAgent2SSGIPong')
    'CustomShaderAgent2R3DSSGIDenoise4' = @('o0 = set_viewport ResourceAgent2SSGIPong', 'ps-t110 = ResourceAgent2SSGIPing')
    'CustomShaderAgent2R3DSSGIDenoise2' = @('o0 = set_viewport ResourceAgent2SSGIPing', 'ps-t110 = ResourceAgent2SSGIPong')
    'CustomShaderAgent2R3DSSGIComposite' = @('o0 = set_viewport ResourceAgent2SSGITarget', 'ps-t110 = ResourceAgent2SSGIPing', 'blend = ADD ONE ONE')
}

foreach ($entry in $expectedPasses.GetEnumerator()) {
    $body = Get-Section $entry.Key
    Assert-Pattern $body '(?m)^sampler = linear_filter\r?$' "$($entry.Key) uses explicit linear clamp"
    Assert-Pattern $body '(?m)^run = BuiltInCommandListUnbindAllRenderTargets\r?$' "$($entry.Key) unbinds OM targets before rebinding"
    Assert-Pattern $body '(?m)^draw = from_caller\r?$' "$($entry.Key) reuses the captured fullscreen draw"
    if ($body -match '(?im)^handling\s*=\s*skip\s*$') { throw "$($entry.Key) suppresses the owner draw." }
    foreach ($statement in $entry.Value) { Assert-Pattern $body ('(?m)^' + [regex]::Escape($statement) + '\r?$') "$($entry.Key) contains $statement" }
    Assert-Pattern $body '(?m)^post ps-t110 = null\r?$' "$($entry.Key) releases its source SRV"
}

foreach ($name in @('Trace', 'Denoise16', 'Denoise8', 'Denoise4', 'Denoise2')) {
    $body = Get-Section "CustomShaderAgent2R3DSSGI$name"
    Assert-Pattern $body '(?m)^post ps-t111 = null\r?$' "$name releases normal SRV"
    Assert-Pattern $body '(?m)^post ps-t112 = null\r?$' "$name releases depth SRV"
}

$override = Get-Section $OverrideSectionName
Assert-Pattern $override '(?s)if \$agent2_ssgi_test == 1.*?ResourceAgent2SSGIOriginalT110 = reference ps-t110.*?ResourceAgent2SSGITarget = reference o0.*?ResourceAgent2SSGINormal = reference ps-t0.*?ResourceAgent2SSGIDepth = reference ps-t5.*?ResourceAgent2SSGIScene = copy o0.*?run = CustomShaderAgent2R3DSSGITrace.*?run = CustomShaderAgent2R3DSSGIDenoise16.*?run = CustomShaderAgent2R3DSSGIDenoise8.*?run = CustomShaderAgent2R3DSSGIDenoise4.*?run = CustomShaderAgent2R3DSSGIDenoise2.*?run = CustomShaderAgent2R3DSSGIComposite.*?ps-t114 = reference ResourceAgent2SSGIOriginalT114.*?endif' 'F2 override preserves high SRVs, captures native inputs, and runs the six passes in order'
if ($override -match '(?im)^\s*Resource\w+\s*=\s*(?:copy|reference)\s+rt\d+\s*$') {
    throw 'Invalid 3DMigoto render-target alias found: command-list render targets must use oN, not rtN.'
}
foreach ($slot in @(110, 111, 112, 113, 114)) {
    Assert-Pattern $override ("(?m)^\s*ResourceAgent2SSGIOriginalT$slot = reference ps-t$slot\r?$") "F2 saves ps-t$slot"
    Assert-Pattern $override ("(?m)^\s*ps-t$slot = reference ResourceAgent2SSGIOriginalT$slot\r?$") "F2 restores ps-t$slot"
}
$rollingAbIndex = $override.IndexOf('if $rebirth_ab_current == 0')
if ($rollingAbIndex -ge 0 -and $override.IndexOf('if $agent2_ssgi_test == 1') -gt $rollingAbIndex) {
    throw 'SSGI must execute before the existing e2aa owner replacement branch.'
}

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    classification = 'pinned-3dmigoto-static-semantics-verified-live-execution-pending'
    packIni = [IO.Path]::GetRelativePath($root, $iniPath)
    packIniSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $iniPath).Hash
    overrideSection = $OverrideSectionName
    verified = [ordered]@{
        copyDescAndHalfResolution = $true
        automaticRtvSrvBindFlags = $true
        omAndViewportRestoration = $true
        explicitLinearClampAndSamplerRestoration = $true
        sixPassPingPongGraph = $true
        additiveCompositeBeforeOwnerDraw = $true
        highSrvPerPassCleanup = $true
        highSrvBackupAndRestore = $true
    }
    sourceEvidence = @($commandListPath, $commandListHeaderPath, $iniHandlerPath, $officialExamplePath | ForEach-Object { [IO.Path]::GetRelativePath($root, $_) })
    remainingGates = @('live 3Dmigoto parse/log without warnings', 'live resource creation and view compatibility', 'visual still/motion capture', 'GPU timing')
    runtimeEligible = $false
    installed = $false
}

$outputFull = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull)) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($outputFull, ($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine, $utf8)

[pscustomobject]@{
    result = 'pass'
    classification = $report.classification
    output = $outputFull
    runtimeEligible = $false
}
