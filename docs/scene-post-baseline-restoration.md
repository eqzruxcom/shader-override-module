# Scene-post baseline restoration — 2026-08-30

This supersedes the next-test instruction in
`scene-post-diagnostic-live-observation.md`.

The user reported that holding F9 did not restore the missing fog lighting.
Local `reference/3Dmigoto/DirectX11/Hunting.cpp` shows that DisableFix and
EnableFix return unless hunting is enabled. The live config and latest reload
log show `hunting=2` (soft disabled), with no logged original-view activation.
The prior F9 comparisons do not validate original-shader parity.

Following user confirmation, the diagnostic overlay was rolled back:

- Restored the previous `Mods/UE4EffectsGenerated.ini` from its verified backup.
  Fog, saturation, and AO variables initialize to index 4 (game original).
- Removed the temporary `Mods/RebirthPostSceneControls_ps.hlsl` from the live
  directory after preserving it in the recovery archive.
- Found and archived an additional neutral decompiled replacement at
  `ShaderFixes/af6cd28a0108a18a-ps_replace.txt`. A neutral replacement is not the
  original game bytecode, so it must not remain in the baseline load path.
- Verified every restored production-overlay file against its install manifest.
- Captured a fresh production reload baseline at byte offset 127697 for the
  responding game process PID 48440.

Recovery archive:
`artifacts/scene-post-baseline-restore-20260830-212635-647`.
The archived neutral replacement SHA256 is
`F002901E2D8B0B5FAE5E01D6C1197D5EF45644925D4CDA23680325E8AA3CA3E7`.

At the time of restoration, the changes were on disk only: F10 reload and a
user report of whether fog lighting returns are still required. Check the
production `artifacts/generated-runtime/FF7RemakeIntergrade` reload baseline,
not the older scene-post diagnostic baseline. Do not request F9 or F3 for this
comparison and do not count parser success as visual validation. The cause of
the reported fog loss remains unresolved; no tonemap is promoted to production.
