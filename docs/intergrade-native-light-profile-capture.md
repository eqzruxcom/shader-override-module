# FF7 Remake native light-profile activation capture

## Question

All five accepted tiled-light compute variants contain the same native angular/IES-style profile path. A retained F8 capture now proves that this path is populated by lights participating in the captured scene; it does not yet identify the current red beacon's exact light index. Glow, bloom, and a colored wall contribution alone remain insufficient evidence of profile activation.

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

## Retained-capture result

The older retained capture `FrameAnalysis-2026-08-30-211238` already contains consecutive dumps for all five accepted buckets. Their `cb3` payloads are byte-identical. Of the 256 possible per-light records, 28 have nonzero low-two-bit profile flags. Intersecting the native packed tile lists with geometrically contributing sampled lights leaves 19 profile-enabled candidates.

The three highest-ranked candidates are profile enabled: light 50 (14,000-unit radius), light 38 (1,700-unit radius), and light 54 (1,700-unit radius). Each has flag value `3` and profile row `0`; row zero is a valid sampled atlas row because the native shader enables the branch from the flag and samples `(row + 0.5) * atlasInverseHeight`.

`tools/analyze_intergrade_native_light_profiles.py` augments the preserved, fingerprinted contact-capture analysis without changing the analyzer used by the guarded contact-shadow stager. The preserved local report is `artifacts/analysis/intergrade-native-light-profile-membership-20260904-v1/analysis.json`. This proves native profile flags occur in ranked tile-member lights and makes angle-dependent illumination a native-light hypothesis. It does not prove which record owns the red beacon, reproduce the profile-atlas sample, or prove that every observed angle transition is intentional.
