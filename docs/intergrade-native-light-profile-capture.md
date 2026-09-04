# FF7 Remake native light-profile activation capture

## Question

All five accepted tiled-light compute variants contain the same native angular/IES-style profile path. A retained F8 capture proves that this path is populated, but camera projection now isolates the two visible red beacons as high-confidence records 1 and 0. Both beacon records have the native profile flags disabled. Their angle-dependent indirect contribution therefore needs to be tested against tiled-list membership and the separate screen-space GI sampler, not attributed to the profile branch.

The branch reads enable bits and a profile-row selector from the per-light data, samples the native angular profile atlas, and modulates the light color. Before changing this path, its runtime values and owning dispatch bucket must be captured.

## Family-derived target set

`New-IntergradeNativeLightProfileCapturePack.ps1` reads the accepted portable family-generation report, verifies its exact `3+1+1` membership and original-assembly hashes, then emits read-only analysis overrides for:

- classifier `f97a821dddaa328a`;
- Base-T5 members `08bb8764f1840179`, `0e97888f9a8767da`, and `c30cdc8365df9840`;
- Base-T4 member `5a9fbefe0ab6f815`;
- Frustum-T4 member `62b33a2d1e505241`.

The pack requests only `dump_rt dump_tex dump_cb mono desc` during the existing F8 frame analysis. It contains no replacement shader, resource assignment, render-state command, draw/dispatch command, or key binding. F10, F2, Page Up, and Page Down remain unchanged.

## Evidence gate

Take matched F8 captures at a view where the red-light contribution is present and a nearby view where it disappears. Compare records 0/1, their packed tile membership, and the indirect-light trace inputs. Do not infer a profile from bloom shape or wall color.

The generated artifact is `artifacts/intergrade-native-light-profile-capture-pack-v1`. `Test-IntergradeNativeLightProfileCapturePack.ps1` proves exact targets, `3+1+1` provenance, read-only commands, manifest checksums, and the reserved-key contract. The pack remains offline and uninstalled until a guarded transition is prepared while the game is closed.

## Retained-capture result

The older retained capture `FrameAnalysis-2026-08-30-211238` already contains consecutive dumps for all five accepted buckets. Their `cb3` payloads are byte-identical. Of the 256 possible per-light records, 28 have nonzero low-two-bit profile flags. Intersecting the native packed tile lists with geometrically contributing sampled lights leaves 19 profile-enabled candidates.

The three highest-ranked candidates are profile enabled: light 50 (14,000-unit radius), light 38 (1,700-unit radius), and light 54 (1,700-unit radius). Each has flag value `3` and profile row `0`; row zero is a valid sampled atlas row because the native shader enables the branch from the flag and samples `(row + 0.5) * atlasInverseHeight`.
Projecting every ranked light center through the captured view matrix isolates exactly two in-view candidates with radius at most 100 units and red dominance above 10x: record 1 at (2363.43, 1104.37) and record 0 at (2848.46, 1130.17). They share a 70-unit radius and the same strongly red color. Both have flag value 0, so neither executes the angular-profile branch.

The consumer layout holds 64 light indices per tile and clamps its loop count to 64. This capture's sampled tile counts range from 1 to 16 with median 3; no sampled tile reaches the capacity. That disproves the 64-light ceiling as the cause in this captured view. It does not yet rule out upstream membership changes between camera angles. Separately, the currently live SSGI trace uses four first-hit angular slices, which can naturally expose only a few contributors and change them as the view rotates.

tools/analyze_intergrade_native_light_profiles.py augments the preserved, fingerprinted contact-capture analysis without changing the analyzer used by the guarded contact-shadow stager. The current preserved local report is artifacts/analysis/intergrade-native-light-profile-membership-20260904-v4/analysis.json. This proves profile flags occur in ranked tile-member lights, identifies the high-confidence beacon pair as unprofiled, and proves the captured native list is unsaturated. A matched ON-angle/OFF-angle capture is still required to decide whether membership changes or four-slice screen-space sampling owns the transition.
