[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$backupRoot = Join-Path $repoRoot "backups\acl-fallback\$timestamp"
[IO.Directory]::CreateDirectory($backupRoot) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)

function Update-TextFile {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][string]$Replacement
    )
    $path = Join-Path $repoRoot ($RelativePath -replace '/', '\')
    $text = [IO.File]::ReadAllText($path)
    $normalizedText = $text -replace "`r`n", "`n"
    $normalizedExpected = $Expected -replace "`r`n", "`n"
    $normalizedReplacement = $Replacement -replace "`r`n", "`n"
    $count = ([regex]::Matches($normalizedText, [regex]::Escape($normalizedExpected))).Count
    if ($count -ne 1) { throw "Expected exactly one match in $RelativePath; found $count." }
    $backupName = ($RelativePath -replace '[/\\]', '__')
    [IO.File]::WriteAllText((Join-Path $backupRoot $backupName), $text, $utf8)
    $updated = $normalizedText.Replace($normalizedExpected, $normalizedReplacement)
    if ($text.Contains("`r`n")) { $updated = $updated -replace "`n", "`r`n" }
    [IO.File]::WriteAllText($path, $updated, $utf8)
}

Update-TextFile 'artifacts/ssr-composite-strength-diagnostics/RebirthSSRCompositeDiagnostic1600_ps.json' @'
  "liveStatus": "pending",
  "runtimeAdapterEligible": false
'@ @'
  "liveStatus": "live-verified-amplified-response",
  "liveEvidence": "artifacts/probe-screenshots/e2aa1c8cb39e0a55-strength-1600-live-validation.json",
  "liveResult": "Angle-dependent white edge glow and sparse reflective/specular model response appeared at 16x and disappeared on the F3 0% side.",
  "runtimeAdapterEligible": false
'@

Update-TextFile 'artifacts/replacement-shaders/e2aa1c8cb39e0a55-ssr-composite-strength-control-pack.json' @'
  "status": "strict-compile-full-replacement-neutral-live-parity-passed-nonneutral-live-validation-pending",
'@ @'
  "status": "live-diagnostic-amplified-response-verified-normal-range-current-scene-inconclusive",
'@

