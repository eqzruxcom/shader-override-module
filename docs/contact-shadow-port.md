# Portable contact-shadow ray test

Newest integration: [shared donor rays in the audited native outer light loop](rebirth-contact-shared-integration.md). Five variants assemble; 1,200 full-group interface cases pass. Consecutive-light reuse, shared captured replay, motion quality and hardware cost remain open. No deployment or live change.

Current status, 2026-08-31: **source reuse is the selected development path**. The pinned Rebirth ray, noise, and checkerboard/AVG statements are retained with provenance. Material/hair and native noise inputs are wired; an optional SM5 neighbor-recompute reconstruction prototype now compiles into five native variants. Six strict smoke compiles, 606 HLSL/resource cases and 15 creation checks pass. Matched reconstructed motion has fewer large changes but more false/missed shadow classifications; final engine temporal AA, phase resets, helper coverage and GPU cost remain unverified. See [current reconstruction evidence](rebirth-contact-reconstruction.md). No deployment is approved. The installed package that showed arm banding has not been replaced; that defect is not proven fixed.

See [source-preserving Rebirth integration](rebirth-contact-source-reuse.md) for the authoritative current implementation, evidence, missing donor caller features and next steps. Sections below describe the earlier experimental implementation and historical tests unless explicitly dated otherwise; their passing artifacts do not validate the new donor candidate.

## Historical experimental implementation

`ContactShadows.hlsl` now contains the separate geometric prototype, sharing only view/settings definitions and helpers from `ContactShadowCommon.hlsl`. Its pre-refactor source is archived under `artifacts/contact-motion-audit-20260831-quadrant-continuity-v11/ContactShadows-experimental.hlsl`. That prototype also failed motion checks. It is not the source-preserving donor and is not being promoted in place of it.

## Source and scope

`src/Effects/Lighting/ContactShadows.hlsl` adapts the improved-thickness local-light path from David Matos' `ShaderInjector`, pinned commit `bab25809b375f028b7c0fb603d804426f38c9b8e`, `ModifiedShaders/Includes/PixelShaderPass_LocalLight.hlsl`, approximately lines 1066-1366. Full MIT notice: `licenses/ShaderInjector-MIT.txt`.

Preserved algorithm features:

- Rays toward one local point/spot light, with a maximum length and exclusion region around the light.
- Pixel-scaled depth/normal bias, camera/side clipping, and rejection of sub-half-pixel rays.
- Perspective-correct interpolation of linear view depth along screen-linear sample positions.
- Finite depth-interval intersection, adaptive thickness, and grazing-dependent receiver exclusion.
- Distance falloff and configurable contrast, returning visibility in [0,1].

The donor defaults are available as a constructor, not a Remake quality preset. Default sample count is 16; 8 and 32 also compile. The component does not replace the native BRDF or add a full-screen AO multiplier.

## Deliberate port differences

- Inputs are explicit structs and function arguments, with no Rebirth resource slots, material IDs, or view-buffer offsets embedded in the effect.
- The caller supplies point-sampled device depth using explicit LOD, so the same algorithm compiles for SM5 pixel and compute stages.
- Position is **already translated world** on entry. Do not add pre-view translation twice. Matrix multiplication uses the donor's row-vector convention; an adapter must transpose/repack if its source uses the opposite convention.
- NDC-to-buffer bias is supplied already unswizzled. A UE4 `ScreenPositionScaleBias` source would supply `.xy` scale and `.wz` bias, after its actual binding is verified.
- Clipping additionally includes the D3D near/far planes and rejects invalid starting positions. Invalid/zero/infinite sampled linear depths are ignored.
- Sampling stays inside explicit viewport UV bounds, not just the entire allocation. Adaptive pixel footprint uses the viewport's pixel size. This is intentional for subrect rendering and must still be validated against Remake's actual view/allocation dimensions.
- Jitter is an argument. No blue-noise texture, frame-index assumption, checkerboard reconstruction, derivatives, or wave/quad intrinsics are copied. The SM5 baseline traces every selected pixel; this is not claimed to have the donor's performance.
- Only the improved interval-test/falloff path is ported. The legacy point test is not included. The loop is rolled rather than forcibly unrolled. Nonnegative controls and invalid light/viewport inputs have conservative guards.
- Material exclusions, hair-specific bias, sky rejection before tracing, strength, and per-light application belong to the adapter. Do not silently infer these from a shader hash.

