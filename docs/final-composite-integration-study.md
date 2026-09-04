# Final composite integration study — 2026-08-30

## Current live observation

The user reported `yes - off`, then clarified `or mostly`: the light haze is
mostly reduced by the static Reinhard-only test. Do not record a complete
fog disable, nor assume that the rest of the scene is unchanged. No screenshot
or additional repetition is required to accept this observation.

The current tone-mapping-only reload passed with no matched errors. Its log
recorded repeated `$ue4fx_scene_tonemap_ab` transitions between 0 and 1; the
last observed transition was 1 -> 0 (original). These events support the user's
A/B result but do not measure pixels. The preceding neutral-only rebuild had
no reported fog loss. Therefore neither a dynamic IniParams dependency nor a
fog-control command is necessary to reproduce the haze reduction. This does
not prove the dynamic implementation has no independent defects.

The installed test has not been changed during this investigation. It remains
the static Reinhard/original Page Down comparison. No new F10 is needed.

## Preserved authoritative evidence

Study directory:
`artifacts/final-composite-study-20260830-220038-889`.

It contains the original cached binaries, cached decompilations, and fresh FXC
disassemblies for `eda405f2d455d5c7`, `4170b0f1040d507f`,
`18305e60b4378edb`, and `41f1bf8b79d01319`. It also preserves the captured
frame log, live tone-mapping log, and current reload status. This is local
analysis evidence, not a redistributable game-shader package.

Original final-composite binary SHA256:
`8B7DB294C666E296D4974929E41892BE44D2BF6984B0BF1511788117A6E4C263`.

## Resource chain from the captured frame

These links use exact resource handles, not equal resource hashes alone:

1. Draw 1141 (`af6cd28a0108a18a`) writes `0x000002780FF6DBA0`.
2. Draw 1142 (`eda405f2d455d5c7`) reads that handle at t0 and writes
   `0x000002780FF6D0A0`. Its source is another motion-sample resolve, not a
   final tone curve.
3. Draw 1143 (`4170b0f1040d507f`) reads that result at t0 and writes
   `0x00000278082F54A0`, beginning a subsequent filtering chain. Its source
   performs weighted resampling and a view-dependent multiplier.
4. Draw 1173 (`18305e60b4378edb`) combines the scene at t0
   (`0x000002780FF6D0A0`) and filtered input at t1
   (`0x00000278082F54A0`), writing `0x00000278082EBAA0`.
5. Draw 1174 (`41f1bf8b79d01319`) reads that final scene at t1 and applies
   color transforms/LUT lookups before combining a separate texture at t4.

Thus the current Reinhard diagnostic changes input upstream of filtering and
the game's final color mapping. Haze attenuation from this placement is
plausible, but the exact contributing visual mechanism remains unmeasured.
Do not claim this experiment has replaced the game's native tone mapping.

## Useful boundary inside the final shader

The original final-composite assembly reads scene color from t1, samples 3D
tables t2/t3, selects a color-transform branch using cb0[38].x, performs further
color conversions, and then samples t4 into r1. The scene stays in r2 through
the subsequent saturation adjustment. The overlay combination is:

```
mul r0.w, r1.w, cb0[25].y
mad_sat r1.xyz, r2.xyzx, r0.wwww, r1.xyzx
```

Afterward it applies output transfer and dithering. The t4 resource
`0x00000278082F0220` was bound/cleared as an earlier render target at draw1124,
then sampled by this final composite. Its role as the UI/overlay path is a
strong candidate from this composition structure, but separate live UI
preservation must still be verified.

The old whole-pass skip that froze the world and disturbed UI does not rule
out editing only the scene branch while preserving the overlay combination.
It tested omission of the entire presentation operation, not a selective edit.

## Next implementation gate

Prefer a minimal original-assembly edit of the scene branch over blindly
rebuilding the cached HLSL. The latter contains invalid `tx`, `rx`, and `state=`
placeholder text for two Texture3D GetDimensions operations, so it is not
compilable as captured. Any reconstructed HLSL must preserve those unsigned
dimension comparisons and all unrelated color/UI logic.

First establish an unchanged binary/assembly round trip and bindings. Then
prepare a single scene-only change with true original on the off side, retain
the original overlay blend/output transfer/dither, and validate it before
live installation. A post-LUT adjustment is distinct from replacement of the
native tone curve; implementing the latter additionally requires auditing the
input scaling, LUT semantics, and selected branch. Keep all production and
cross-game claims pending until their own evidence exists.
