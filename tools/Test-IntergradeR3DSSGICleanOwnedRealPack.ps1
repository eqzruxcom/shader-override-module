[CmdletBinding()]
param([string]$PackRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\agent2-r3d-ssgi-clean-owned-real-pack'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $PackRoot 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Manifest is missing: $manifestPath" }
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.result -ne 'pass' -or $manifest.runtimeEligible -ne $false -or
    $manifest.installed -ne $false -or $manifest.liveTestsPerformed -ne $false -or $manifest.nativeE2aaReplacementIncluded -ne $false -or
    $manifest.architecture -notmatch '^single owned fullscreen composite') { throw 'Clean owned real manifest contract failed.' }
$mods = Join-Path $PackRoot 'Mods'
if (@($manifest.files).Count -ne 8 -or @($manifest.compile).Count -ne 7) { throw 'Expected eight files and seven compiled shaders.' }
foreach ($file in @($manifest.files)) {
    $path = Join-Path $mods ([string]$file.name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$file.sha256) { throw "Payload drifted: $($file.name)" }
}
$ini = [IO.File]::ReadAllText((Join-Path $mods 'Agent2R3DSSGITest.ini'))
$composite = [IO.File]::ReadAllText((Join-Path $mods 'Agent2R3DSSGICompositeE2AA_ps.hlsl'))
if ([regex]::Matches($ini,'(?im)^\s*key\s*=.*(?<![A-Z0-9_])F2(?![A-Z0-9_]).*$').Count -ne 1 -or
    $ini -match '(?im)^\s*key\s*=.*(?:F10|VK_PRIOR|VK_NEXT).*$') { throw 'Key contract failed.' }
if ([regex]::Matches($ini,'(?im)^\s*draw\s*=\s*3\s*,\s*0\s*$').Count -ne 1 -or
    [regex]::Matches($ini,'(?im)^\s*draw\s*=\s*from_caller\s*$').Count -ne 5) { throw 'Draw ownership contract failed.' }
if ($composite -notmatch '(?m)^\s*return float4\(indirectRadiance, 0\.0\);\s*$') { throw 'Real indirect output is missing.' }
if (Test-Path -LiteralPath (Join-Path $PackRoot 'ShaderFixes\e2aa1c8cb39e0a55-ps.txt')) { throw 'Native e2aa replacement leaked into the clean pack.' }
[pscustomobject]@{Result='pass';Files=@($manifest.files).Count;Compiled=@($manifest.compile).Count;Architecture=$manifest.architecture;F2='single-path owned SSGI';NativeE2aaReplacement=$false;RuntimeEligible=$manifest.runtimeEligible}
