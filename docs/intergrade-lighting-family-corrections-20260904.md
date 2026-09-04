# FF7 Remake lighting-family corrections — 2026-09-04

This note supersedes the earlier interpretation of the five accepted tiled-light compute shaders. It does not change the live install.

## Proven family

The stable runtime sequence is:

1. classifier `f97a821dddaa328a`;
2. `c30cdc8365df9840` at indirect-argument offset 0;
3. `62b33a2d1e505241` at offset 12;
4. `5a9fbefe0ab6f815` at offset 24;
5. `0e97888f9a8767da` at offset 36;
6. `08bb8764f1840179` at offset 48.

Five independent captures preserve that order and use one indirect-argument buffer. These are material/tile specializations of one surface-light evaluator family. They are not exclusive face, skin, clothing, or individual-light shaders.

Every variant contains the same local-light dataflow:

- subtract reconstructed world position from a per-light position;
- calculate squared distance and normalize the pixel-to-light vector;
- conditionally evaluate inverse-square/radius attenuation;
- conditionally evaluate a spot cone from the per-light direction and spot angles;
- conditionally sample an angular light-profile atlas;
- multiply the current light color by the sampled profile scalar;
- combine the current light with prior lighting and write the result.

## Two corrected mistakes

The earlier three-read/modify/write plus two-direct-write split was an analyzer bug. It hard-coded prior lighting to `t9`. In two variants, the equivalent register pair shifts down: profile atlas `t7`, prior lighting `t8`. In three variants it is profile atlas `t8`, prior lighting `t9`. All five read, combine, and rewrite prior lighting.

The old label “infinite/non-radial attenuation bypass” for `cb4[index+512].w` was too strong. The flag selects between unity and the local distance-attenuation expression, but the shader still uses a per-light position, local pixel-to-light vector, spot logic, and profile logic. The safe name is **local-light distance-attenuation-mode flag**. Its exact native field identity is not yet proven, and it must not be used as a directional-light classifier.

## Native angular/IES-style profiles

The native angular profile mechanism is integrated per light in all five shaders. It is guarded by the low two bits of `cb3[index+768].x`; its profile row comes from `cb3[index+768].z`; and its sampled scalar modulates `cb4[index+512].xyz` light color.

This proves the native mechanism, not that the current red beacon activates it. A representative patterned light still needs a runtime capture of the flag/index or sampled contribution.

## Indirect-light boundary

All three current `SampleGI` near matches are disqualified. In particular:

- `a26b3473289dba2d` is full-resolution motion/depth evaluation plus a 16x16 tile reduction;
- `58101bdcc044cd88` is the following 9x9 motion-vector tile dilation;
- neither shader may be replaced as an indirect-light pass.

The prepared next experiment remains `c473ab75b7519f7e-ps`, immediately before that native velocity chain. The existing late-scene composite remains the visually confirmed no-feedback fallback.

## Remaining coverage and safe next order

Still unresolved:

- the actual sun/directional-light owner;
- live activation of the integrated angular-profile branch;
- runtime ownership of unshadowed tiled direct-diffuse candidate `adb544f9a11d6c7e`;
- an exact native `SampleGI` shader in the current regional census.

Next order:

1. With the user present, test the already compiled c473 pre-temporal pack: F2 off must be exact native parity, then F2 on while rotating around a local light and receiving wall.
2. Capture an outdoor sun-lit scene and identify directional ownership independently.
3. Instrument a visibly patterned local light to verify the native angular-profile flags/index.
4. Runtime-own `adb544f9a11d6c7e` before changing it.
5. Only then promote contact/falloff changes into the full five-bucket automatic family template.

Key contract remains fixed: F10 is shader reload; F2 is indirect-light testing; Page Up is the active foreground test cycle only when configured; Page Down is the graduated master toggle only when configured.

## Machine-readable evidence

- `artifacts/analysis/intergrade-tiled-light-dispatch-sequence-20260904.json`
- `artifacts/analysis/intergrade-tiled-light-profile-branch-20260904.json`
- `artifacts/analysis/intergrade-tiled-local-light-dataflow-20260904.json`
- `artifacts/analysis/intergrade-native-velocity-sequence-20260904.json`
- `artifacts/analysis/intergrade-lighting-coverage-resolution-20260904.json`
- `artifacts/analysis/intergrade-lighting-family-model-20260904.json`

