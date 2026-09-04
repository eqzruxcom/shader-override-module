# Original versus neutral scene-post isolation

## Baseline recovered

This updates the pending verification in `scene-post-baseline-restoration.md`.
The user confirmed that fog lighting returned after the baseline reload.
The production `live-reload-status.json`, checked at 2026-08-30T21:32:05Z,
records `passed-live-parser-reload`, no matched errors, and 16199 appended
bytes after offset 127697. Parser success supports reload detection; the
user's report supplies the visual result.

## Current diagnostic

`artifacts/installed-scene-post-neutral-isolation-overlay.json` records the
minimal replacement installed for hash `af6cd28a0108a18a`. It is diagnostic
only, not a production promotion.

- F10 loads the diagnostic with `$ue4fx_scene_neutral_ab = 0`.
- Page Down switches between original game execution (0) and an unchanged
  decompiled rebuild through CustomShader (1).
- A second Page Down returns to original execution.
- No fog, AO, saturation, tone-mapping, or IniParams controls are included.
- F3 and F9 are not part of this comparison. F9 is gated by hunting mode in
  the current runtime and did not establish original parity earlier.

The neutral source SHA256 is
`F002901E2D8B0B5FAE5E01D6C1197D5EF45644925D4CDA23680325E8AA3CA3E7`.
This is source identity, not proof that recompilation preserves rendering.

The diagnostic reload baseline is in
`artifacts/generated-runtime/FF7RemakeIntergradeScenePostNeutralIsolation`,
at log offset 143896 for PID 48440. The latest check in this continuation
found the process alive and responding, zero appended bytes, and
`pending-no-reload`. The visual comparison remains pending; do not overwrite
the installed test before receiving the user's result.

## Outcome routing

- If fog changes with the neutral rebuild, investigate reconstruction or
  CustomShader execution before testing additional tone-mapping math.
- If the neutral rebuild appears unchanged, that is scene-specific visual
  evidence, not universal equivalence. Next isolate the dynamic controls.
- If the baseline itself is wrong, restore the production backup and resolve
  that before accepting any comparison.

## Archived dynamic math observation

The archived `RebirthPostSceneControls_ps.hlsl` calls
`Redx11ApplyTonemap` even when mode is zero. That function applies
`max(color, 0.0f)` before checking the selected mode, so zero mode is not an
exact bypass for negative inputs. Saturation at one also still passes through
the luma/lerp expression. These are source-level observations, not an
explanation of the reported fog loss: there is no evidence yet that negative
values caused the visible failure. Do not change the live isolation to test
these hypotheses concurrently.

## Recovery

After checking installed hashes, use
`tools/Uninstall-UE4GeneratedRuntimeOverlay.ps1` with install manifest
`artifacts/installed-scene-post-neutral-isolation-overlay.json` to restore
the preceding production INI and remove the temporary neutral HLSL. F10 is
required to apply that recovery to the running game.