## Verification

Run from the workspace, choosing a new artifact directory:

```powershell
.\tools\Test-ContactShadows.ps1 -OutputDirectory 'C:\Users\EQZITARA\Documents\ChatGPT\FF7 Rebirth mod\artifacts\contact-shadow-test-new'
```

Latest complete portable/adapter run: `artifacts/contact-shadows-port-20260831-v14/manifest.json`.

- Six strict FXC builds passed: SM5 pixel/compute stages at 8, 16 and 32 samples, with warnings treated as errors and IEEE-strict math.
- **34/34 tests executed successfully on D3D11 WARP**, Microsoft's software rasterizer. This runs the actual HLSL through a headless compute shader and reads back numerical results; it is not a separately implemented CPU approximation.
- Cases cover perspective interpolation, orthographic/perspective/subviewport thickness, clip exit, hit/miss/receiver rejection, regular and reversed depth, camera/viewport limits, subpixel rays, light exclusion, invalid samples, jitter, spatial occluder stripes, vertical UV orientation, occluders beyond the light, and late-hit falloff.
- The constant-valued fixture disables only FXC's redundant-finite-check warning 3577. The parameterized texture/sampler smoke shaders do not suppress warnings.

The 34 ray fixtures supply analytic device-depth values. An additional **56 adapter cases** execute `ContactShadowKernel_ps.hlsl` through a compute wrapper using actual D3D Texture2D/Texture1D resources and constant buffers, populated with synthetic data. They cover both depth slots (t4/t5), selected/all/wrong lights, disabled/partial strength, translated and rotated cameras, nonuniform projection, subviewports, invalid mappings, normal/radius rejection, and the bit-cast light index. The eight newest cases exercise lit receiver-plane rejection with blockers, no blockers, translation and rotation. The unused depth slot is deliberately bound to incorrect data. This is not captured game data or a hardware-cost test.

The first adapter test run (v8) failed in the test harness's nested include resolution, before execution. A parent-aware include handler fixed that; subsequent complete runs passed. Earlier artifacts are preserved rather than overwritten.

## Native integration and instruction checks

Generator: `tools/New-IntergradeContactShadowCandidate.ps1`. Latest validated candidate: `artifacts/contact-shadow-candidate-20260831-v6/candidate.json`. Validation receipt: `artifacts/contact-candidate-validation-20260831-v6/manifest.json`. Earlier v3/v4 remain preserved as the single/all-light live experiments.

- Five pinned native compute binaries are disassembled and patched, not rebuilt from incomplete decompiled HLSL. All original instruction tokens except the temporary-register declaration are preserved. Other DXBC sections are preserved; copied reflection/statistics metadata is not a trustworthy new instruction-cost report.
- The native light index is saved immediately after its packed-index mask, before BRDF code reuses the register. The production adapter is compiled once and its instructions are remapped into isolated temporaries. Early returns become breaks from a wrapper loop; returns inside an existing kernel loop are rejected by the generator.
- Visibility multiplies only the finished diffuse/specular contribution of that light, immediately before accumulation. Native attenuation, shadow maps, combined material/screen/capsule occlusion, BRDF calculations and diffuse-luminance output alpha remain in place.
- Destination masks are physical register lanes. The first offline candidate used abbreviated source masks that could permute xzw/yzw specular channels. That candidate is superseded and must not be installed. Corrected candidates use identity `.xyzw` sources with masked destinations; freshly disassembled instructions are checked explicitly.
- **185 execution cases** run the exact injected assembly block, separately from the rest of the renderer, with real synthetic resources across all five variants. Distinct RGBA sentinels verify both modified lanes and untouched lanes, including partial strength and disabled paths. Cases include zero contributions with nonzero unmasked lanes, each of the six contribution lanes individually, negative zero, negative contributions, and the new lit receiver-plane checks. Both zero cases require byte-exact preservation and visibility 1, proving the hit-producing fixture bypasses ray evaluation.
- **15 D3D11 WARP CreateComputeShader checks** pass: five originals, five complete patched shaders and five isolated injection fixtures. Complete patched binaries also reassemble byte-identically.
- OFF skips contribution writes but still adds register pressure/index snapshot/control checks. It is an unchanged-math path, not a zero-overhead original shader object. Whole-native-dispatch execution, driver/hardware cost and live image equivalence remain untested.

