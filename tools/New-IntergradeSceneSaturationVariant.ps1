[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateRange(0.0, 1.0)]
    [double]$Saturation,
    [string]$SourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\captured-shaders\af6cd28a0108a18a-ps\af6cd28a0108a18a-ps_decompiled.txt'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime\Intergrade\Mods'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')

function Resolve-WorkspacePath([string]$Path, [switch]$AllowMissing) {
    $full = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
    }
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must remain inside the project workspace: $full"
    }
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full)) {
        throw "Path does not exist: $full"
    }
    $full
}

$sourceFull = Resolve-WorkspacePath $SourcePath
$outputFull = Resolve-WorkspacePath $OutputDirectory -AllowMissing
New-Item -ItemType Directory -Path $outputFull -Force | Out-Null

$percent = [int][Math]::Round($Saturation * 100, 0, [MidpointRounding]::AwayFromZero)
if ([Math]::Abs($Saturation - ($percent / 100.0)) -gt 0.0000001) {
    throw 'Saturation must resolve to a whole percentage point.'
}
$tag = $percent.ToString('000', [Globalization.CultureInfo]::InvariantCulture)
$literal = $Saturation.ToString('0.##########', [Globalization.CultureInfo]::InvariantCulture)
$baseName = "RebirthPostSceneSaturation$($tag)_ps"
$hlslPath = Join-Path $outputFull "$baseName.hlsl"
$objectPath = Join-Path $outputFull "$baseName.cso"
$assemblyPath = Join-Path $outputFull "$baseName.asm"
$manifestPath = Join-Path $outputFull "$baseName.json"

$source = [IO.File]::ReadAllText($sourceFull)
$pattern = '(?m)^  o0\.xyz = r5\.xyz;\r?\n  o0\.w = 0;$'
$matches = [regex]::Matches($source, $pattern)
if ($matches.Count -ne 1) {
    throw "Expected exactly one scene-color output assignment, found $($matches.Count)."
}
$replacement = @"
  // Generated scene-only saturation control. The HUD is composed after this pass.
  float sceneLuma = dot(r5.xyz, float3(0.2126, 0.7152, 0.0722));
  o0.xyz = lerp(sceneLuma.xxx, r5.xyz, $literal);
  o0.w = 0;
"@ -replace "`r`n", "`n"
$generated = [regex]::Replace($source, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement }, 1)
[IO.File]::WriteAllText($hlslPath, $generated, [Text.UTF8Encoding]::new($false))

if (-not (Test-Path -LiteralPath $FxcPath -PathType Leaf)) {
    throw "FXC was not found: $FxcPath"
}
$compilerOutput = & $FxcPath /nologo /T ps_5_0 /E main /Ges /WX /O3 /Fo $objectPath /Fc $assemblyPath $hlslPath 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "FXC failed for $baseName`n$($compilerOutput -join [Environment]::NewLine)"
}

$assembly = [IO.File]::ReadAllText($assemblyPath)
foreach ($binding in @('t0','t1','t2','cb0','cb1')) {
    if ($assembly -notmatch "(?m)^//\s+$binding\s+") {
        throw "Compiled variant is missing expected binding $binding."
    }
}
if ($assembly -notmatch '(?m)^//\s+SV_Target\s+0\s+xyzw') {
    throw 'Compiled variant is missing the expected SV_Target0 output.'
}

$manifest = [ordered]@{
    schemaVersion = 1
    adapter = 'FF7RemakeIntergrade'
    shaderHash = 'af6cd28a0108a18a'
    stage = 'ps'
    effect = 'scene-saturation'
    saturation = $Saturation
    source = $hlslPath.Substring($repoRoot.Length + 1).Replace('\','/')
    sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hlslPath).Hash
    object = $objectPath.Substring($repoRoot.Length + 1).Replace('\','/')
    objectSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectPath).Hash
    assembly = $assemblyPath.Substring($repoRoot.Length + 1).Replace('\','/')
    assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assemblyPath).Hash
    compiler = [ordered]@{
        profile = 'ps_5_0'
        entry = 'main'
        flags = @('/Ges','/WX','/O3')
    }
    contract = [ordered]@{
        inputs = @('t0','t1','t2','cb0','cb1')
        output = 'SV_Target0'
        preserveAlphaBehavior = 'o0.w = 0'
        uiComposedAfterPass = $true
    }
}
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Saturation = $Saturation
    Source = $hlslPath
    Object = $objectPath
    Manifest = $manifestPath
    SourceSha256 = $manifest.sourceSha256
    ObjectSha256 = $manifest.objectSha256
}
