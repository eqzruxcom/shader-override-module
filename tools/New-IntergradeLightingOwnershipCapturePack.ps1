[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\intergrade-lighting-ownership-capture-pack-20260904-v1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if (-not $output.StartsWith($artifacts + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputRoot must remain below workspace artifacts: $output"
}
if (Test-Path -LiteralPath $output) {
    throw "OutputRoot already exists; refusing to merge evidence: $output"
}

$targets = @(
    [ordered]@{
        hash = 'aadc1c2374853914'
        stage = 'ps'
        role = 'directional cascade shadow-factor producer; trace its output into the later surface-light consumer'
        assembly = Join-Path $root 'artifacts\validation-captures\ff7r-contact-area-baseline-20260831\assembly\aadc1c2374853914-ps.asm'
        expectedAssemblySha256 = '18A20B5D74AC5714690F3CFAE954A21003DDE4598D0AB9EC9DDB67FE86140141'
    },
    [ordered]@{
        hash = 'adb544f9a11d6c7e'
        stage = 'cs'
        role = 'unshadowed tiled local-light diffuse candidate; establish runtime ownership before any transform'
        assembly = Join-Path $root 'artifacts\analysis\intergrade-live-compute-census-20260903-v3\adb544f9a11d6c7e-cs.asm'
        expectedAssemblySha256 = '1C86224EC2EE4DA291F76F4A061290938C0FE063B5A42343028A6DA1E4DE289B'
    }
)

foreach ($target in $targets) {
    if (-not (Test-Path -LiteralPath $target.assembly -PathType Leaf)) {
        throw "Pinned shader evidence is missing: $($target.assembly)"
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $target.assembly).Hash
    if ($actual -ne $target.expectedAssemblySha256) {
        throw "Pinned shader evidence drifted for $($target.hash): $actual"
    }
}

$mods = Join-Path $output 'Mods'
[void][IO.Directory]::CreateDirectory($mods)
$iniPath = Join-Path $mods 'IntergradeLightingOwnershipCapture.ini'
$ini = @'
; Read-only frame-analysis narrowing for unresolved FF7 Remake lighting ownership.
; This file changes no shader, render state, resource binding, draw, dispatch, or key.
; During an ordinary F8 frame analysis, only these two shader executions request
; their render targets/UAVs, shader textures, constant buffers, and descriptions.

[ShaderOverrideUE4FXCaptureDirectionalShadowFactorsAADC]
hash = aadc1c2374853914
allow_duplicate_hash = true
analyse_options = dump_rt dump_tex dump_cb mono desc

[ShaderOverrideUE4FXCaptureUnshadowedLocalLightADB]
hash = adb544f9a11d6c7e
allow_duplicate_hash = true
analyse_options = dump_rt dump_tex dump_cb mono desc
'@
[IO.File]::WriteAllText($iniPath, $ini.TrimStart() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

$manifestTargets = @($targets | ForEach-Object {
    [ordered]@{
        hash = $_.hash
        stage = $_.stage
        role = $_.role
        assembly = [IO.Path]::GetRelativePath($root, $_.assembly).Replace('\','/')
        assemblySha256 = $_.expectedAssemblySha256
    }
})
$manifest = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    packId = 'ff7-remake-lighting-ownership-capture-v1'
    purpose = 'Narrow ordinary 3Dmigoto frame analysis to two unresolved lighting ownership boundaries without modifying rendering.'
    targets = $manifestTargets
    capture = [ordered]@{
        trigger = 'existing F8 frame-analysis key'
        options = @('dump_rt','dump_tex','dump_cb','mono','desc')
        directionalScene = 'outdoor area with dominant sun and visible cascade receiver shadows'
        localLightScene = 'area where adb544f9a11d6c7e executes; do not infer absence from another scene'
        analyzer = 'tools/Analyze-IntergradeShaderResourceFlow.ps1'
    }
    invariants = [ordered]@{
        shaderReplacement = $false
        renderStateMutation = $false
        resourceBindingMutation = $false
        drawOrDispatchMutation = $false
        keyBinding = $false
        f10 = 'unchanged shader reload'
        f2 = 'unchanged indirect-light toggle'
        pageUp = 'unchanged foreground test cycle'
        pageDown = 'unchanged graduated master toggle'
    }
    files = @([ordered]@{
        path = 'Mods/IntergradeLightingOwnershipCapture.ini'
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $iniPath).Hash
    })
    runtimeEligible = $false
    installed = $false
    nextGate = 'Install only while the user is available, press existing F10 once, take one F8 capture in the appropriate scene, then analyze resource consumers before any shader modification.'
}
[IO.File]::WriteAllText(
    (Join-Path $output 'manifest.json'),
    ($manifest | ConvertTo-Json -Depth 10) + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Result = 'pass'
    Output = $output
    TargetCount = $targets.Count
    RenderingMutated = $false
    Installed = $false
}