Reproduce the final injection checks with a freshly built matching test runner:

```powershell
.\tools\Test-IntergradeContactCandidate.ps1 -CandidateDirectory '.\artifacts\contact-shadow-candidate-20260831-v6' -TestBuildDirectory '.\artifacts\contact-shadows-port-20260831-v14' -PlaneAuditDirectory '.\artifacts\contact-plane-audit-20260831-v13' -OutputDirectory '<new directory under workspace artifacts>'
```

Control contract: IniParams row 31 is enabled / selected-light index / strength / ray length. Negative light index selects all. After the single-light experiment below, the next controlled test uses -1, not a preferred preset. No all-light performance claim is made. The kernel adds 13 temporaries plus three integration registers per variant, and can perform 16 depth samples per traced light/pixel. A new gate bypasses rays when all six native diffuse/specular contribution lanes compare equal to zero; it does not remove native AO or shadows. Material/hair exclusions and temporal jitter are not yet integrated.

## Traced binding contract

The existing frame log binds resource `0x0000027980873060` (hash `a394978d`) to CS cb1 at event 806 and VS cb0 at event 813. No intervening CS slot-1 rebinding occurs before the five surface-light dispatches. Geometry shader `f2f65b9971c21bde` adds view row 62 to world position, then combines forward rows 0..3. Its original binary and fresh FXC disassembly are preserved in `artifacts/contact-capture-preparation-20260830`; original SHA256 is `EFFFA6ACB56BDABB07FFBD6AEE0E13E448EC6DED00533378063B3CDC740A90A8`.

The adapter uses native inverse world reconstruction rows 40..43, linear-depth coefficients 57, pretranslation 62, allocation size/inverse 126, and bit-cast dispatch viewport bounds cb0[1]. Light position/inverse radius come from cb4[index]. The forward row-vector convention is traced from native geometry. These offsets now pass sampled numerical validation using the actual captured view and depth; see the live staging record below.

A receiver reprojection guard checks the reconstructed position against its original pixel (0.75-pixel tolerance) and linear depth (0.2% or 0.01-unit tolerance). Failed checks return full visibility. This tests the receiver, not every possible ray endpoint or every matrix coefficient, and must not be mistaken for proof that live bindings are correct.

## Why this is separate from native occlusion

The [surface-lighting study](surface-lighting-occlusion-study.md) found native material/screen occlusion and an additional analytical capsule-like occlusion producer. These are not to be removed wholesale to make the new feature visible. The new component traces toward a specific light through screen depth; its visual benefit must be demonstrated where native light/contact detail is insufficient.

Optional microshadow replacement is deferred, not called equivalent or impossible. The existing native occlusion makes it a lower-confidence improvement than our original assumption suggested, and the donor's optional Uncharted formula is disabled in its pinned local-light configuration.

## Remaining Remake integration work

1. Capture and sampled camera validation are complete. Light-50 contact rays produced no visible change; its diagnostic contribution cut produced angle-dependent illumination removal. The current task is a controlled all-contributing-local-light contact-ray comparison.
2. Check material/tile coverage and validate a focused runtime candidate with a reliable native-original comparison. Current F3/F9 behavior must not be assumed from earlier tests. Keep native occlusion and all original output contracts.
3. Ask for one useful contact/light comparison in motion, accept the user's clear report, and pause whenever their input is required. Check parser/compiler health and neutral-path image equality before evaluating the new effect.
4. Measure GPU cost, test another lighting situation and character materials, then keep/revise/skip based on actual benefit. The all-light test is experimental; routine use or a preferred preset is not yet justified.

