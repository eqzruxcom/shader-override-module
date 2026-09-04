[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GeneratedRuntimeDirectory=(Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\generated-runtime\FF7RemakeIntergradeFinalCompositeIsolation'),
    [string]$GameRoot='C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes',
    [int]$ProcessId=48440
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$generated=(Resolve-Path -LiteralPath $GeneratedRuntimeDirectory).Path.TrimEnd('\')
if (-not $generated.StartsWith((Join-Path $repo 'artifacts\generated-runtime')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Generated directory escaped workspace.' }
$live=[IO.Path]::GetFullPath((Join-Path $GameRoot 'End\Binaries\Win64')).TrimEnd('\')
$installPath=Join-Path $repo 'artifacts\installed-final-composite-isolation-overlay.json'
if (Test-Path -LiteralPath $installPath) { throw 'Isolation install manifest already exists; do not overwrite rollback evidence.' }
$manifestPath=Join-Path $generated 'runtime-manifest.json'
$m=Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($m.adapterId -ne 'FF7RemakeIntergradeFinalCompositeIsolation' -or -not $m.diagnosticOnly -or $m.status -ne 'offline-verified-live-boundary-pending') { throw 'Not the audited diagnostic.' }
if ($m.trueNativeShaderToggle -or $m.replacesNativeTonemapper -or $m.originalTokensByteIdentical -ne 134 -or $m.control.default -ne 0) { throw 'Diagnostic contract changed.' }
$expectedCandidate='79422F03492009C266BAD83B6F729D5DF32D160A24E80C6C389A822888D4007C'
if ($m.candidateSha256 -ne $expectedCandidate -or (Get-FileHash -LiteralPath (Join-Path $generated 'validation\scene-toggle.shdr')).Hash -ne $expectedCandidate) { throw 'Candidate fingerprint changed.' }
$expectedFiles=@('Mods/UE4EffectsGenerated.ini','ShaderFixes/41f1bf8b79d01319-ps.txt')
if ((@($m.files.relativePath | Sort-Object) -join ',') -cne (($expectedFiles | Sort-Object) -join ',')) { throw 'Unexpected diagnostic payload.' }
foreach ($f in $m.files) {
    if ((Get-FileHash -LiteralPath (Join-Path $generated $f.relativePath)).Hash -ne $f.sha256) { throw 'Generated file changed.' }
}
$old=Get-Content -Raw -LiteralPath (Join-Path $repo 'artifacts\installed-scene-post-tonemap-isolation-overlay.json') | ConvertFrom-Json
if ([IO.Path]::GetFullPath($old.targetRoot).TrimEnd('\') -ne $live) { throw 'Predecessor runtime path differs.' }
foreach ($f in $old.files) {
    if ((Get-FileHash -LiteralPath (Join-Path $live $f.relativePath)).Hash -ne $f.installedSha256) { throw 'Live predecessor was changed; preserve it.' }
}
$inis=@(Get-ChildItem -LiteralPath (Join-Path $live 'Mods') -File -Recurse -Filter '*.ini')
if ($inis.Count -ne 1 -or $inis[0].FullName -ne (Join-Path $live 'Mods\UE4EffectsGenerated.ini')) { throw 'Other active mod INIs exist.' }
if (@(Get-ChildItem -LiteralPath (Join-Path $live 'ShaderFixes') -File -Recurse).Count -ne 0) { throw 'ShaderFixes is not empty; refuse to layer the diagnostic.' }
$rootIni=Join-Path $live 'd3dx.ini'
$rootText=Get-Content -Raw -LiteralPath $rootIni
if ($rootText -notmatch '(?m)^hunting\s*=\s*2\s*$' -or $rootText -notmatch '(?m)^ini_params\s*=\s*120\s*$' -or $rootText -notmatch '(?m)^cache_shaders\s*=\s*0\s*$') { throw 'Audited root configuration changed.' }
$rootSha=(Get-FileHash -LiteralPath $rootIni).Hash
$p=Get-Process -Id $ProcessId
if ($p.Path -ne (Join-Path $live 'ff7remake_.exe') -or -not $p.Responding) { throw 'Exact game process is unavailable or not responding.' }
$logPath=Join-Path $live 'd3d11_log.txt'
$offset=(Get-Item -LiteralPath $logPath).Length
if (-not $PSCmdlet.ShouldProcess($live,'Stage the scene-only ASM diagnostic with backup; default OFF and no root configuration changes')) { return }
$result=& (Join-Path $PSScriptRoot 'Install-UE4GeneratedRuntimeOverlay.ps1') -GeneratedRuntimeDirectory $generated -GameRoot $GameRoot -InstallManifestPath $installPath
if ((Get-FileHash -LiteralPath $rootIni).Hash -ne $rootSha) { throw 'Root configuration changed during staging.' }
$baseline=[ordered]@{
    schemaVersion=1; adapterId=$m.adapterId; diagnostic='final-composite-assembly-isolation'
    capturedAtUtc=[DateTime]::UtcNow.ToString('o'); processId=$ProcessId; processResponding=$true
    logPath=$logPath; byteOffset=$offset; rootIniSha256=$rootSha
    liveIniPath=(Join-Path $live 'Mods\UE4EffectsGenerated.ini')
    expectedControlKeys=@('UE4FXFinalSceneAB'); expectedEligibleHashes=@('41f1bf8b79d01319')
    forbiddenBlockedHashes=@('af6cd28a0108a18a','ef7fe8d9c4e9ad15','a77b589dce5822d6','e2aa1c8cb39e0a55')
    expectedAsmFilename='41f1bf8b79d01319-ps.txt'; offState=$m.offState
    installedOverlayManifest=$installPath.Substring($repo.Length+1).Replace('\','/')
    installedOverlayManifestSha256=(Get-FileHash -LiteralPath $installPath).Hash
    generatedRuntimeManifestSha256=(Get-FileHash -LiteralPath $manifestPath).Hash
}
[IO.File]::WriteAllText((Join-Path $generated 'live-reload-baseline.json'),($baseline | ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
$result
[pscustomobject]@{ State='staged-awaiting-F10'; ProcessId=$ProcessId; LogOffset=$offset; RootConfigurationUnchanged=$true; Key='Page Down'; Default='original calculations within replacement' }
