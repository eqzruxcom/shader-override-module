# Remake-first priorities

Research date: 2026-08-30. Target: Final Fantasy VII Remake Intergrade, DX11/3Dmigoto, SDR. This document supersedes the implementation order in `port-backlog.md`; that file remains a historical capability inventory.

Implementation direction updated 2026-08-31: reuse the actual pinned Rebirth shader functions before writing new effect algorithms. Write Remake resource/input glue around them, preserve attribution, and explicitly track any missing donor caller features. SSRT3 and Skyrim Community Shaders are reference leads parked for later, not the next implementation target. See [current donor integration](rebirth-contact-source-reuse.md).

## Decision

Port selected lighting techniques from frostbone25/David Matos, then investigate Remake-specific image-stability issues. Do not treat reproducing the entire Rebirth preset as the objective. A useful hook, a visible change, and a visual improvement are three different milestones.

The order below is a priority order for investigation and implementation, not a claim that Remake lacks every listed feature. Skip an item when the original already does the job or its cost/artifacts outweigh the benefit. No need to manufacture a visible difference to justify keeping it.

## Why Remake needs a different plan

Square Enix describes Intergrade improvements to rough-surface SSR, reflection/fog handling, shadow sampling, and custom SSAO denoising. Its renderer already has substantial custom work. The interview concerns the PS5 Intergrade development: it is architectural evidence, not proof that every current PC permutation is identical. Our captured shader/resource chain remains authoritative for this executable. [Square Enix Intergrade interview](https://www.unrealengine.com/developer-interviews/how-square-enix-impressively-optimized-final-fantasy-vii-remake-intergrade-for-next-gen?lang=en-US)

The donor author himself uses Remake as a favorable comparison when discussing Rebirth's gameplay lighting. That supports transferring useful techniques selectively; it does not establish that Remake needs Rebirth's lighting corrections. [Author's analysis](https://frostbone25.github.io/p/ff7-rebirth-contact-shadows/)

The local donor source reviewed is `reference/ShaderInjector`, commit `bab25809b375f028b7c0fb603d804426f38c9b8e`. Its active settings and code, not screenshots alone, inform the candidate list. In particular, camera-attached lighting, probe-specific tweaks, aggressive SSR weighting, and a preferred tone curve are not neutral engine fixes. Preserve attribution/license requirements when porting individual algorithms.

## Phase A: author's techniques, in this order

| Rank | Candidate | Remake purpose and implementation boundary | Keep only if |
|---:|---|---|---|
| 1 | Microshadows | Evaluate fine material self-occlusion in a real direct-light pass. Portable SM5 functions already exist in `src/Effects/Lighting/MicroShadows.hlsl`; the Remake light/material bindings are not verified yet. Check for an equivalent native term before adding anything. | Small surface features gain plausible shading without dirty skin, black hair, or double-applied AO. The disabled path matches the original. |
| 2 | Contact shadows | Supplement demonstrably missing contact detail, starting with a useful local point/spot light in the current industrial scene, then directional lighting in a suitable scene. Port the ray test, not the donor's whole lighting shader. | Detail follows the actual light and geometry, remains stable in motion, and does not create silhouette halos or excessive GPU cost. |
| 3 | Selective specular occlusion | Investigate reflection leakage only where reproduced at normal intensity. Keep native material response, probe fallback, and SSR confidence intact; scope any correction to the affected contribution. | Reflections are better grounded without flattening wet floors/metals, blackening rough materials, or changing unrelated skin/hair. |
| 4 | Bloom, then optional image/tone changes | Separate lamp bloom from volumetric light haze. Evaluate the donor's bloom technique independently before considering its color look. Retain Remake's native grading by default. | Highlight detail improves without haze loss, grey shadows, HUD changes, or unintended clipping. Tone-curve alternatives require correct color-domain/LUT handling and a user preference, not just a working toggle. |
| 5 | Mild sharpening | An optional finishing pass after temporal resolve, with verified render/output dimensions. Do not use it as a substitute for fixing temporal instability. | Useful detail improves at normal viewing distance without bright outlines, crawling hair/fences, or HUD sharpening. Otherwise leave it off. |

This is not five guaranteed live tests. Each candidate first needs an offline integration check; an unsuitable one can be skipped without another user keypress cycle.

Contact shadows only see the available screen depth, so missing off-screen occluders and thin geometry remain limitations. Start with short rays and conservative thickness rather than applying a blanket shadow to every light. [Epic contact-shadow documentation](https://dev.epicgames.com/documentation/en-us/unreal-engine/contact-shadows?application_version=4.27)

Specular-occlusion caution: a weak direct-light shadow mask does not by itself mean indirect reflections should be dark. The donor's artistic heuristic needs separate evaluation, not universal adoption. The current scene's 0-to-100% SSR comparison was inconclusive; the amplified probe is evidence of coverage only. See the local source `ModifiedShaders/Includes/ComputeShaderPass_ReflectionEnvironment.hlsl` and our historical SSR evidence in `port-backlog.md`.

### Author features deferred rather than copied automatically

- Experimental SSGI/replacement AO and auto-exposure: later research, not prerequisites. The donor documents noise/flicker risks; additional bounce light must also coexist correctly with Remake's existing lighting. [Pinned donor configuration](https://github.com/frostbone25/ShaderInjector/blob/bab25809b375f028b7c0fb603d804426f38c9b8e/ConfigurationGuide.md)
- Wholesale BRDF, probe, camera-light, and reflection-direction replacement: Rebirth-specific assumptions need independent Remake evidence. Keep native behavior unless a concrete defect is demonstrated.
- GT7 tone mapping: retain the offline candidate, but do not install it next. The inverse-curve/input-scale assumptions are not validated for the active Remake LUT branch. A successful compile is insufficient.
- Fog removal: retain the existing control as an optional preference; removing atmosphere is not a general quality improvement.
- Water/ocean: no demonstrated need in the current scene; evaluate later only against a specific material problem.

The author's troubleshooting notes also acknowledge microshadow overdarkening. Low arithmetic cost is not a guarantee of visual correctness. [Pinned donor troubleshooting](https://github.com/frostbone25/ShaderInjector/blob/bab25809b375f028b7c0fb603d804426f38c9b8e/Solutions.md)

## Phase B: Remake-specific exploration after the selected ports

These are ranked research candidates, not five confirmed defects on this installation. Their order reflects likely value, our observations, and existing implementations.

### 1. Motion clarity: temporal AA, hair/dithering, and resolution changes

Compare moving hair, fences, fine specular detail, and camera pans. First distinguish temporal blur/ghosting from dithering, ordinary motion blur, and reduced internal resolution. A single still frame cannot settle this.

There is already a Remake-specific DX11 Luma mod offering DLSS/FSR upscaling and experimental GTAO, plus bloom/vignette controls. It is the first external implementation to evaluate as an isolated benchmark, not a reason to build another upscaler immediately. Its changelog also discusses dithering and resolution-related fixes; these may address its own integration and must not be relabeled as proven vanilla bugs. [Luma author page](https://www.nexusmods.com/finalfantasy7remake/mods/1974)

Possible work: targeted temporal/dither integration, or compatibility with an existing solution. Success means better motion detail with acceptable ghosting, not merely a sharper paused frame. Upscaling cannot recreate genuinely absent texture detail.

### 2. AO stability around moving characters

User evidence: a nearby-character outline that changes with the AO test, most apparent in motion. The mapped native temporal pass gives us a real starting point. This does not yet identify whether the unwanted effect is an AO radius/depth issue, bad history rejection, or a deliberate contact shadow.

Possible work: inspect temporal weights, depth/normal rejection, denoising, and radius before replacing AO. The existing strength slider is not a quality fix. Preserve the packed metadata and downstream contract unless deliberately replacing the entire chain.

The reviewed Luma adapter demonstrates a substantially larger alternative: depth prefilter, GTAO evaluation, and denoising with extra working textures, replacing/skipping native AO stages. Its constant-buffer assumptions are reference leads, not verified bindings for our hashes. [Pinned Remake adapter source](https://github.com/Filoppi/Luma-Framework/blob/efce453dd4a1a25a15c973b0fcaca7e3dd60f56f/Source/Games/Final%20Fantasy%20VII%20Remake/main.cpp)

Success means less unwanted outlining/trailing without removing useful crevice/contact shading. Compare any replacement against native AO, not only against AO disabled. XeGTAO itself has screen-depth limitations and needs multiple passes; it is not a one-line shader swap. [XeGTAO implementation](https://github.com/GameTechDev/XeGTAO)

### 3. Reflection stability at screen edges and in motion

Find a reproducible problem with untouched/neutral rendering at normal intensity before changing anything. The extreme white edge glow seen under our amplified probe is not evidence of a stock-game defect.

Possible work: ray validity, edge confidence/fade, history rejection, and transition to environment captures. Retain the native reflection/fog relationship rather than adding fog twice. Screen-space data cannot supply hidden geometry; fixing an edge transition is not equivalent to adding ray tracing. [Epic SSR overview](https://dev.epicgames.com/documentation/en-us/unreal-engine/1.5---screenspace--reflections?application_version=4.27)

Success means stable wet-ground/metal reflections across camera angles, without edge flashes or a discontinuous fallback. Normal-range validation is still missing in our current view, so no automatic promotion of the existing SSR intensity control.

### 4. Native shadow and lighting defects in specific scenes

After the imported micro/contact techniques, investigate any remaining shadow detachment, unstable sampling, abrupt transitions, or local lighting leaks. These are conditional checks, not confirmed current problems. Start with native bias/filtering or material/probe interpretation; do not globally darken the image.

Separate shader-accessible defects from baked lightmap/probe placement or low-resolution asset limitations. The latter may require engine or asset work outside this shader adapter. Do not promise that an injection can recover missing source information.

Success means correcting a named scene defect while preserving nearby materials, fog, cutscene faces, and the intended lighting contrast. If the original behaves correctly, skip this item.

### 5. Frame pacing, streaming, and performance work

User clarification: the current F10 pause is an injector/DLL shader-reload concern, not a request to alter normal game behavior. No normal-game stutter defect has been established here. The broader gameplay investigations below remain conditional, deferred research, not the present work item.

Profiling is a gate throughout both phases; this rank is for separate optimization work afterward. Measure steady-state GPU cost and frame-time spikes, distinguishing traversal/streaming, first-use compilation, CPU limits, and our own F10 reload cost. A crash needs captured diagnostics, not an assumed shader-stutter cause.

Existing options are not interchangeable. FFVIIHook can expose configuration/console access, but each CVar needs verification on this custom build. The newer asynchronous compilation mod targets DX12 PSOs, not our DX11 path. Older streaming bundles change many parameters and may include a different graphics proxy; do not install them over 3Dmigoto as a generic fix. [FFVIIHook author page](https://www.nexusmods.com/finalfantasy7remake/mods/74), [DX12 async-compilation author page](https://www.nexusmods.com/finalfantasy7remake/mods/2130), [streaming-tweak bundle](https://www.nexusmods.com/finalfantasy7remake/mods/139)

Success means a measured improvement on repeatable gameplay traversal without worse texture arrival, memory pressure, or image quality. No performance estimate from the donor's GPU/game is treated as our benchmark.

## Existing implementations and compatibility

Luma was researched, not installed. It overlaps AO/post-processing resources and shader replacement responsibilities. Before trying it, plan an isolated reversible baseline, check DLL/proxy ordering, overlapping passes and keys, the exact executable, and the supported API. Compatibility with our current 3Dmigoto overlay has not been established.

Code reuse is a separate decision from testing a released mod. The framework has a custom license, and individual sources/dependencies and packaged-mod permissions need review before redistribution. Do not describe the whole package as unrestricted MIT. [Luma license](https://github.com/Filoppi/Luma-Framework/blob/efce453dd4a1a25a15c973b0fcaca7e3dd60f56f/LICENSE.md)

HDR remains deferred until the end and only if the user wants it. Cross-game portability remains the long-term goal, after a feature earns its place in Remake. No universal UE4 compatibility claim follows from one working game.

## Immediate next work and testing rules

Latest result, 2026-08-31: the directly extracted Rebirth ray/noise/parity/AVG now has a shared SM5 native integration, with an audited uniform outer-loop boundary. Five variants assemble and pass 1,200 full-group cases / 307,200 lane results. Raw/recomputed captured replays also completed. General compiled size drops from 214,008 bytes (recomputed) to 67,724 (shared), not a measured performance result. **Deployment remains unapproved.** Prior matched motion still shows fewer abrupt changes but more false/missed shadows; native phase resets, helper coverage and engine TAA are unverified. Next is repeated-light storage reuse and shared captured replay, then quality/cost validation—not another live confirmation cycle yet. No new game files are installed; arm banding is not proven fixed. See [shared integration](rebirth-contact-shared-integration.md) and [reference quality evidence](rebirth-contact-reconstruction.md).

Retained progress: [the surface-lighting study](surface-lighting-occlusion-study.md) identified five tiled compute variants with native combined occlusion, including an analytical capsule-like source. Optional microshadow replacement remains deferred. Captured data validates 129,600 sampled camera mappings; that old result establishes the reconstruction contract, not the new donor ray output. The first light-50 contact test loaded but the user saw no change; a temporary native contribution cut then produced angle-dependent illumination removal. That is not proof of a flicker bug or changing light slots. The [contact-ray integration](contact-shadow-port.md) retains native AO/shadows and the zero-native-contribution bypass. Existing image adjustment, main config, DLL and disabled capture commands remain unchanged. No reload is requested; live benefit, motion quality and GPU cost are unverified.

1. Audit the existing capture for an actual surface-lighting pass and verify material AO, normal, light direction/attenuation, view reconstruction, and current native micro-occlusion. Fog-light injection is not the surface-lighting hook.
2. Continue the contact-ray adapter after the native-occlusion audit: verify projection/viewport and per-light inputs, then prepare one minimal candidate offline. Revisit optional microshadows only for a concrete benefit. If evidence is missing, request only the necessary capture and pause when the user is needed.
3. Run the mandatory software-renderer gate before handing over a candidate: original-preserving disabled path, real blocker retention, angled receivers, matching-source captured-resource replay and exact assembly integration. State missing motion/engine coverage clearly. Compile success alone is insufficient. Keep a documented baseline; do not assume an old F3/F9 assignment still provides originals.
4. Make one meaningful comparison in a suitable view. Accept the user's clear motion/visual report; request screenshots or a short clip only for ambiguity. Use before/after captures when helpful, without demanding repeated confirmations of a settled observation.
5. Keep, revise for a specific reason, or skip the effect. Check motion, menus/cutscenes, a second lighting situation, and GPU cost before promoting a preferred preset. Material/temporal effects need character inspection; unrelated animation is not effect evidence.

## State preserved during this review

The currently installed author image-adjustment comparison remains unchanged: `41f1bf8b79d01319`, exposure -0.45 EV / gamma 1.15, original native tone mapping retained. The user confirmed a tonal difference, not a preferred result. Page Down is its comparison control; the selected state was not re-read during research. This is not a statement that all historical generated-runtime keys are active now. See [live observation](author-image-adjustments-observation.md).

The GT7 candidate remains offline in `artifacts/generated-runtime/FF7RemakeIntergradeAuthorGT7-offline-v2`. No new shader, runtime configuration, external mod, driver setting, or game setting was installed by this research pass. Only planning documentation was changed.