Capture preparation: `tools/Prepare-IntergradeContactCapture.ps1` installed only `Mods/ContactShadowCapture.ini`, with receipt `artifacts/contact-capture-preparation-20260830/capture-preparation.json`. It contains scoped dump commands, no shader replacement, skipped draws, clears, new keys or continuous capture. The local 3Dmigoto source gates dump commands on active frame analysis. Existing F8 starts one frame only when hunting is enabled; existing Numpad0 toggles hunting. Expect a temporary capture stall and full-resolution texture files. Do not use F8 repeatedly while it is busy.

At preparation the game was not running. That preparation state is superseded by the completed capture and live staging below.

## Captured validation and first live staging, 2026-08-31 UTC

Capture: `FrameAnalysis-2026-08-30-211238` in the game Win64 directory. It contains all five variants, actual constant-buffer contents, depth/normal/material textures, tile lists and per-tile light records. Original shaders and offline candidates survived the reboot; the capture supplies runtime inputs, not replacement shader discovery.

`tools/analyze_intergrade_contact_capture.py` produced `artifacts/contact-capture-analysis-20260830-v2/analysis.json`. All 129,600 stride-8 sampled receivers pass the production mapping tolerances. Maximum pixel reprojection error is 0.008011 pixel; maximum relative linear-depth error is 0.001437. This is sampled FP32 analysis, not full GPU equivalence. Projection scale is 1.7320509 / 3.079202. The full cb4 files differ only outside the active 768-row native light layout; all active light rows agree across the variants.

The updated ranking mirrors native radial attenuation, source-radius denominator and spotlight attenuation from the original assembly, and excludes receivers inside the donor's 0.175-radius exclusion zone. It still omits IES, shadow maps, BRDF and native occlusion. Light 50 has 75,391 eligible sampled receivers and is nominated for the first test. The index is scene-local, not a stable portable light identity. No indirect dispatch counts were captured; tile membership alone does not prove executed coverage.

`tools/Stage-IntergradeContactShadows.ps1` staged five assembly payloads and reassembled every payload to the exact tested candidate binary. The first staging directory `...ContactShadows-live-v1` was offline only. The installed package is `artifacts/generated-runtime/FF7RemakeIntergradeContactShadows-live-v2`, with receipt `artifacts/installed-contact-shadows-overlay-v1.json` and backup `backups/GeneratedRuntimeOverlay/20260831-013538-331`.

- **Home** toggles the contact effect 0/1, initialized OFF; light 50, strength 1, ray length 100, 16 samples. This is an experiment, not a preferred preset.
- Page Down retains the author-image-adjustment toggle. The image-adjustment INI/shader, root `d3dx.ini`, and DLL are hash-verified unchanged. Existing Ctrl+Home hunting differs from unmodified Home and does not conflict.
- The temporary capture INI is now comment-only, with its original preserved in the backup. The new `Mods/ContactShadows.ini` owns the five hashes. No capture commands remain active.
- F9 is hold-to-original only while hunting is enabled, confirmed in local `Hunting.cpp`; do not describe it as a persistent toggle. Home OFF preserves native calculations but not native register cost. F3 is not part of this package.
- Initially installation was disk-only at log offset 138800, PID 8168. On 2026-08-31 at 01:52:10 UTC, `tools/Get-IntergradeContactShadowStatus.ps1` reports `passed-parser-and-five-native-asm-reloads`: Home key and all five overrides parsed, all five replacement assemblies loaded and shaders created, no detected errors, unchanged protected/payload hashes, game responding. Live visual quality and OFF-path image equality are not yet proven. Next comparison uses Home in the same test area; no further F10 is needed.
- No extra user capture is needed at this stage. Pause for the user. Do not mistake successful parser/creation checks for visible benefit or performance evidence.

Rollback uses `tools/Uninstall-UE4GeneratedRuntimeOverlay.ps1 -InstallManifestPath <workspace>/artifacts/installed-contact-shadows-overlay-v1.json` after verifying installed hashes. It removes the six added contact files and restores the prior capture-only INI from backup; reload is then required. It does not alter the author-image-adjustment overlay.

