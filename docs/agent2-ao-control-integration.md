# Agent 2 AO control and owner integration

Date: 2026-09-01

This note is intentionally separate from the concurrently edited AO plan.
It records the user's corrected control assignment and the current runtime
topology without overwriting another task's active work.

## Authoritative control assignment

- F1 is reserved for the future global mod on/off switch. AO must not use it
  as an Original/native preset selector.
- F2 is the single binary test control for the current shader change:
  off preserves the existing shader owner; on runs one reviewed candidate.
- F3 is not owned by AO. The current shared runtime uses it for
  `KeyRebirthRollingAB`; that ownership is preserved until separately
  resolved.

Therefore the `F1 Original / F2 Balanced / F3 Strong` metadata present in the
consumer-variant review package is not authoritative. Balanced is an invented
conservative interpolation. Strong is the literal Rebirth Performance fallback
and compiles to the same object as Agent 2's canonical donor-literal candidate.

## Current single-owner topology

`runtime/Intergrade/Mods/RebirthEffectsDX11.ini` owns
`e2aa1c8cb39e0a55` exactly once under
`ShaderOverrideRebirthABShared`. Both rolling A/B branches currently run the
same neutral 100%-SSR custom replacement. Adding a second standalone override
for the same hash is rejected.

The offline owner-integration preview:

- requires the exact current owner SHA recorded in its manifest;
- adds F2 exactly once;
- keeps one `e2aa...` override;
- runs the literal donor fallback candidate only when F2 is on;
- nests the unchanged rolling A/B owner under F2 off;
- preserves F3 without assigning it to AO; and
- changes neither project runtime nor the live game.

Artifacts:

- `tools/New-IntergradeRebirthFallbackAOF2OwnerIntegrationPack.ps1`
- `tools/Test-IntergradeRebirthFallbackAOF2OwnerIntegrationPack.ps1`
- `tools/Analyze-IntergradeAOControlOwnership.ps1`
- `tools/Test-IntergradeAOControlOwnership.ps1`
- `tools/Analyze-IntergradeAOShaderTestMatrix.ps1`
- `tools/Test-IntergradeAOShaderTestMatrix.ps1`
- `tools/Stage-IntergradeRebirthFallbackAOF2OwnerIntegration.ps1`
- `tools/Test-IntergradeRebirthFallbackAOF2OwnerStage.ps1`
- `artifacts/ao-rebirth-fallback-consumer-f2-owner-integration-pack/`
- `artifacts/analysis/agent2-ao-control-ownership.json`
- `artifacts/analysis/agent2-ao-shader-test-matrix.json`

Live staging remains unauthorized and unperformed. It requires a review of the
exact owner SHA, preservation or separate resolution of the F3 rolling A/B
purpose, and fixed-camera F2 off/on validation.

The staging tool is prepared but has only been exercised against workspace
fixtures. It validates the exact pack and owner hashes, refuses extra F2 or
`e2aa...` claims, backs up both destinations, verifies post-copy hashes, and
supports Status and Restore. Restore refuses to overwrite either staged file
after drift. External targets require an explicit switch and must end in the
exact FF7 Remake `End/Binaries/Win64/Mods` path; external backups are restricted
to `F:/Shader3Dmigoto/Agent 2`.
