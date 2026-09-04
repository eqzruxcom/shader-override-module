[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GeneratedRuntimeDirectory=(Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\generated-runtime\FF7RemakeIntergradeAuthorImageAdjustments-live'),
    [string]$GameRoot='C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes',
    [int]$ProcessId=48440
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$generated=(Resolve-Path -LiteralPath $GeneratedRuntimeDirectory).Path.TrimEnd('\')
if (-not $generated.StartsWith((Join-Path $repo 'artifacts\generated-runtime')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Generated runtime escaped workspace.' }
$live=[IO.Path]::GetFullPath((Join-Path $GameRoot 'End\Binaries\Win64')).TrimEnd('\')
$installPath=Join-Path $repo 'artifacts\installed-author-image-adjustments-overlay.json'
if (Test-Path -LiteralPath $installPath) { throw 'Install manifest exists; preserve rollback evidence.' }
$manifestPath=Join-Path $generated 'runtime-manifest.json'
$m=Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($m.adapterId -ne 'FF7RemakeIntergradeAuthorImageAdjustments' -or $m.status -ne 'author-port-compiled-live-pending' -or -not $m.diagnosticOnly -or $m.trueNativeShaderToggle) { throw 'Not the audited author port.' }
$candidate='01CB3652072A4F4A942CAB9D3BD5C5DC0DB3012F67CE4D8614E833407FDC364B'
if ($m.candidateSha256 -ne $candidate -or (Get-FileHash -LiteralPath (Join-Path $generated 'validation\author-final.shdr')).Hash -ne $candidate) { throw 'Candidate binary changed.' }
$expected=@('Mods/UE4EffectsGenerated.ini','ShaderFixes/41f1bf8b79d01319-ps.txt')
if (($m.files.relativePath -join ',') -cne ($expected -join ',')) { throw 'Unexpected payload.' }
foreach ($f in $m.files) { if ((Get-FileHash -LiteralPath (Join-Path $generated $f.relativePath)).Hash -ne $f.sha256) { throw 'Generated payload changed.' } }
$oldPath=Join-Path $repo 'artifacts\installed-final-composite-isolation-overlay.json'
$old=Get-Content -Raw -LiteralPath $oldPath | ConvertFrom-Json
if ([IO.Path]::GetFullPath($old.targetRoot).TrimEnd('\') -ne $live) { throw 'Wrong predecessor target.' }
foreach ($f in $old.files) { if ((Get-FileHash -LiteralPath (Join-Path $live $f.relativePath)).Hash -ne $f.installedSha256) { throw 'Live predecessor was modified; preserve it.' } }
$inis=@(Get-ChildItem -LiteralPath (Join-Path $live 'Mods') -File -Recurse -Filter '*.ini')
if ($inis.Count -ne 1 -or $inis[0].FullName -ne (Join-Path $live 'Mods\UE4EffectsGenerated.ini')) { throw 'Conflicting mod INIs.' }
$fixes=@(Get-ChildItem -LiteralPath (Join-Path $live 'ShaderFixes') -File -Recurse)
if ($fixes.Count -ne 1 -or $fixes[0].FullName -ne (Join-Path $live 'ShaderFixes\41f1bf8b79d01319-ps.txt')) { throw 'Conflicting ShaderFixes files.' }
$priorStatus=& (Join-Path $PSScriptRoot 'Get-IntergradeFinalCompositeReloadStatus.ps1')
if ($priorStatus.classification -ne 'passed-native-asm-and-parser-reload' -or -not $priorStatus.processResponding) { throw 'Predecessor is not live and validated.' }
$p=Get-Process -Id $ProcessId
if ($p.Path -ne (Join-Path $live 'ff7remake_.exe') -or -not $p.Responding) { throw 'Exact game process unavailable.' }
$rootIni=Join-Path $live 'd3dx.ini'
$rootSha=(Get-FileHash -LiteralPath $rootIni).Hash
$rootText=Get-Content -Raw -LiteralPath $rootIni
if ($rootText -notmatch '(?m)^hunting\s*=\s*2\s*$' -or $rootText -notmatch '(?m)^ini_params\s*=\s*120\s*$' -or $rootText -notmatch '(?m)^cache_shaders\s*=\s*0\s*$') { throw 'Root configuration differs from audited setup.' }
$logPath=Join-Path $live 'd3d11_log.txt'
$offset=(Get-Item -LiteralPath $logPath).Length
if (-not $PSCmdlet.ShouldProcess($live,'Install source-author image adjustments before native tone mapping, with backup and default OFF')) { return }
$utf8=[Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $generated 'predecessor-live-status.json'),($priorStatus | ConvertTo-Json -Depth 7)+[Environment]::NewLine,$utf8)
$result=& (Join-Path $PSScriptRoot 'Install-UE4GeneratedRuntimeOverlay.ps1') -GeneratedRuntimeDirectory $generated -GameRoot $GameRoot -InstallManifestPath $installPath
if ((Get-FileHash -LiteralPath $rootIni).Hash -ne $rootSha) { throw 'Root configuration changed during install.' }
$baseline=[ordered]@{
    schemaVersion=1; adapterId=$m.adapterId; diagnostic='author-image-adjustments'; processId=$ProcessId
    processResponding=$true; capturedAtUtc=[DateTime]::UtcNow.ToString('o'); logPath=$logPath; byteOffset=$offset
    liveIniPath=(Join-Path $live 'Mods\UE4EffectsGenerated.ini'); rootIniSha256=$rootSha
    expectedControlKeys=@('UE4FXFinalSceneAB'); expectedEligibleHashes=@('41f1bf8b79d01319')
    forbiddenBlockedHashes=@('af6cd28a0108a18a','ef7fe8d9c4e9ad15','a77b589dce5822d6','e2aa1c8cb39e0a55')
    expectedAsmFilename='41f1bf8b79d01319-ps.txt'; offState=$m.offState
    installedOverlayManifest=$installPath.Substring($repo.Length+1).Replace('\','/')
    installedOverlayManifestSha256=(Get-FileHash -LiteralPath $installPath).Hash
    generatedRuntimeManifestSha256=(Get-FileHash -LiteralPath $manifestPath).Hash
}
[IO.File]::WriteAllText((Join-Path $generated 'live-reload-baseline.json'),($baseline | ConvertTo-Json -Depth 8)+[Environment]::NewLine,$utf8)
$result
[pscustomobject]@{State='author-port-staged-awaiting-F10'; LogOffset=$offset; RootConfigurationUnchanged=$true; Key='Page Down'; Default='original calculations'; On='author brightness -0.45 EV and gamma 1.15 before native tone mapping'}
