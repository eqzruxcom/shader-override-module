[CmdletBinding()]
param(
    [string]$DiagnosticDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\capsule-occlusion-ownership-diagnostic-20260831-v1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $DiagnosticDirectory).Path
$manifest = Get-Content -Raw -LiteralPath (Join-Path $root 'diagnostic-manifest.json') | ConvertFrom-Json
if ([string]$manifest.diagnosticId -ne 'ff7r-capsule-occlusion-ownership-v1' -or
    [string]$manifest.shader -ne 'b9e2305a994308f2-cs' -or
    [string]$manifest.family -ne 'tiled-capsule-occlusion-producer') {
    throw 'Unexpected capsule diagnostic identity.'
}
if ([bool]$manifest.runtimeEligible -or [bool]$manifest.installed -or -not [bool]$manifest.neutralRoundTripIdentical) {
    throw 'Capsule diagnostic safety state is invalid.'
}
if ([string]$manifest.control.masterKey -ne 'Page Down' -or
    [string]$manifest.control.experimentKey -ne 'Page Up' -or
    [string]$manifest.control.experimentDefault -ne 'off') {
    throw 'Capsule diagnostic hotkey contract changed.'
}
if ([string]$manifest.change.modifiedOutput -ne 'u0.xy capsule visibility forced to neutral 1.0') {
    throw 'Capsule diagnostic no longer isolates the visibility channels.'
}

foreach ($file in @($manifest.files)) {
    $path = Join-Path $root ([string]$file.path).Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Capsule diagnostic file is missing: $path"
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$file.sha256) {
        throw "Capsule diagnostic file fingerprint changed: $path"
    }
}

$ini = Get-Content -Raw -LiteralPath (Join-Path $root 'payload\Mods\CapsuleOcclusionOwnership.ini')
if ([regex]::Matches($ini, '(?m)^key = no_modifiers VK_NEXT\r?$').Count -ne 1 -or
    [regex]::Matches($ini, '(?m)^key = no_modifiers VK_PRIOR\r?$').Count -ne 1 -or
    [regex]::Matches($ini, '(?m)^x28 = \$ue4fx_master_injected_v1\r?$').Count -ne 1 -or
    [regex]::Matches($ini, '(?m)^y28 = \$ue4fx_capsule_ownership_v1\r?$').Count -ne 1) {
    throw 'Capsule diagnostic INI does not contain exactly one master and experiment binding.'
}

$originalAssembly = Get-Content -Raw -LiteralPath (Join-Path $root 'validation\original.asm')
$assembly = Get-Content -Raw -LiteralPath (Join-Path $root 'payload\ShaderFixes\b9e2305a994308f2-cs.txt')
$neutralPattern = 'mov r3\.xy, l\(1\.000000,1\.000000,0,0\)'
$originalNeutralCount = [regex]::Matches($originalAssembly, $neutralPattern).Count
$candidateNeutralCount = [regex]::Matches($assembly, $neutralPattern).Count
$injectedSequence = '(?m)^ld_indexable\(texture1d\)\(float,float,float,float\) r14\.xy, l\(28, 0, 0, 0\), t120\.xyzw\r?\n' +
    '^mul r14\.x, r14\.x, r14\.y\r?\n' +
    '^if_nz r14\.x\r?\n' +
    '^  mov r3\.xy, l\(1\.000000,1\.000000,0,0\)\r?\n' +
    '^endif\r?\n' +
    '^store_uav_typed u0\.xyzw, vThreadID\.xyyy, r3\.xyzw$'
if ([regex]::Matches($assembly, 'store_uav_typed u1\.xyzw, r0\.wwww, r0\.xxxx').Count -ne 1 -or
    [regex]::Matches($assembly, 'store_uav_typed u0\.xyzw, vThreadID\.xyyy, r3\.xyzw').Count -ne 1 -or
    $candidateNeutralCount -ne ($originalNeutralCount + 1) -or
    [regex]::Matches($assembly, $injectedSequence).Count -ne 1 -or
    [regex]::Matches($assembly, '\bt120\b').Count -ne 2) {
    throw 'Capsule diagnostic assembly no longer preserves the narrow output edit.'
}

Write-Output 'PASS: capsule ownership diagnostic is assembled, neutral-by-default, output-isolated, fingerprinted, and not installed.'
