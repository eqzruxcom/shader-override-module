# UE4 regex strategy

The HelixMod Universal UE4 patch is useful because Unreal emits recurring shader
families across games and engine revisions. Its signatures can locate candidate
passes even when a game's exact shader hashes and permutations are different.

This is the core portability model:

1. A regex family identifies a likely UE4 pass from disassembled DXBC.
2. 3Dmigoto captures the matching Intergrade shaders and their live resources.
3. A no-op replacement proves the match without altering the image.
4. The game adapter records the exact hash, partner stages, constants, textures,
   UAVs, and render targets.
5. Portable Rebirth-derived effect code is inserted only after that contract is
   verified.

“Mostly the same” therefore means structurally recognizable, not necessarily
byte-identical. Compiler version, UE4 branch, static switches, platform defines,
and game modifications can all change hashes, register allocation, and control
flow without changing the pass's purpose.

## Confirmed reference families

The authorized Intergrade Helix package contains 204 base `ShaderRegex` sections.
The most useful discovery families for this project are:

| Project pass | Universal UE4 candidate families | What must still be confirmed |
| --- | --- | --- |
| Directional light | `ShaderRegex_72_SunLightPS1` through `PS4` | GBuffer inputs, shadow input, output blend contract |
| Local lights | `ShaderRegex_01_DynamicLights1` through `6`; `ShaderRegex_07_Lights*`; `ShaderRegex_17_*LightsAdditional*` | ordinary/IES permutations, attenuation and shadow resources |
| SSR | `ShaderRegex_02_SSR_Velocity*`; `03_SSR_Extended1`; `04_SSR_Extended2`; `05_SSR_Standard`; `74_SSR_Additional*`; `91_WaterSSR_1` | PS versus CS path, scene depth/color slots, velocity, UAV outputs |
| Reflection environment | `ShaderRegex_08_Reflections_*`; `ShaderRegex_55_Reflection*`; `*SpecReflect*`; `86_PerfectMirror` | cubemap/probe resources, BRDF inputs, compositing target |
| Fog | `ShaderRegex_01_Volumetric_*`; `ShaderRegex_07_VolumetricSpecial`; `ShaderRegex_67_VolFog_GS` | whether Intergrade uses volumetric or analytic path at the test scene |
| Ambient occlusion | `ShaderRegex_79_AO1` through `AO5` | depth/normal reconstruction and target channel |

These names are discovery hints, not claimed Intergrade matches. The adapter keeps
them separate from verified shader hashes for that reason.

## First capture sequence

The first vertical slice remains the final post-process pixel shader because it is
the lowest-risk place to prove replacement, controls, and color-space handling.
The Universal stereo patch does not provide a reliable final-tonemap identity, so
that pass will be located by render-target inspection and controlled skip tests.

After the final pass works:

1. Run the Universal lighting regex families against the live shader cache.
2. Confirm candidates with 3Dmigoto marking and single-frame captures.
3. Record exact contracts in `shader-map.json`.
4. Port directional light, then local light, then SSR/reflections.

## Generated reference inventory

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Analyze-HelixReference.ps1
```

The report is written to `artifacts/helix-reference-inventory.json`. It records
section identifiers and shader-file metadata, not copies of the regex bodies.