## First visual result and paused diagnostic, 2026-08-31 UTC

User reported **no change** with Home. Accept this result; do not ask for the same comparison again. The log confirms repeated `ue4fx_contact_enabled` transitions between 0 and 1 and all five successful native-assembly reloads. The current view's pixels are not proven by those logs.

To distinguish a ray failure from absent/occluded native contribution, `tools/Replay-IntergradeContactCapture.ps1` runs the actual production HLSL kernel on D3D11 WARP with the saved cb0/cb1/cb4, packed normal texture and depth. It does not attach to the game. Successful artifacts: `artifacts/contact-capture-replay-20260831-v3`; the first two builds failed before execution on missing SDK/header includes and are preserved. Ten replay runs cover OFF/ON for lights 50,38,54,20,52 at stride 8. All output values are finite within 0..1 and each OFF run is exactly 1 for all 129,600 receivers. Light 50's ON run changes 31,343 raw sampled receivers. Correlating with tile membership, native attenuation and donor exclusion gives 6,138 eligible shadowed receivers (`artifacts/contact-capture-analysis-20260831-replay`). This proves the captured kernel can find hits, **not** that the live native contribution changes. The wrapper does not execute native BRDF, IES or shadow-map logic; current game inputs may also differ from the saved frame.

Next diagnostic is a **temporary native contribution cut for light 50**, not a stronger contact-shadow preset. `tools/Stage-IntergradeContactLightCut.ps1` retains original shader instructions (except added temporary declarations) and zeros only that light's finished diffuse/specular lanes before accumulation when Home is ON. It bypasses all ray/receiver calculations to isolate the live selection/contribution path. Five diagnostic shader-creation checks pass; no complete native-dispatch execution or visual result is claimed.

Installed package: `artifacts/generated-runtime/FF7RemakeIntergradeContactLightCut-live-v2`. Receipt: `artifacts/installed-contact-light-cut-overlay-v1.json`. Backup: `backups/GeneratedRuntimeOverlay/20260831-020742-983`. Six files replace the five contact-ray assemblies and `Mods/ContactShadows.ini`. Previous contact-ray payloads are backed up. Protected image-adjustment shader/INI, DLL and root configuration remain unchanged. Temporary capture commands remain disabled.

The user returned and reloaded the cut diagnostic. Logs confirmed its key/overrides and all five assembly reloads, with the process responding and payload/protected hashes unchanged. User initially described lights flickering while moving the camera, then clarified **"it could be unchanged at most angles" / "think it just disables at angles"**. Record this as angle-dependent illumination removal. It is not proof of a flicker bug or of light-slot reassignment; these were hypotheses, not established causes. Accept the report without requesting the same toggle comparison again.

To restore the contact-ray stage, verify current cut hashes and uninstall **installed-contact-light-cut-overlay-v1.json** first, then reload. Do not uninstall the older contact-ray receipt while the cut overlay is installed, as those predecessor hashes intentionally differ. The cut must not become a released feature.

## All-contributing-local-light test staged, 2026-08-31 08:19 UTC

The above cut has now been replaced **on disk**, not yet confirmed reloaded. `tools/Stage-IntergradeContactAllLights.ps1` installed `artifacts/generated-runtime/FF7RemakeIntergradeContactAllLights-live-v1`; receipt `artifacts/installed-contact-all-lights-overlay-v1.json`, backup `backups/GeneratedRuntimeOverlay/20260831-081948-566`. Six files were backed up and replaced. The image adjustment, root INI, DLL, and comment-only capture INI were hash-verified unchanged.

The v4 candidate restores the actual author-derived contact rays, with Home default OFF, all local lights (`y31=-1`), strength 1, ray length 100 and 16 samples. Unlike the diagnostic, it does not unconditionally zero a selected light. It skips ray evaluation only when all six finished native contribution lanes compare equal to zero. The gate tests individual channels without summing (no cancellation), ignores unmasked register lanes, and treats both signs of zero as zero. No new temporary registers are needed beyond v3. Every original instruction token except the temporary declaration remains intact; all complete binaries round-trip identically and staged assembly reassembles to the tested binaries.

