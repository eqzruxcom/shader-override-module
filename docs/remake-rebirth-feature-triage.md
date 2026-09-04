# FF7 Remake / Rebirth lighting feature triage

Research date: 2026-09-01

## Visual target

The target is **localized, colored indirect illumination**, not a global ambient lift.
Bright practical lights should visibly spill their color onto nearby walls, floors, and
characters, then fall off with distance while unlit regions remain dark. The lower image
in `codex-clipboard-c6447aae-c956-4194-83e6-1d910b3dcedd.png` is the reference: a warm
light energizes the surrounding surfaces and the character instead of reading as a bright
bulb with a small direct-light patch.

Contact shadows and AO are separate from this target. They restore grounding and local
occlusion after indirect light is added; they cannot create the colored bounce themselves.

Remake's baked/light-probe indirect lighting is not a quality target. Keep it only as an
optional baseline or off-screen fallback, because a screen-space replacement cannot see
geometry or emitters outside the frame.

## Decisions

| Feature | Decision | Reason |
|---|---|---|
| Native shadow maps | Keep | Screen-space contact shadows cannot replace off-screen or hidden casters. |
| Rebirth contact shadows | Keep and complete coverage | They visibly improve grounding. Preserve the accepted left-edge frustum fade. Discover and verify local, IES, and directional families instead of assuming five captured compute variants are complete. |
| Native material AO / capsule occlusion | Keep | Remake's local-light shaders already consume several occlusion terms. Removing them would discard information unavailable to a screen-space pass. |
| Rebirth direct-light AO/microshadow multiplication | Do not port wholesale | It is likely to double-darken Remake because those occlusion terms already participate in direct lighting. Test only as a separate, family-complete option if a specific deficit remains. |
| Rebirth one-ray checkerboard SSGI | Do not use as the final GI | It is noisy, resolution-dependent, and relies on the game's temporal upscaler instead of dedicated filtering. This matches the donor author's documented limitations and the worse behavior observed at 1080p. |
| Horizon/finite-thickness SSGI | Preferred GI direction | Better matches the colored local-spill target. Start with the already-built R3D horizon candidate, then compare it with an SSRT3-style implementation using temporal accumulation, spatial denoising, and native indirect as off-screen fallback. |
| XeGTAO | Preferred universal AO baseline | MIT-licensed, HLSL/SM5-friendly, explicitly separates depth prefilter, AO evaluation, and denoise. It is more portable and easier to validate than treating the donor's SSGI AO as the universal solution. |
| FidelityFX CACAO | Defer as a second AO option | Strong open-source AO, but more integration complexity than XeGTAO. Evaluate only if XeGTAO leaves a measurable quality or performance gap. |
| Community Shaders screen-space shadows | Algorithm/architecture reference | Its modular runtime and resolution-aware screen-space shadow pass are useful precedents, but the implementation is Skyrim-specific and GPL-3. Do not copy it wholesale into a permissive universal core. |
| Oren-Nayar diffuse | Optional, later | It changes the material response and art direction; it does not supply missing indirect light. Test only after shadow and GI coverage is stable. |
| Character dominant-direction shaping | Optional, later | May improve faces/characters, but is a broad Rebirth-specific probe-lighting correction rather than a universal GI solution. |
| Rebirth auto exposure | Skip for the baseline | The donor documents flicker and performance cost. It does not create stable local bounce. |
| Rebirth rough SSR replacement | Skip for the baseline | Intergrade already contains bespoke rough-surface SSR improvements. The donor configuration is low-ray and can be noisy. |
| Bloom replacement | Skip for the baseline | Subjective post-processing; Intergrade's bloom was deliberately retuned. It cannot fix missing indirect light. |
| Fog density replacement | Skip for the baseline | Remake uses custom PBR volumetric fog. A simple density multiplier is not a universal lighting upgrade. |
| Tonemapper / sharpening / color grading | Separate optional pack | These change image presentation and can conceal lighting defects. Keep them out of the lighting core. |
| Water/ocean changes | Skip | Game- and material-specific, unrelated to the current Remake lighting goal. |

## Evidence from the current Remake capture

- The current regional cache is incomplete: 184 original shader identities are not evidence
  of complete game coverage.
- Five tiled local-light compute variants are proven. Directional and IES coverage is not yet
  proven in the current indoor capture.
- The native AO path already has a temporal producer, three spatial filters, a compositor,
  and consumers in local-light and reflection passes.
- The local-light compute family already combines material AO, screen AO, capsule/other
  occlusion, and native shadow maps. This is why indiscriminate microshadow multiplication
  is risky.
- The donor SSGI configuration uses one ray, sixteen ray-march steps, and checkerboard
  reconstruction. Pixel-sized offsets become proportionally coarser at 1080p than 4K,
  consistent with the observed resolution sensitivity.

Local supporting documents:

- `docs/shader-coverage-audit-2026-08-31.md`
- `docs/surface-lighting-occlusion-study.md`
- `docs/shader-injector-v2.2.1-preset-diff.md`
- `artifacts/analysis/remake-ao-architecture-map.json`
- `artifacts/analysis/agent2-r3d-ssgi-sampling-semantics.json`

## Implementation order

1. Freeze the currently accepted contact-shadow/frustum/clothing state as the rollback point.
2. Finish shader-family coverage and instrumentation: local variants first, then capture and
   prove IES and directional passes in appropriate scenes.
3. Do not stack new AO yet. Run isolated comparisons between native AO, XeGTAO, and the
   existing R3D horizon candidate.
4. Prototype colored horizon SSGI with a dedicated temporal/spatial denoise path. Use native
   probe/baked indirect only as an optional or off-screen fallback.
5. Validate at both 1920x1080 and 3840x2160, including motion, disocclusion, screen edges,
   thin geometry, and bright colored practical lights.
6. Only after AO/GI is stable, evaluate optional Oren-Nayar and character-light shaping.
7. Keep exposure, SSR replacement, bloom, fog, water, tonemapping, and sharpening outside
   the baseline lighting package.

## Primary references

- [Square Enix: Remake Intergrade rendering upgrades](https://www.unrealengine.com/developer-interviews/how-square-enix-impressively-optimized-final-fantasy-vii-remake-intergrade-for-next-gen?lang=en-gb)
- [Square Enix: Remake's custom UE4 lighting/rendering work](https://www.unrealengine.com/developer-interviews/how-square-enix-leveraged-unreal-engine-to-modernize-final-fantasy-vii-remake?lang=en-US)
- [Rebirth Shader Injector configuration guide](https://github.com/frostbone25/ShaderInjector/blob/main/ConfigurationGuide.md)
- [Rebirth contact-shadow implementation and limitations](https://frostbone25.github.io/p/ff7-rebirth-contact-shadows/)
- [XeGTAO](https://github.com/GameTechDev/XeGTAO)
- [FidelityFX CACAO](https://github.com/GPUOpen-Effects/FidelityFX-CACAO)
- [SSRT3](https://github.com/cdrinmatane/SSRT3)
- [Skyrim Community Shaders](https://github.com/community-shaders/skyrim-community-shaders)
