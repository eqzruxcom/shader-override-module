# Surface-lighting occlusion study

Date: 2026-08-30. Scope: the captured Intergrade DX11 frame, not all scenes or engine versions.

## Result

The existing capture contains five tiled surface-lighting compute variants. All five original binaries successfully disassemble, validate, and reassemble byte-for-byte unchanged. No effect was installed or visually tested in this study.

The original code already combines material-channel occlusion, the native screen-AO result, and another occlusion texture before per-light shading. This is evidence against assuming that direct lighting lacks all occlusion. It is not evidence that the native algorithm equals the donor's optional Uncharted 4 microshadow formula, nor that either looks better.

Reproduce the offline audit with a new output directory:

```powershell
.\tools\New-IntergradeSurfaceLightingStudy.ps1 -OutputDirectory 'C:\Users\EQZITARA\Documents\ChatGPT\FF7 Rebirth mod\artifacts\surface-lighting-study-new'
```

The tool fingerprints the executable and five original binaries, checks the recorded dispatch identities, preserves a frame-log snapshot, and generates independent FXC assembly plus unchanged assembler round trips. It only writes a new workspace artifact directory and refuses to overwrite prior evidence.

Current result: `artifacts/surface-lighting-study-20260830-v3/study.json`. Every variant has `runtimeEligible=false`. Decompiled text is retained for navigation; fresh binary disassembly is the authority. Six related producer/classifier binaries are also preserved and freshly disassembled, but are not counted among the five byte-identical round trips. These captured game binaries and their derived sources remain local research artifacts, not redistributable mod code.

## Captured variants

| Event | Compute shader | Indirect argument offset | Screen AO / other occlusion slots | Native per-light visibility register |
|---:|---|---:|---|---|
| 1028 | `c30cdc8365df9840` | 0 | t6 / t7 | r29.z |
| 1029 | `62b33a2d1e505241` | 12 | t5 / t6 | r17.y |
| 1030 | `5a9fbefe0ab6f815` | 24 | t5 / t6 | r21.z |
| 1031 | `0e97888f9a8767da` | 36 | t6 / t7 | r21.y |
| 1032 | `08bb8764f1840179` | 48 | t6 / t7 | r15.w |

Each declares a 16x16x1 thread group. These are indirect calls: their presence in the log does not prove that every variant ran a nonzero number of groups or contributed visible pixels in this view. The argument-buffer contents were not captured here.

Do not map this family into the old `local_light` pixel-shader slot by changing only its hash. This is a compute integration with five variants, tiled light lists, indirect dispatch and a UAV output. Nor is it the previously identified volumetric-fog light injection.

## Input and resource evidence

- t1 loads a normal, decodes it from [0,1] to [-1,1], and normalizes it.
- t2 carries material values and a packed classification: the shader scales alpha by 255, rounds, then masks its low four bits. Material-class labels are not yet independently validated for this build.
- t3 supplies base-color-like RGB and an alpha value used in occlusion. The log binds the exact G-buffer target written as o3 (`0x00000278082EB7E0`) to this t3 input. Representative writer `37efcd402da50bcb` writes a saturated texture sample to o3.w. This supports a material-occlusion interpretation, not a complete audit of every material producer.
- Draw 1019 (`a8845c7ad73425a9`) writes the AO output at `0x0000027807DEEAE0`. Its inputs include the native temporal result and the downstream filtered AO chain. The lighting shaders sample this same resource through the screen-AO slots above; this is an exact handle match, not merely equal resource hashes.
- The second occlusion input is `0x0000027807DEEDA0`. Event 1020 initializes it with compute shader `c814bac1ac75b35e`, and event 1024 writes to it with `53fca3b84eeecea5`. The latter depth-aware upsamples the result of event 1023, `b9e2305a994308f2`, from `0x00000278079F7760`. That compute shader reconstructs position, iterates buffered center/radius/axis/length data, clamps receiver projection along each axis to half-length, and normalizes distance to the closest point by radius before analytical attenuation. This is strong structural evidence of capsule-shaped occlusion, not a per-light screen-depth ray march. The precise capsule ownership, strength and visual coverage still require runtime data. Do not call the input a white fallback or assume it contains no character/contact occlusion.
- Per-light positions/directions and attenuation parameters are accessed through indexed cb3/cb4 arrays. A shadow-map array is sampled before the shading loop. Preserve these native terms.
- All five compute variants write the same scene UAV, `0x00000278082EE960`. Later rendering and the verified reflection-environment composite use this scene target.

### Capsule-path classification correction

