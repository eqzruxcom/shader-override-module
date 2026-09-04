# Static tone-mapping isolation — 2026-08-30

The user reported that neither F10 nor Page Down removed the fog in the
neutral-only comparison. The live log confirms reload and neutral A/B state
transitions 0 -> 1 -> 0 -> 1, with no matched parser errors. This supports
scene-specific visual parity, not universal equivalence or exact pixel parity.
It supersedes the pending neutral comparison in `scene-post-neutral-isolation.md`.

Evidence is preserved under
`artifacts/scene-post-neutral-confirmed-20260830-215313-337`.

## Next isolated change

`New-IntergradeScenePostTonemapIsolation.ps1` compiles an otherwise unchanged
scene shader with a static Reinhard operator on its RGB output. The INI gates
the custom draw with a single global variable:

- F10: default 0, actual original game execution.
- Page Down: 0/1 toggle, original versus static Reinhard.
- No fog/AO overrides, saturation adjustment, or shader parameter texture reads.
- Alpha stays zero, matching the captured shader.

This tests tone-mapping math without the earlier dynamic IniParams setup or
other effect controls. It is not a replacement for the game's original
tonemapper, whose color domain/integration is still unverified. No production
eligibility was granted.

The payload reuses `Mods/RebirthScenePostNeutral_ps.hlsl` as the destination
filename so both files in the preceding neutral test are replaced and backed
up together. Its contents are now the static Reinhard test, not neutral HLSL.

## Verification and installation

The new strict-compilation/payload/reload test passed, as did the unchanged
neutral-isolation and diagnostic-reload regression tests. The new test checks
default-original state, gated custom execution, preserved alpha, no dynamic
parameter use, file hashes, overwrite refusal, and incomplete/complete log
fixtures. These checks do not substitute for the user's visual result.

Current install manifest:
`artifacts/installed-scene-post-tonemap-isolation-overlay.json`.

Backup of the preceding neutral comparison:
`backups/GeneratedRuntimeOverlay/20260830-215313-781`.

Current generated directory:
`artifacts/generated-runtime/FF7RemakeIntergradeScenePostTonemapIsolation`.

Its reload baseline is byte offset 281899 for responding PID 48440. Immediately
after staging, status was `pending-no-reload` with zero appended bytes. F10 and
the user's report remain required. Do not monitor the old neutral baseline
for this test.

Uninstalling this overlay with its manifest restores the verified neutral
comparison. To return to the production baseline instead, uninstall this
overlay first, then the preceding neutral-isolation overlay, checking hashes
and reloading once after both restorations.