Offline checks: six strict compiles, 34 ray cases, 48 adapter cases, 165 exact-block cases and 15 shader-creation checks passed. Captured tile counts are min 1, median 3, p99 10, max 16; these are not measurements of surviving contributing lights or GPU cost. Enabling every local light may be substantially more expensive. Screen-space contact shadows can remain view-dependent and may overlap native shadows; benefit, hair/material quality, motion stability and performance are unproven.

**Next input / pause:** one F10 loads the new package OFF, then Home once enables the actual contact shadows. Look for contact darkening near feet/objects and its behavior while moving the camera; report noticeable slowdown or abrupt light loss. Home again disables the new effect. Do not describe F3 as a supported comparison here. No keys or mouse input were sent by the agent. `tools/Get-IntergradeContactShadowStatus.ps1` now defaults to this package and must confirm the new reload before interpreting a result.

Rollback order matters: verify current all-light hashes and uninstall `installed-contact-all-lights-overlay-v1.json` first (restores the temporary cut payloads), then verify/uninstall the cut receipt to recover v3 contact rays. Do not reload the intermediate cut unintentionally. Older receipts must not be applied over newer payloads. For unchanged native math without disk rollback, Home OFF is the current comparison; it is not zero-cost original shader objects.

## All-light live quality failure and isolated self-shadow regression

At 2026-08-31 08:25:53 UTC the status check confirmed the new all-light package's Home key/overrides and all five successful shader reloads, no detected errors, matching payload/protected hashes, and responding PID 8168. The user reports a visible but **unreliable** response, then specifically points out **bands on Cloud's left arm**. Three screenshots were supplied: `codex-clipboard-747cc3f9-c220-490a-8609-15f1e9eee980.png`, `codex-clipboard-b9f89836-2fc6-4393-924e-63a4baae18dc.png`, and `codex-clipboard-9d6c4f26-5fc4-41a4-aef9-ea923b499318.png` in the user's local Temp directory. Do not infer an exact A/B order or attribute animation differences to the shader. Accept the banding/motion report as a failed quality test, not a preferred effect or a missed subtle improvement.

A new independent headless test, `tools/Audit-ContactShadowPlanes.ps1`, executes the **unchanged production tracer** on a single analytic infinite plane, with every ray pointing into that plane's lit hemisphere. There is no separate occluder: correct visibility is 1. The fixture spans eight plane slopes, ten positive light/normal angular gaps, two receiver depths (100/1000), and exact versus 3840x2160 point-quantized depth sampling. The normal offset and direction offset move the origin away from the plane, so these rays cannot physically intersect it. They use donor settings and fixed midpoint jitter, like the current adapter.

Results: `artifacts/contact-plane-audit-20260831-v2/manifest.json` and `results.csv`. Execution completed with zero invalid outputs, but **46/160 exact-depth cases and 46/160 point-quantized cases produce false shadow hits**. This reproduces false self-shadowing independently of point-sampling quantization, model animation, live light selection, and game resource binding. It does not prove that every live arm band has this cause. The first audit build compiled the C++ runner but HLSL failed on FXC redundant finite-check warning 3577 for constant fixture matrices; only that fixture warning was suppressed for v2. Production finite guards were not changed.

The interval test compares a span of ray depths with a single sampled surface depth. On sloped surfaces at shallow light angles that span can overlap the receiver's own depth interval even when the physical ray remains above it. This is the next concrete failure to investigate before adding temporal noise or weakening effect strength. The previously passing 165 integration cases remain valid but did not exercise inclined, unobstructed receivers; they were not sufficient quality coverage.

No live file, production shader source, or donor source was changed during this diagnosis. No further screenshots or repeated toggles are needed to establish the reported defect. Keep the all-light package experimental; next work is an offline receiver/intersection correction that preserves real occluder hits, followed by reassembly/integration validation before another live test.