`b9e2305a994308f2` is not merely a tiled-light list builder. Its retained
assembly proves an 8x8 depth reduction, capsule candidate culling/list
construction, and analytical capsule-distance occlusion evaluation. Its
low-resolution occlusion output is depth-aware upsampled before the five tiled
surface-light evaluators consume it. This validates separate expensive
dynamic/capsule-shadow infrastructure of the kind expected for character
rendering, but it does **not** yet prove character-only ownership. The next
runtime test must identify its visible ownership; contact-ray code must not be
inserted into this upstream producer.

## Native occlusion equation

The shared original instruction sequence at approximately lines 219-235 of the generated FXC assembly implements the following blend for scalar visibility inputs:

```text
p = a * b
m = min(a, b)
q = 1 + p - m
B(a, b) = p + q*q*(m - p)

combinedVisibility = B(B(materialChannel, screenAO), otherOcclusion)
```

For inputs within [0,1], this lies between the product and the minimum; an input of one preserves the other input. This mathematical property does not establish the range of every runtime input without data.

Within each light loop, a native flags branch either takes the minimum of shadow-map visibility and `combinedVisibility`, or uses `combinedVisibility` directly. Further diffuse/specular remapping follows; this scalar is not simply a multiplier applied to the final image.

This differs from the donor's Uncharted 4 formula:

```text
saturate(NdotL + 2*materialAO*materialAO - 1)
```

The donor also has its own default micro-occlusion routines. In the pinned **local-light** source, `ENABLE_MICRO_SHADOWS`, its skin variant, and its hair variant are commented out; the alternate branch remains active. Inspect each donor pass independently rather than describing one global default. Source: `reference/ShaderInjector/ModifiedShaders/Includes/PixelShaderPass_LocalLight.hlsl` and `LibraryMicroShadows.hlsl` at the pinned revision in the priority document.

## Consequence for the port

### Tile specialization and the first useful boundary

The classifier `f97a821dddaa328a` ORs material-class bits across each 16x16 tile: IDs 1/5 contribute bit 1, ID 3 bit 2, ID 9 bit 4, ID 7 bit 8, and ID 8 bit 16. It selects list 1 for mask 1, list 2 for masks 2/3, list 3 for masks 8/9, list 4 for mask 10, and list 0 otherwise. Lists are spaced by `0x8700` entries; the indirect argument offsets match the five rows above. This establishes specialization logic, not the actual tile population in the captured frame.

The simple `62b33a2d1e505241` variant handles the ID 1/5 case, but those same material classes can also occur in list 2 (mask 3), list 3 (mask 9), and the general list 0. Editing only the simple and general variants would still give incomplete and potentially camera-dependent coverage. A material-specific port must cover every relevant specialization, not assume a shader hash identifies one object or light.

In the simple variant, normal/light dot product is computed at the per-lobe stage, after the earlier occlusion blend. The final per-light diffuse contribution accumulates in r15.xyz, the specular contribution in r16.xyz. Final RGB adds those contributions to the existing scene; output alpha includes diffuse luminance and is not disposable metadata. A minimal port needs to change the appropriate upstream lobe visibility while retaining that output calculation.

### Remaining decision

Microshadow work is an alternative-occlusion experiment, not a missing-feature toggle. A naive extra multiplication would stack a new darkening term on existing native occlusion, potentially confusing the comparison and over-darkening materials.

Keep the original native path as baseline. Before implementing the optional donor formula, trace the material-specific diffuse and specular visibility branches and decide exactly which native term it replaces or modifies. Preserve screen AO, the other occlusion source, shadow maps, transmission, skin/hair behavior, and output packing. Do not rewrite the full BRDF to obtain one extra factor.

The byte-identical compute round trips remove a tooling uncertainty: minimal assembly edits are feasible offline. They do not prove live compatibility, material coverage, performance, or an improvement.

Next technical steps:

1. Finish the material-class and per-lobe visibility mapping on the simple variant, and identify where the same case occurs in the mixed-material variant.
2. Determine which tiled variants actually contribute in the chosen test view, using existing classification logic or a focused capture if required; do not ask for five arbitrary visual toggles.
3. Prepare a narrowly scoped alternative with a provably unchanged disabled path, or explicitly skip it if the native behavior makes the proposed change redundant or undesirable. Contact shadows remain the next ranked feature, not a reason to multiply all lighting by AO again.

Decision after this audit: defer the optional microshadow replacement until there is a clearer improvement to test. Preserve native occlusion and proceed with the separate donor [contact-ray component](contact-shadow-port.md), which is now implemented and tested offline but not bound to Remake. This is a prioritization decision, not proof of equivalent algorithms or no possible microshadow benefit.

No F10 or other user action is needed for this offline study. The author image-adjustment comparison remains the installed live overlay.
