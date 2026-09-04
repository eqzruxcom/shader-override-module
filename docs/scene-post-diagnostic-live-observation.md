# Scene-post diagnostic: live observation, 2026-08-30

## Current outcome

The user reported **"fog lighting off"** in response to the Page Down
None/Reinhard test. Accept this as the observed result. It does not establish
a successful scene-wide tonemap or a cause for the missing fog lighting.
Do not promote this diagnostic to a production tonemap on this evidence.

## Inspected evidence

- The installed diagnostic targets pixel shader `af6cd28a0108a18a`.
- Live `Mods/UE4EffectsGenerated.ini` binds unmodified Page Down to
  `w101 = 0.0, 1.0` and Home to the separate temporal-volume variable.
- The appended log after the diagnostic baseline records repeated `w101`
  transitions between zero and one. Its last inspected transition is
  `1.0 -> 0.00`.
- The reload initializes the temporal-volume and ambient-occlusion variables
  to `4.000000` (original). No changes to those variables appear in the
  inspected post-baseline key events.
- A search of live Mods/ShaderFixes INI and HLSL files finds the diagnostic
  binding and shader as the only active consumers found for this tonemap
  parameter. There is no observed Page Down/fog-control collision.
- The exact inspected FF7 process is PID 48440, started 2026-08-30 14:35:08
  local, and responds to the process health query. This is not visual proof.

## Correction to the comparison procedure

Live `d3dx.ini` configures `show_original = no_modifiers VK_F9` under a
comment instructing the user to hold the key temporarily. Earlier instructions
incorrectly described two F9 taps as persistent off/on states.

The user's earlier "same" report is retained, but does not independently
prove a sustained originals-versus-replacement comparison under those
instructions. Neutral parity must therefore remain unverified.

## Next discriminating observation

While the fog lighting is absent, hold F9 for two seconds, observe the scene,
then release it. Ask whether the missing fog lighting returns while held.
Do not infer a result from silence or from the process remaining responsive.
Do not change runtime files or request another F10 before that observation.

Relevant local evidence: the diagnostic's `live-reload-baseline.json`,
`live-reload-status.json`, and `runtime-manifest.json` under
`artifacts/generated-runtime/FF7RemakeIntergradeScenePostDiagnostic`, plus
`artifacts/installed-scene-post-diagnostic-overlay.json`.
