# Intergrade lighting live-transition plan — 2026-09-04

## Safety state

- No live game or `F:` files were changed during this offline pass.
- DXVK remains paused.
- `F10` remains shader reload only.
- `F2` remains the indirect-light test toggle.
- The accepted automatic contact-shadow family is the protected live baseline.

## Confirmed live baseline

The current live `Mods\ContactShadows.ini` is the accepted automatic ShaderRegex family with SHA-256:

`F86A81DEE319C6A6E98933D4AC99C0477B6E5D8B43E6F7D29272FDDA476B5478`

It matches both the accepted generated and rebuilt family artifacts. The five former explicit contact-shadow replacements are intentionally absent; their behavior is now supplied by the automatic family.

The accepted late-scene SSGI predecessor consists of eight `Mods` files plus:

`ShaderFixes\af6cd28a0108a18a-ps.txt`

The live files match the accepted `agent2-r3d-ssgi-late-scene-pack` payload.

## Important transition finding

The prepared `c473ab75b7519f7e` pre-temporal pack replaces the late-scene injection location, but a normal copy would leave the accepted `af6cd28a0108a18a` replacement installed. That could execute both injection paths in the same frame, producing double or inconsistent lighting.

The new transition stager therefore treats the change as one nine-file transaction:

1. Back up the eight accepted late-scene `Mods` files and the `af6...` shader replacement.
2. Stage the eight `c473...` pre-temporal files.
3. Quarantine/remove the old `af6...` shader replacement.
4. Verify every staged checksum and verify `af6...` is absent.
5. On restore, reject drift and restore all nine predecessor files exactly.

Offline fixture testing proves the nine-file transition, `af6...` quarantine, drift rejection, and exact restoration. A live `-WhatIf` preflight also passes.

## Lighting ownership capture

The retained frame captures do not contain executions of either remaining target:

- `aadc1c2374853914-ps`: directional cascade-shadow-factor producer.
- `adb544f9a11d6c7e-cs`: unshadowed tiled local-light candidate.

That absence is scene-specific evidence only; it does not mean the shaders are unused.

The new capture pack adds read-only frame-analysis triggers for those two hashes. It requests only resource/constant-buffer metadata dumps and does not replace shaders, bind resources, issue draws/dispatches, or change render state.

The resource-flow analyzer reconstructs PS/CS SRVs, CS UAVs, and output-merger render targets in frame-log order. For each target execution it records outputs, later consumers, and overwrites. Its control tests prove:

- `c473...` output reaches `af6...-ps:t0` in the known capture.
- `a26...` UAV 1 reaches `58101...-cs:t0` in the known capture.
- An absent `adb...` is reported as not observed, not misclassified as unused.

## Next live sequence

Do not combine discovery and visual tuning in one run.

### A. Ownership capture first

1. Stage the capture-only pack with `Stage-IntergradeLightingOwnershipCapture.ps1`.
2. Launch normally and visit two controlled locations:
   - an outdoor/directional-shadow scene for `aadc...`;
   - a dense local-light scene for `adb...`.
3. Use the existing `F8` frame-analysis capture only when the target lighting is visible.
4. Exit the game and restore the capture pack immediately.
5. Run `Analyze-IntergradeShaderResourceFlow.ps1` on each new frame log.

Success means the log proves the target executes and identifies its output resource plus its first downstream consumer. If a target does not execute, change scenes rather than editing shaders blindly.

### B. Pre-temporal SSGI validation second

1. Confirm the game is closed.
2. Stage the `c473...` transition with `Stage-IntergradeR3DSSGIPreTemporal.ps1`.
3. Launch and compare `F2` off/on at a fixed camera near a small emissive light.
4. Rotate and move far enough to test the previously observed angle dependence and stale-frame persistence.
5. Press `F10` only as a shader reload diagnostic, never as a test-cycle key.
6. Exit and restore through the same stager.

Acceptance requires all of the following:

- no white skin or material corruption;
- no shader-family rejection/error OSD;
- no accumulated or frozen previous-frame light;
- `F2` produces a repeatable difference;
- the effect does not disappear merely because the camera crosses the prior angle boundary;
- contact-shadow and frustum behavior remains unchanged.

## Files

- `tools\New-IntergradeLightingOwnershipCapturePack.ps1`
- `tools\Stage-IntergradeLightingOwnershipCapture.ps1`
- `tools\Analyze-IntergradeShaderResourceFlow.ps1`
- `tools\Stage-IntergradeR3DSSGIPreTemporal.ps1`
- `artifacts\intergrade-lighting-ownership-capture-pack-20260904-v1`

