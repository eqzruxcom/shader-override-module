# FF7 Remake native light-profile activation capture

## Question

All five accepted tiled-light compute variants contain the same native angular/IES-style profile path, but retained evidence does not prove that the current red beacon—or any particular visible light—activates it. Glow, bloom, and a colored wall contribution are not sufficient evidence of profile activation.

The branch reads enable bits and a profile-row selector from the per-light data, samples the native angular profile atlas, and modulates the light color. Before changing this path, its runtime values and owning dispatch bucket must be captured.

## Family-derived target set

`New-IntergradeNativeLightProfileCapturePack.ps1` reads the accepted portable family-generation report, verifies its exact `3+1+1` membership and original-assembly hashes, then emits read-only analysis overrides for:

- classifier `f97a821dddaa328a`;
- Base-T5 members `08bb8764f1840179`, `0e97888f9a8767da`, and `c30cdc8365df9840`;
- Base-T4 member `5a9fbefe0ab6f815`;
- Frustum-T4 member `62b33a2d1e505241`.

The pack requests only `dump_rt dump_tex dump_cb mono desc` during the existing F8 frame analysis. It contains no replacement shader, resource assignment, render-state command, draw/dispatch command, or key binding. F10, F2, Page Up, and Page Down remain unchanged.

## Evidence gate

Prefer a visibly patterned local light; the current red beacon can still establish an inactive-versus-active profile state. Take one fixed-scene F8 capture, identify the executing family bucket, then inspect the dumped per-light constant-buffer values and profile texture. Do not infer a profile from bloom shape or wall color.

The generated artifact is `artifacts/intergrade-native-light-profile-capture-pack-v1`. `Test-IntergradeNativeLightProfileCapturePack.ps1` proves exact targets, `3+1+1` provenance, read-only commands, manifest checksums, and the reserved-key contract. The pack remains offline and uninstalled until a guarded transition is prepared while the game is closed.