Update-TextFile 'artifacts/replacement-shaders/e2aa1c8cb39e0a55-ssr-composite-strength-control-pack.json' @'
      "verification": "strict-compile"
    },
    {
      "strength": 0.25,
'@ @'
      "verification": "live-no-observable-difference-current-scene",
      "liveEvidence": "artifacts/probe-screenshots/e2aa1c8cb39e0a55-strength-000-live-validation.json"
    },
    {
      "strength": 0.25,
'@

Update-TextFile 'artifacts/replacement-shaders/e2aa1c8cb39e0a55-ssr-composite-strength-control-pack.json' @'
  "liveGate": "Passed: the radiance-presence probe and native-resolution 100% replacement parity. Pending: validate 0% and 50% downstream SSR-radiance strength.",
'@ @'
  "liveGate": "Blocked for runtime promotion in this scene: 0%-to-100% produced no observable difference, while diagnostic-only 0%-to-1600% proved angle-dependent screen-edge and sparse reflective/specular model response. Find a view with visible normal-range SSR before validating 50%.",
'@

Update-TextFile 'artifacts/replacement-shaders/e2aa1c8cb39e0a55-ssr-composite-strength-control-pack.json' @'
    "neutral100Percent": "artifacts/probe-screenshots/e2aa1c8cb39e0a55-strength-100-neutral-live-validation.json"
'@ @'
    "neutral100Percent": "artifacts/probe-screenshots/e2aa1c8cb39e0a55-strength-100-neutral-live-validation.json",
    "zeroEndpoint": "artifacts/probe-screenshots/e2aa1c8cb39e0a55-strength-000-live-validation.json",
    "amplifiedDiagnostic1600Percent": "artifacts/probe-screenshots/e2aa1c8cb39e0a55-strength-1600-live-validation.json"
'@

Update-TextFile 'tools/Test-IntergradeSSRCompositeStrengthControlPack.ps1' @'
if ($pack.status -notmatch 'neutral-live-parity-passed' -or $pack.status -notmatch 'nonneutral-live-validation-pending') { throw 'Control pack does not record passed neutral parity and pending non-neutral validation.' }
if ($pack.liveGate -notmatch '^Passed:' -or $pack.liveGate -notmatch 'Pending: validate 0% and 50%') { throw 'Control pack live gate must record passed neutral parity and pending strength validation.' }
foreach ($evidence in @($pack.liveValidation.radiancePresence, $pack.liveValidation.neutral100Percent)) {
'@ @'
if ($pack.status -ne 'live-diagnostic-amplified-response-verified-normal-range-current-scene-inconclusive') { throw 'Control pack does not record the amplified live response and inconclusive normal-range result.' }
if ($pack.liveGate -notmatch '^Blocked for runtime promotion in this scene:' -or $pack.liveGate -notmatch '0%-to-1600%' -or $pack.liveGate -notmatch 'before validating 50%') { throw 'Control pack live gate must preserve the amplified proof and the pending normal-range gate.' }
foreach ($evidence in @($pack.liveValidation.radiancePresence, $pack.liveValidation.neutral100Percent, $pack.liveValidation.zeroEndpoint, $pack.liveValidation.amplifiedDiagnostic1600Percent)) {
'@

Update-TextFile 'tools/Test-IntergradeSSRCompositeStrengthControlPack.ps1' @'
if (@($levels.objectSha256 | Select-Object -Unique).Count -ne 5) { throw 'Expected five unique compiled objects.' }
'@ @'
if ($levels[0].verification -ne 'live-no-observable-difference-current-scene' -or [string]::IsNullOrWhiteSpace([string]$levels[0].liveEvidence)) {
    throw 'The 0% endpoint must record its inconclusive live comparison evidence.'
}
if (@($levels.objectSha256 | Select-Object -Unique).Count -ne 5) { throw 'Expected five unique compiled objects.' }
'@

Update-TextFile 'docs/universal-ue4-effects-roadmap.md' @'
- The fail-closed FF7 binding input configures four passes. The generated adapter
  emits three live-eligible controls (temporal volumetric scattering, UI-safe
  scene saturation, and packed temporal SSAO) and blocks downstream SSR strength
  until its remaining 0% and 50% live validation passes. The strict-compiled 100%
  composite replacement now passes native-resolution parity against F9/original,
  and a dedicated downstream radiance mask confirms a real screen-space reflection
  contribution without conflating it with reflection-environment fallback. Negative tests
'@ @'
- The fail-closed FF7 binding input configures four passes. The generated adapter
  emits three live-eligible controls (temporal volumetric scattering, UI-safe
  scene saturation, and packed temporal SSAO) and blocks downstream SSR strength.
  The strict-compiled 100% composite replacement passes native-resolution parity
  against F9/original, and a dedicated downstream radiance mask confirms a real
  screen-space reflection contribution without conflating it with reflection-environment
  fallback. A 0%-to-100% A/B was visually inconclusive in the tested view, while a
  diagnostic-only 0%-to-1600% A/B produced angle-dependent screen-edge glow and sparse
  reflective/specular scene and character-model response that disappeared on the 0%
  side. Normal-range 0/100 and 50% validation therefore moves to a stronger SSR view.
  Negative tests
'@

Update-TextFile 'README.md' @'
- Pixel shader `e2aa1c8cb39e0a55` is the verified immediately downstream
  reflection-environment/SSR composite. Draw 1096 consumes the exact render
  target handle written by `b2bc6059f9a39c7f` on draw 1095, and its dataflow
  implements `SSR.rgb + environment.rgb * (1 - SSR.alpha)` with additional
  material weighting. Original-versus-hit-mask diagnostics are staged for live
  classification.
  A downstream 0/25/50/75/100% SSR-radiance matrix also compiles strictly,
  but remains packaging-ineligible until native 100% neutral parity passes.
'@ @'
- Pixel shader `e2aa1c8cb39e0a55` is the verified immediately downstream
  reflection-environment/SSR composite. Draw 1096 consumes the exact render
  target handle written by `b2bc6059f9a39c7f` on draw 1095, and its dataflow
  implements `SSR.rgb + environment.rgb * (1 - SSR.alpha)` with additional
  material weighting. The 100% full replacement passes native original parity,
  and a downstream 0/25/50/75/100% SSR-radiance matrix compiles strictly. The
  tested view showed no visible 0%-to-100% difference, but a diagnostic 1600%
  variant produced angle-dependent white screen-edge glow plus sparse reflective/
  specular scene and character-model response; F3's 0% side removed both. This
  proves the control point while leaving normal-range 0/100 and 50% validation
  pending in a stronger SSR view, so runtime packaging remains blocked.
'@

Update-TextFile 'src/Adapters/FF7RemakeIntergrade/shader-map.json' @'
      "status": "resource-flow-radiance-and-neutral-parity-verified-live-strength-pending",
'@ @'
      "status": "resource-flow-and-amplified-response-verified-normal-range-current-scene-inconclusive",
'@

Update-TextFile 'src/Adapters/FF7RemakeIntergrade/shader-map.json' @'
      "notes": "Draw 1096 immediately follows SSR producer draw 1095. ShaderUsage proves b2 o0 and e2 t11 share the exact handle 00000278082FF6E0 and resource hash 36f63b9f. Static dataflow samples t11, computes one minus SSR alpha for reflection-environment fallback, samples a TextureCubeArray, and adds SSR RGB after material weighting. The semantic descriptor matches only e2 among 184 cached shaders with 11 checks and zero regex timeouts. The live hit-mask probe produced no distinct visual change, while the radiance-presence probe showed cyan on nonzero SSR radiance and black where no SSR RGB contribution was present. The strict-compiled 100% replacement passed native-resolution parity against F9/original. The 0/25/50/75/100% downstream SSR-radiance matrix preserves the environment fallback path; 0% and 50% live strength validation remain pending. This combined output must not be scaled as an SSR-only control."
'@ @'
      "notes": "Draw 1096 immediately follows SSR producer draw 1095. ShaderUsage proves b2 o0 and e2 t11 share the exact handle 00000278082FF6E0 and resource hash 36f63b9f. Static dataflow samples t11, computes one minus SSR alpha for reflection-environment fallback, samples a TextureCubeArray, and adds SSR RGB after material weighting. The semantic descriptor matches only e2 among 184 cached shaders with 11 checks and zero regex timeouts. The live hit-mask probe produced no distinct visual change, while the radiance-presence probe showed cyan on nonzero SSR radiance and black where no SSR RGB contribution was present. The strict-compiled 100% replacement passed native-resolution parity against F9/original. The normal 0%-to-100% comparison produced no observable difference in the tested view. A diagnostic-only 0%-to-1600% A/B produced angle-dependent blown-white screen-edge glow plus sparse reflective/specular response on scene and character-model surfaces; F3's 0% side removed both effects. This proves the additive SSR-radiance control point, but normal-range 0/100 and 50% validation require a view with a stronger visible screen-space contribution. Runtime promotion remains blocked, and the combined output must not be scaled as an SSR-only control."
'@

$jsonFiles = @(
    'artifacts/probe-screenshots/e2aa1c8cb39e0a55-strength-1600-live-validation.json',
    'artifacts/ssr-composite-strength-diagnostics/RebirthSSRCompositeDiagnostic1600_ps.json',
    'artifacts/replacement-shaders/e2aa1c8cb39e0a55-ssr-composite-strength-control-pack.json',
    'src/Adapters/FF7RemakeIntergrade/shader-map.json'
)
foreach ($relativePath in $jsonFiles) {
    Get-Content -Raw -LiteralPath (Join-Path $repoRoot ($relativePath -replace '/', '\')) | ConvertFrom-Json | Out-Null
}

[pscustomobject]@{
    Result = 'updated'
    BackupRoot = $backupRoot
    FilesUpdated = 6
}
