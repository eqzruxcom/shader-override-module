# Source-preserving Rebirth contact-shadow port

Updated 2026-08-31. Target remains **Remake Intergrade DX11**, not a switch to modding Rebirth. User direction: use existing Rebirth implementation code first; do not build another clean-room effect. SSRT3 and Skyrim Community Shaders are parked.

Latest step: a source-preserving shared-ray SM5 prototype now assembles into all five native variants. The common outer-loop boundary is audited; 1,200 full-group cases / 307,200 lane results match donor recomputation. This reduces redundant ray work, not the known quality tradeoff. **Not ready for installation.** See [shared native integration and remaining checks](rebirth-contact-shared-integration.md), and [reconstruction/motion/capture evidence](rebirth-contact-reconstruction.md). Earlier raw-stage artifacts below are historical evidence, not matching-source approval for the new prototype.

## Source boundary

Donor: David Matos/frostbone25 [ShaderInjector](https://github.com/frostbone25/ShaderInjector/tree/bab25809b375f028b7c0fb603d804426f38c9b8e), pinned commit `bab25809b375f028b7c0fb603d804426f38c9b8e`. Local donor checkout is clean. MIT copyright and permission text is retained.

- `src/ThirdParty/ShaderInjector/RebirthContactRay.hlsl`: verbatim ray section after LF normalization, except one explicit substitution of the Rebirth depth texture/sampler access with `Redx11ContactSampleDeviceDepth(uv)`.
- `RebirthContactNoise.hlsl`: unchanged two-argument interleaved-gradient-noise function from `LibraryRandom.hlsl`.
- `RebirthContactReconstruction.hlsl`: unchanged donor parity and AVG statements, with explicit scalar lane parameters replacing SM6 quad-access plumbing; statement provenance is recorded.
- `provenance.json`: full source/section hashes, pinned feature switches, exactly enumerated substitution and generated-file hashes. `tools/import_rebirth_contact_source.py` verifies extraction against pinned git objects and rejects changed working donor files. It emits an apply_patch patch only with `--emit-patch`; verification does not write files.
- `src/Effects/Lighting/RebirthContactShadows.hlsl`: compatibility structs/macros, Remake view/settings mapping and receiver-viewport preflight. No geometric-fit or new intersection algorithm. The donor's own improved-thickness/falloff logic, loops and hair branch remain in the extracted source.
- `ContactShadowCommon.hlsl`: shared input structs/settings and helper routines. Shared helper unit cases are not proof of equivalent donor internals.
- `ContactShadows.hlsl`: the old experimental geometric tracer, deliberately separate. No new runtime package is installed from either path.

## Provisional Remake caller versus donor caller

| Feature | Current source-preserving adapter | Remaining work |
|---|---|---|
| Position/depth/normal/light | Uses traced Remake bindings and reconstruction guard; raw/recomputed captured-resource replays completed. | Shared-path captured replay and native motion validation are still required. |
| Ray/default controls | Donor 16 samples, improved thickness, bias/exclusion/falloff; row 31 remains strength/ray control. | Defaults are not a validated Remake quality preset. |
| Sampling noise | Actual donor IGN evaluated at pixel center using integer bits from native `cb1[139].w`, matching native PS noise use. | One captured frame corroborates the layout; live progression/reset behavior still needs observation. This is a view-state sampling index, not a claimed unbounded application frame counter. |
| Hair | Native `t2.w` is decoded as `uint(alpha*255+.5)&15`; ID 7 selects the unchanged donor hair branch and bias 1.5. | Native strand-shading structure corroborates ID 7; a visual material-mask check is still outstanding. |
| Checkerboard/quad reconstruction | `SharedQuad` shares selected rays at the audited common native boundary; `RecomputeQuad` remains its barrier-free reference; default `Raw` is unchanged. | Consecutive-light storage reuse, shared captured replay, native phase resets, raster/helper coverage and GPU cost remain unverified. |
| Viewport | Receiver must project within the supplied viewport; native point-depth callback clamps sampling to viewport edges. | Donor ray still assumes normalized full-allocation UVs for clipping and allocation-based pixel footprint. Cropped/dynamic viewports need explicit validation/mapping; shared-helper subviewport tests do not prove this correct. |
| Composition | Multiplies native finished diffuse/specular lanes; BRDF, shadows/AO and output alpha retained. Shared mode preserves zero contributions but their threads still participate in ray sharing/barriers. | No full tiled native dispatch, visual equivalence or GPU timing claim. |

The shader wrapper is opt-in with `REDX11_CONTACT_USE_REBIRTH_SOURCE`, or the tools' `-Implementation Rebirth`. Tool defaults remain Experimental for historical workflows. Production staging has **not** been switched to the donor build, and no quality gate was relaxed.

## Evidence

| Artifact/check | Result and meaning |
|---|---|
| Source extraction checker | Pass: one resource substitution; ray section otherwise unchanged; noise function unchanged. |
| `artifacts/rebirth-contact-inputs-20260831-v4` | Six strict FXC PS/CS builds at 8/16/32 samples; 34/34 analytic/shared-helper, 56/56 synthetic adapter and 34/34 focused donor-input cases. The focused cases exercise all 256 packed material bytes, hair-only bias and real constant-buffer frame bits. |
| `artifacts/rebirth-contact-candidate-20260831-v2` | Five native variants assemble and round-trip byte-identically. All original instruction tokens except temporary declaration are retained; masked contribution lanes checked. Generated kernel reads `t2.w` and integer `cb1[139].w`. |
| `artifacts/rebirth-contact-interface-20260831-v2` | 15/15 CreateComputeShader checks and 555/555 isolated injection cases: five variants, 37 cases, three frame/material profiles (0/1, 61/231, 12345/248). Source/runner fingerprints verified. **Interface-only**, not the full quality-gated validation receipt. |
| `artifacts/rebirth-contact-motion-animated-20260831-v2` | 96 frames each of plane, sphere, moving box and perturbed/quantized sphere, with animated donor IGN. Zero invalid outputs; unobstructed surfaces report no false hits. Moving box flags 209 false-hit samples, 281 misses among 2,787 eligible blocker samples, and 1,167 large visibility changes while binary truth remains unchanged. Final repeated geometry also repeats its noise frame for exact-repeat validation. **Not a passing motion result.** |
| `artifacts/rebirth-contact-native-input-evidence-20260831-v1` | Fresh FXC disassembly of two original cached PS binaries plus a copied native view buffer corroborate the sampling-index binding; see the mapping evidence below. |

These motion classifications are diagnostics against synthetic geometry, not proof that the original Rebirth mod has these game-visible defects. The incomplete caller integration, screen-space visibility and absence of temporal reconstruction matter. Do not start rewriting donor intersection math to force a pass without establishing which contract differs.

### Native input evidence and limits

`RebirthContactInputMapping.hlsl` isolates the Remake-only mapping. Native general light variant `c30cdc8365df9840` converts `t2.w*255+.5` to an integer and masks its low four bits. Its ID-7 branch has the strand tangent, light-plane construction and anisotropic constants matching the donor's `ShadeHair`; that is structural evidence, not yet an on-screen hair-mask validation. High-nibble flags must not become material IDs.

Original pixel shaders `7101fdc4c25fb2bd` and `a77b589dce5822d6` use `cb1[139].w` in an integer shift, mask to a 3D noise-texture slice, and load that texture. Original tiled lights use `.z` for their eight-phase slice. The captured view row 139 has unsigned bits `(899797841,11283,5,61)`; `61&7=5`. Read `.w` with `asint`, not float-to-integer conversion. Do not substitute row 140.x. Only one native frame is captured, so advancement after camera cuts/reloads remains unobserved. The evidence directory retains original binaries and the buffer; their provenance/hashes are in `evidence.md`.

Focused fixture development exposed loss of tiny synthetic float bit patterns before the mapping function; supplying real integer bits through an immutable constant buffer fixed the fixture. Early v1/v2 incomplete test runs and the diagnostic shader are preserved, not counted as passes. The current suite tests the actual buffer path. No donor ray mathematics changed for those tests.

### Donor reconstruction is spatial, not a history denoiser

The donor local-light caller alternates a checkerboard using pixel coordinates and `View_TemporalAAParams.x`. It traces two lanes of each 2x2 quad and reconstructs the others using `QuadReadLaneAt` and `saturate((lane0+lane1+lane2+lane3)*.5-1)`, where untraced lanes start at 1. This averages the two traced visibility values **within the same frame**. The optional SM5 prototype now implements the parity/average using explicit neighboring pixel inputs; the default raw path remains available. Neither harness runs Remake's later temporal AA.

The donor SM6 quad operation cannot be copied blindly into the native SM5 tiled compute path. Its lane geometry and per-light divergent branches must be respected; adding group barriers inside those branches is not a safe substitute. The current recomputation prototype establishes a testable scalar reference but increases cost and does not establish raster-helper equivalence. See the reconstruction report for matched motion results; raw rays or same-frame averages are not final game output.

Earlier artifacts are preserved: portable v2 had one invalid-viewport fixture failure, corrected only in adapter preflight for v3; motion v1 stopped at compile because finite fixture constants triggered FXC warning 3577 under /WX. Only the synthetic motion entry point suppresses that redundant-check warning. Parameterized production/smoke builds still compile with strict warnings.

### Reproduce offline

Choose unused absolute output paths below workspace `artifacts`; tools refuse overwrites.

```powershell
python tools/import_rebirth_contact_source.py
.\tools\Test-ContactShadows.ps1 -Implementation Rebirth -OutputDirectory '<new absolute artifacts directory>'
.\tools\New-IntergradeContactShadowCandidate.ps1 -Implementation Rebirth -OutputDirectory '<another new absolute artifacts directory>'
.\tools\Test-RebirthContactInterface.ps1 -CandidateDirectory '<candidate directory>' -TestBuildDirectory '<input test directory>' -OutputDirectory '<another new absolute artifacts directory>'
.\tools\Audit-ContactShadowMotion.ps1 -Implementation Rebirth -NoiseMode Animated -OutputDirectory '<another new absolute artifacts directory>'
```

For interface-only checks, the generated candidate JSON names each original/patched/fixture binary. `ContactShadowWarpTest.exe --validate-cs <original> <patched> <fixture>` performs creation checks; `--adapter-assembly <fixture> <depthSlot> <diffuseMask> <specularMask> [frameIndex materialByte]` performs 37 isolated execution cases per profile. These commands do not grant installation eligibility.

## Next work

1. Carry the wired material/frame inputs into a matching-source captured-resource replay; complete live progression/material coverage only when a focused observation is necessary.
2. Evaluate the implemented reconstruction against captured resources and establish native phase/coverage and a practical execution boundary. Do not present raw noisy-ray output or the current average as the complete Rebirth rendering result.
3. Only after input/interface and quality checks are satisfactory, prepare one reversible native-original comparison. Pause when user input is needed; no repeated confirmation cycles.

The old installed package remains unchanged. No request to press F10 or test in-game is needed at this step.
