# FF7 Remake Intergrade lighting checkpoint — 2026-09-04

## Safety state

No live game, `F:/` install, process, key binding, or foreground window was changed during this offline pass. F10 remains shader reload; F2 remains the indirect-light test toggle; Page Up and Page Down retain the established foreground-test/master-toggle contract.

## Contact-shadow automatic family

The accepted family is reproducible and fail-closed:

- exactly five of 184 captured shaders are accepted;
- the split remains BaseT5 `3`, BaseT4 `1`, FrustumT4 `1`;
- the regenerated `ContactShadowFamily.ini` is byte-identical to the accepted artifact (`F86A81DEE319C6A6E98933D4AC99C0477B6E5D8B43E6F7D29272FDDA476B5478`);
- raw body regex alone is not a safe oracle: the two T4 native bodies structurally overlap;
- exact instruction-count and binding guards disambiguate them (`631` versus `478` instructions);
- stale-manifest and deliberately widened-range mutations are rejected.

Primary evidence:

- `artifacts/analysis/intergrade-accepted-contact-family-validation-20260904.json`
- `artifacts/accepted-contact-family-rebuild-20260904-v1`
- `artifacts/analysis/intergrade-accepted-contact-family-guard-rejection-20260904.json`

The old WARP/software evidence is valid only for its archived source snapshot. The current experimental geometric tracer has a different source hash and cannot inherit that old pass result. This does not invalidate the accepted five-shader assembly family, which is generated from hash-pinned first-working shader checkpoints.

## Indirect-light result and angle dependence

The late-scene pack remains the first visually confirmed, non-feedback indirect-light foundation. Its source is current-frame HDR scene radiance; it is not bloom injection.

The observed angle-dependent beacon response has two separate mechanisms:

1. A visible small source can be missed because the half-resolution trace uses four pixel-hash-rotated directions. Camera movement changes the sampling phase even while the beacon remains visible.
2. An off-screen or occluded source cannot be sampled because the trace reads only current screen-space scene color and stops at the viewport edge.

The prepared c473 pre-temporal pack addresses the first problem partially by feeding `native scene + current GI` into Remake's native temporal resolve while leaving native history and motion inputs untouched. It cannot recover a source absent from screen space. It is compiled and offline-validated but not installed.

Evidence:

- `artifacts/analysis/intergrade-ssgi-angle-dependence-20260904.json`
- `artifacts/agent2-r3d-ssgi-late-scene-pack`
- `artifacts/agent2-r3d-ssgi-pre-temporal-pack`

If c473 still misses a visible beacon, the next controlled candidate should enlarge sampling coverage before the trace (depth-aware source footprint or more stratified slices), not raise the final strength. If only off-screen sources fail, the next architecture is a separately validated GI-only reprojection cache or native light-list/probe source. A composed scene-plus-GI target must never be fed back as source radiance.

## Remaining light coverage

Directional coverage is now separated correctly:

- `aadc1c2374853914` is the one verified directional cascade shadow projection/filter pass;
- it reconstructs receivers and filters a Texture2DArray cascade map into packed shadow factors;
- it is not the later directional surface-light evaluator;
- five partial cascade near matches remain rejected;
- the actual sun/directional-light consumer remains unresolved and must be runtime-owned outdoors before modification.

Evidence: `artifacts/analysis/intergrade-directional-light-coverage-20260904.json`.

`adb544f9a11d6c7e` is a high-confidence unshadowed tiled local-light diffuse evaluator candidate:

- it is the only shader in the retained compute census with its exact 16x16, 256-light-index, four-texture tiled-light skeleton;
- it reconstructs receiver position/normal, evaluates position/radius attenuation and Lambert diffuse, reads prior lighting, and writes the lighting target;
- it declares no shadow-array/contact input;
- the original Helix package independently filed the same hash under its `Lights2 / Clipping CS 3` family;
- it did not execute in the retained red-beacon scene, so it remains runtime-unowned and unpatched.

Evidence: `artifacts/analysis/intergrade-unshadowed-local-light-coverage-20260904.json`.

## Next live order

1. With the user awake, preflight then test the already-built c473 pre-temporal pack. F2=0 must be exact native parity; F2=1 gets fixed-camera, slow orbit, fast pan, camera cut, character, UI, FOV/resolution, and timing checks.
2. If a visible beacon still toggles, isolate sampling coverage. If only an off-screen beacon fails, move to a GI-only history/probe design.
3. Capture outdoors: trace the verified cascade-mask output into the later directional-light consumer, then runtime-own that consumer.
4. Find a scene that dispatches `adb544f9a11d6c7e`; isolate it before adding any automatic transform.
5. Capture a visibly patterned profile/IES light and record its native flag/index activation.
6. Only after those gates, promote remaining contact/falloff behavior across the guarded five-shader family.

All fifteen current offline regressions pass after these additions.
