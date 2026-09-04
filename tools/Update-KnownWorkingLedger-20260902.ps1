[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$path = Join-Path $root 'docs\known-working-code.md'
$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$backupRoot = Join-Path $root "artifacts\migrations\$stamp-known-working-ledger"
[IO.Directory]::CreateDirectory($backupRoot) | Out-Null
Copy-Item -LiteralPath $path -Destination (Join-Path $backupRoot 'known-working-code.md.pre-update')

function Replace-Exact([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    if ($count -ne 1) { throw "$Label expected one exact occurrence, found $count" }
    return $Text.Replace($Old, $New)
}

$text = Get-Content -Raw -LiteralPath $path
$oldWorking = @'
- **What worked:** the source-preserving donor contact-shadow port loads and
  produces added contact shadows in Remake. User: "its stable" and "that said it
  looks working in most cases". Home provides the current effect OFF/ON comparison.
'@
$newWorking = @'
- **What worked:** the source-preserving donor contact-shadow port loads and
  produces added contact shadows in Remake. User: "its stable" and "that said it
  looks working in most cases". The original live experiment used Home. The
  currently promoted runtime uses **Page Down** as the sole accepted-code master;
  Page Up is free for the next experiment and F10 remains reload-only.
'@
$text = Replace-Exact $text $oldWorking $newWorking 'Current contact control'

$oldEdge = @'
### Left-edge fade qualification (2026-08-31)

The first left-only fade was confirmed to act by the user, with 1% the closest
old preset, but they reported snap-back on re-entry. Keep this as partial
evidence, not a finished edge fix. The follow-up 0.5%-zero / 4%-full strength
profile is a separate experiment, not a replacement for the preserved donor.
It fades added darkness spatially; it is neither temporal accumulation nor
softening the shape of all contact shadows. See `contact-left-edge-fade-experiment.md`
for its latest staging/load status. Do not count an offline pass as a live pass.
'@
$newEdge = @'
### Left-edge frustum fix qualification (2026-08-31, promoted 2026-09-01)

The early left-only fade experiments remain historical evidence, including the
reported snap-back. A later spatial profile was promoted as `//Frustum Fix` in
`62b33a2d1e505241-cs.txt`. The user then motion-tested it while running and
reported that it worked "phenomenally" and became easy to forget. It fades only
the added contact contribution near the left screen boundary; it does not add
geometry, extend the camera frustum, accumulate temporal history, or soften all
contact-shadow shapes. Resolution/FOV behavior is normalized to the shader's
screen coordinate rather than a fixed pixel count.

Authoritative live audit:
`artifacts/runtime-toggle-audits/20260901-164027-570/manifest.json`. It records
the five accepted compute replacements, their hashes, the Page Down guard, and
zero Page Up consumers. Preserve the original first-working snapshot and the
Frustum Fix checkpoint separately; neither is overwritten by this status note.
'@
$text = Replace-Exact $text $oldEdge $newEdge 'Frustum qualification'

$anchor = @'
| Reflection shader identification | Diagnostic material coverage worked | Normal-range reflection strength, still not visually validated in a suitable view |
'@
$familyStatus = @'
| Reflection shader identification | Diagnostic material coverage worked | Normal-range reflection strength, still not visually validated in a suitable view |

### Current reviewed shader-family coverage (2026-09-02)

The authoritative Remake catalog now contains **34 exact shader identities in
13 verified families**. It preserves the dynamic/static ShadowDepth split, the
Cloud clothing VS/PS material pair, all five accepted tiled local-light compute
variants, temporal SSAO, SSR, and the reflection/indirect composite boundary.

Three of the 11 Rebirth donor families now have explicit Remake relations:

1. `local-light` -> `tiled-surface-light-evaluation`: working contact-shadow
   adapter in the current area.
2. `ssr` -> `screen-space-reflection-trace-resolve`: verified semantic role and
   two known Remake variants; effect port still requires a live visual gate.
3. `reflection-environment` -> `reflection-indirect-composite`: verified only as
   a **partial downstream consumer boundary**. This does not equate Rebirth's
   SSGI/AO producer with Remake's temporal SSAO.

All 11 donor families retain exactly one reviewed decision; the other eight
remain unresolved rather than guessed. The machine-readable sources are
`src/Adapters/FF7RemakeIntergrade/verified-shader-classifications.json` and
`src/Adapters/FF7RemakeIntergrade/rebirth-family-relations.json`.

For terminology and controls, see
[`helixmod-to-3dmigoto-workflow.md`](helixmod-to-3dmigoto-workflow.md).
'@
$text = Replace-Exact $text $anchor $familyStatus 'Reviewed family status'

[IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
$receipt = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    result = 'updated-known-working-ledger'
    backup = (Join-Path $backupRoot 'known-working-code.md.pre-update')
    output = $path
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
}
[IO.File]::WriteAllText((Join-Path $backupRoot 'receipt.json'), (($receipt | ConvertTo-Json -Depth 5) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Host "PASS: updated known-working ledger; backup: $backupRoot"