## Corrected tracer and mandatory software gate, 2026-08-31

The user explicitly requested software-renderer checks before receiving another candidate. Corrections were made only in the workspace. These are deliberate deviations from the donor, not claims that its original implementation behaved identically in Rebirth:

- Require ray penetration against depth at the matching UV, rather than accepting only overlap with the interval spanning different UVs.
- Reconstruct the sampled surface at its texel center. For a light above the receiver's tangent plane, reject samples on or below that plane. The adapter supplies verified ViewData[40..43] reconstruction and [62] translation plus point-sampling information.
- Refine a stepped-over front-to-back crossing with five bisections; still require a finite penetration within thickness. A discontinuity alone is not a hit.
- Apply falloff by progress along the world-space ray, accounting for frustum clipping, and include the visible endpoint in the last sample.

Expanded WARP audit: `artifacts/contact-plane-audit-20260831-v13/manifest.json`. Across 20,480 cases (slopes, light-angle gaps, receiver depths, exact/point-quantized depth, eight azimuths and four subpixel offsets), **10,240 unobstructed receivers have zero false hits; 10,112 visible box blockers have zero misses; 128 boxes beyond the visible ray exit have zero false hits**. The latter are deliberately expected unshadowed: an independent CPU ray/AABB/frustum oracle shows they begin beyond screen visibility. Boxes and planes are mathematically generated, not extracted animated character geometry. Earlier failed results are retained.

Native validation v6 uses portable v14 and this exact audit: six strict compiles, 34 analytic cases, 56 adapter-resource cases, 185 exact-block cases, 15 shader-creation checks and byte-identical complete-shader assembly roundtrips pass. Candidate v6 adds 24 temporaries to each original shader (including input/result/scratch), versus the older candidate's smaller footprint; live GPU cost is unknown.

Saved-resource replay: `artifacts/contact-capture-replay-20260831-v4/manifest.json`. The corrected production kernel executes with captured game depth, normals and cb0/cb1/cb4 for five lights, OFF/ON: 1,296,000 sampled results are finite/in range; all five OFF runs are exactly neutral. ON still finds occluders for every tested light. Counts are raw ray hits, not native light contribution, aesthetic quality or GPU performance. The wrapper does not execute the complete native tiled-light dispatch or reproduce BRDF/shadow-map/temporal/post-processing composition.

`tools/Assert-IntergradeContactSoftwareGate.ps1` checks the audit, replay readback, source/runner fingerprints and linkage to native validation. `Stage-IntergradeContactAllLights.ps1` now requires this gate before creating the corrected v2 package. Source changes invalidate evidence and require fresh runs. `artifacts/contact-software-gate-tests-20260831-v1/manifest.json` records seven passing gate tests: current evidence accepted; failed audit, stale source, lost blocker, missing replay, nonneutral OFF and NaN ON rejected. These tests mutate disposable copies only.

**Motion clarification:** this is a headless shader-execution harness using D3D11 WARP, not FF7 running its entire engine on the CPU. Separate subpixel view offsets are not a continuous animation/temporal-history test. The later synthetic sequence below adds moving camera/blocker coverage; it still does not execute FF7 animation or temporal history. Captured buffers are one static snapshot. Actual skin/hair, articulated models, engine history and final game composition still need live verification. Do not describe this software gate as a final engine-motion test or proof that Cloud's arm is fixed.

No new game files have been installed for this correction. Preserve the current receipt chain. A future controlled install must default Home OFF, preserve Page Down and protected files, and request one reload plus a focused motion observation only when ready; pause there for the user.

## Continuous synthetic motion, failures caught before deployment

`tools/Audit-ContactShadowMotion.ps1` builds a headless WARP test of the production tracer. The CPU independently generates point-sampled depth textures by intersecting camera rays with known planes, a sphere or a moving box. Four sequences each contain 96 consecutive camera poses with lateral/depth motion and yaw. A 32x16 grid tracks the same world-space receivers through each sequence; camera-hidden or unlit receivers are excluded from quality counts. The final pose exactly repeats the first to check deterministic output. Resolution is 1280x720, not the game's 4K capture. No whole-engine rendering, history buffer, articulated model or native tiled dispatch is reproduced.

