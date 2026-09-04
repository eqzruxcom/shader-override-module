# FF7 Remake Intergrade SSGI pre-temporal stabilization

## Result

The late-scene SSGI build is the first visually confirmed no-feedback foundation. It produces real indirect light and updates with the current frame without requiring F10. Its remaining camera-angle appearance/disappearance is expected from screen-space source visibility, but the current placement makes that transition unnecessarily abrupt: the indirect result is added after Remake's temporal resolve.

The offline successor in `artifacts/agent2-r3d-ssgi-pre-temporal-pack` moves only the writeback boundary. It traces the same current-frame scene radiance and geometry, constructs `native scene + indirect RGB` in a private texture, binds that texture as the native temporal resolver's current-scene input, and executes the original temporal shader unchanged.

## Verified native contract

The retained `c473ab75b7519f7e-ps` assembly declares:

- `t2`: current scene color;
- `t3`: temporal history;
- `t4`: motion data;
- native history sampling and rejection logic;
- `CB1[140]`: the matching UE view buffer layout used by the candidate shaders.

The frame capture orders the relevant passes as lighting/reflection composition, `c473` temporal resolve, then `af6cd` final scene color. This makes `c473` the appropriate stabilization boundary.

## Safety properties

- F2 remains the only candidate control.
- F10 remains native reload and is not rebound.
- Page Up, Page Down, F1, F3, and the contact-shadow number keys are untouched.
- F2 off runs no private draw and leaves native `c473 t2` unchanged.
- No render-target `o0` copy or reference is used as an SSGI source.
- Native `c473 t3` history and `t4` motion bindings are untouched.
- Native `c473` and `af6cd` shader binaries are not replaced.
- All seven SM5 HLSL shaders compile with strict FXC settings.
- The INI resource graph matches pinned 3DMigoto `copy_desc`, `reference`, post-restore, output-merger save/restore, and viewport behavior.

## What this can and cannot improve

Passing the indirect result through native temporal accumulation should reduce immediate stochastic noise and soften one-frame camera-angle popping. It cannot make screen-space emitters visible after they leave the screen or become occluded. Solving that limitation requires an off-screen radiance cache, probes, voxel/mesh data, or ray tracing—not a stronger SSGI multiplier.

Native temporal history may also retain incorrect indirect light during fast motion or disocclusion. Therefore the candidate remains offline and `runtimeEligible=false` until live tests cover fixed-camera F2-off parity, slow orbit, fast pan, camera cut, character materials, menus, resolution/FOV changes, and GPU cost.

## Evidence

- Working foundation: `artifacts/agent2-r3d-ssgi-late-scene-pack`
- Visual acceptance receipt: `artifacts/agent2-r3d-ssgi-late-scene-pack/validation/live-visual-acceptance-20260903.json`
- Pre-temporal candidate: `artifacts/agent2-r3d-ssgi-pre-temporal-pack`
- Generator: `tools/New-IntergradeR3DSSGIPreTemporalPack.ps1`
- Regression test: `tools/Test-IntergradeR3DSSGIPreTemporalPack.ps1`
