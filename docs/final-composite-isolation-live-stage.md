# Final-composite assembly isolation — staged, not yet loaded

## Preceding observation

The user described the static Reinhard comparison as light haze off or mostly off, then clarified that apparent haze behind it may be baked into the background. Treat the toggle observation as the evidence; do not interpret residual bright wall patches as proof that volumetric fog remains active. The supplied screenshot `codex-clipboard-6310a99b-fe17-4944-a310-2658992ca1ed.png` shows the remaining appearance but does not establish its rendering mechanism.

Static Reinhard at `af6cd28a0108a18a` reproduced the haze reduction without fog overrides or dynamic shader parameters. Neutral reconstruction was previously visually unchanged in this scene. This narrows the problem to the tone operation/placement; it does not prove every earlier dynamic implementation was correct.

## Current stage

- Adapter: `FF7RemakeIntergradeFinalCompositeIsolation`.
- Hash: `41f1bf8b79d01319`, final composite.
- Native loading path: `ShaderFixes/41f1bf8b79d01319-ps.txt` assembly, not CustomShader HLSL or a spoofed binary cache.
- Generated directory: `artifacts/generated-runtime/FF7RemakeIntergradeFinalCompositeIsolation`.
- Install manifest: `artifacts/installed-final-composite-isolation-overlay.json`.
- Backup: `backups/GeneratedRuntimeOverlay/20260830-223918-912`.
- Game PID: 48440, responding at staging.
- Reload baseline: log byte offset 308905.
- Initial status: `pending-no-reload`; **no successful native reload or visual result yet**.

Two files were installed: the generated INI and the assembly replacement. The previous Reinhard HLSL remains on disk but is not invoked by this INI. No fog, AO, SSR, or upstream scene override is active in the new INI. `d3dx.ini`, hunting=2, F9 semantics, and cache settings were unchanged and hash checked.

## Controls and limitations

F10 reloads. Page Down alternates 0 and 1, starting at 0. State 0 retains the original shader calculations within the replacement. State 1 inserts a numeric 0.5 scene multiplier after native color mapping and before the suspected overlay blend. This is a boundary diagnostic, **not replacement of the native tonemapper** and not a perceptual 50% brightness claim.

The off state is **not an actual native shader switch**. It adds a parameter read and branch using a separate temporary register, but skips the brightness instruction. The unchanged original assembly round trip is byte-identical to the captured original. In the toggle variant, all 134 original instruction/declaration tokens other than the temp-count declaration are byte-identical. The temp count changes 12 to 13; one resource declaration plus five diagnostic instructions are added. The original math is unchanged, but GPU/pixel equivalence has not been independently measured.

Original SHA256: `8B7DB294C666E296D4974929E41892BE44D2BF6984B0BF1511788117A6E4C263`.

Toggle SHA256: `79422F03492009C266BAD83B6F729D5DF32D160A24E80C6C389A822888D4007C`.

The key assigns x30 for this shader. Its extra t120 load is gated by an exact equality to 1. Original t0–t4 resource declarations, output transfer, dithering, viewport logic, and alpha are preserved. UI preservation remains a live hypothesis.

## Verification and next gate

Passed this turn:

- `Test-IntergradeFinalCompositeCandidate.ps1` (original binary round trip and static one-instruction edit).
- `Test-IntergradeFinalCompositeIsolation.ps1` (toggle bytecode, original token preservation, payload manifests, default off, output confinement, overwrite refusal).
- `Stage-IntergradeFinalCompositeIsolation.ps1 -WhatIf` against exact live predecessor.
- Two-file backed-up installation and initial pending status read.

Do not report the full project suite as run. Use `Get-IntergradeFinalCompositeReloadStatus.ps1` after F10: it requires both generated-INI parser success and an exact successful native assembly shader reload message, which follows GPU shader creation. INI parsing alone is insufficient.

Next visual question: does Page Down clearly dim the scene while the HUD remains unchanged? Accept the user's answer; request screenshots only if they are unsure. Pause for that input rather than starting another experiment. No HDR testing.

Rollback uses `Uninstall-UE4GeneratedRuntimeOverlay.ps1 -InstallManifestPath artifacts/installed-final-composite-isolation-overlay.json`, then F10. It removes the exact unchanged diagnostic ASM and restores the preceding Reinhard INI. For actual clean baseline, remove the diagnostic layer and use the preceding adapter's state 0; do not rely on F9 while hunting=2.