Current 16-sample evidence: `artifacts/contact-motion-audit-20260831-16-v4/manifest.json`, `frames.csv`, `results.csv`, and `visibility.f32`. All 196,608 outputs were valid. The unobstructed plane, convex sphere, and perturbed/10-bit-quantized sphere normal sequences have zero false hits or large changes. The moving-box sequence has 43,855 active receiver samples, 189 false-hit classifications, 608 misses among 2,787 eligible visible blockers, and 920 consecutive-frame visibility changes over 0.5 with unchanged binary world occlusion. These raw classifications include thin/grazing boundaries and do not by themselves establish 920 engine-like flicker defects.

`tools/analyze_contact_motion_audit.py` checks nearest distance from the actual biased ray to the box, not just the unbiased oracle. `geometry-analysis.json` establishes 65 false-hit samples where the biased ray misses by more than one world unit, and 40 large lit/dark changes where both consecutive biased rays miss by more than one unit. One concrete case, frame 10 / receiver 467, has visibility 0.00000433403 despite a 2.93389-unit clearance, between neighboring frames with visibility 1. This is stronger evidence of a real synthetic false-shadow transition than a binary shadow boundary alone. One unit is a diagnostic category, not an invented live acceptance threshold.

The numerical helper `tools/inspect_contact_motion_case.py` traces representative cases. Frame 2 / receiver 192 reveals a thin grazing intersection skipped between samples: the ray sees background at one sample and is already in front of the box at the next. Other missed cases have meaningful thickness: after accounting for the biased ray, 24 recorded eligible misses have box chords over five units. Frame 10 / receiver 467 exposes a finite-depth interval accepting a distant surface-depth jump. This helper is diagnostic CPU math; WARP readback remains authoritative.

Increasing samples to 64 (`artifacts/contact-motion-audit-20260831-64-v3`) reduces eligible misses to 189 but increases false-hit classifications to 264, with 748 large stable-binary-occlusion changes. It is not a fix, not a chosen setting, and provides no live GPU timing. The first 64-sample build failed on a missing standard-library include and was preserved.

### Rejected stricter surface-crossing experiment

The v5 motion experiment required matching-UV upper thickness, near-surface direct hits, and refinement in both crossing directions. It reduced false-hit classifications to 1 but increased eligible misses to 1,015. It also failed four existing analytic cases (UV stripe, offset viewport stripe, vertical UV flip, late-hit falloff) and lost 2,221/5,056 exact-depth plus 2,267/5,056 quantized visible box blockers in the expanded static audit. This is not an acceptable improvement.

Evidence: `artifacts/contact-motion-audit-20260831-16-v5`, `artifacts/contact-shadows-port-20260831-motion-experiment-v15/warp-tests.log`, and `artifacts/contact-plane-audit-20260831-motion-experiment-v14`. The experimental source is preserved as `ContactShadows-rejected.hlsl` in the v5 directory. Only that experiment's source edits were reversed with a patch. The restored production source hash is `6438901B48369DDCF1B837E17A0554BFA7FA6883F7D5D1871433E8B5C371A257`, matching candidate v6 and motion v4. The predecessor source is also backed up under `backups/ContactMotion/20260831-before-surface-crossing`.

`Assert-IntergradeContactMotionGate.ps1` is now mandatory in the all-light stager, in addition to the prior software gate. A dry run was verified to reject this current source's failing v4 motion evidence before creating a package. `FF7RemakeIntergradeContactAllLights-live-v2` does not exist. Existing static gate tests remain useful but cannot authorize deployment alone. Do not relax the motion expectations merely to package a build; distinguish genuine boundary ambiguity from wider false transitions with independent geometry evidence.

Next offline work: preserve real blocker coverage while addressing discontinuity/interval acceptance and skipped thin intersections; evaluate each change against both static and continuous tests. Do not add sample count, noise or history smoothing as an unexplained cure, and do not request another live comparison yet. The user is not needed for the current diagnosis.
