# Rebirth v2.2.1 pass coverage versus FF7 Remake

## Purpose

This matrix keeps three different kinds of evidence separate:

1. Shader Injector v2.2.1 describes features and pass organization in **FF7
   Rebirth**.
2. The current captures describe the modified UE4 renderer used by **FF7
   Remake Intergrade**.
3. The 3Dmigoto Universal UE4 rules demonstrate broad structural recognition
   for stereo correction; they do not enumerate every effect pass.

Remake is therefore a difficult compatibility adapter, not the source of the
canonical stock-UE4 family model.

## Donor inventory

The Maximum Quality package contains 44 target manifests: one target for each
of 11 logical shader families in four supported Rebirth version groups.

| Rebirth family | Stage | Shared source role |
| --- | --- | --- |
| DirectionalLight | PS | deferred directional-light evaluation |
| LocalLight | PS | deferred local-light evaluation |
| LocalLightIES | PS | local-light evaluation with the IES variant enabled |
| OceanA | PS | ocean rendering |
| PostProcessFinal | PS | final image processing |
| PostProcessFog | PS | fog post process |
| ReflectionEnvironment | CS | reflection environment plus optional SSGI/AO |
| SampleGI | CS | sampled/baked GI and character-direction shaping |
| SSR | PS | screen-space reflections |
| WaterA | PS | water rendering |
| WaterB | PS | alternate water permutation |

This is exactly **9 pixel-shader families, 2 compute-shader families, and zero
vertex-shader families**. LocalLight and LocalLightIES share one implementation
with a variant define. WaterA and WaterB do the same. The four version targets
are small wrappers around shared HLSL rather than four independent rewrites.

The absence of vertex shaders is a fact about this donor version, not proof
that Unreal lighting and shadow work can never involve a vertex shader. It
means these particular Rebirth modifications are made at pixel/compute
evaluation points.

## Current Remake area corpus

The immutable area capture contains 184 original shaders:

- 95 PS
- 70 VS
- 18 CS
- 1 GS

The independent semantic matcher currently proves these Remake passes:

| Remake role | Hashes | Stage |
| --- | --- | --- |
| motion-blur/scene-color resolve | `af6cd28a0108a18a`, `eda405f2d455d5c7` | PS |
| reflection environment and SSR composite | `e2aa1c8cb39e0a55` | PS |
| SSR trace/resolve | `b2bc6059f9a39c7f` | PS |
| temporal SSAO horizon | `a77b589dce5822d6` | PS |
| volumetric-fog grid injection | `c25d7f5229662b97`, `cbc771ff8a37a0b3` | PS |
| volumetric scattering/history | `ef7fe8d9c4e9ad15` | CS |

The known contact-shadow port currently runs in five tiled local-light compute
variants:

- `08bb8764f1840179`
- `0e97888f9a8767da`
- `5a9fbefe0ab6f815`
- `62b33a2d1e505241`
- `c30cdc8365df9840`

The observed coverage labels for those five variants are retained separately
in `contact-output-isolation-results.md`. They are observations about visible
coverage, not exclusive object-type declarations.

## Reproducible inventory

`tools/New-RebirthRemakeShaderInventory.ps1` validates the donor package,
capture manifest, retained DXBC/assembly artifacts, and semantic report, then
emits a machine-readable inventory. The baseline command is:

```powershell
& tools\Test-RebirthRemakeShaderInventory.ps1
```

The current verified output is
`artifacts/analysis/rebirth-v2.2.1-remake-area-inventory.json`. The regression
test requires all 44 donor packages, 11 logical families, four version groups,
the 9 PS / 2 CS / 0 VS donor split, all 184 captured Remake shaders, and all
184 original D3D disassembler headers, plus all eight verified semantic
matches. A missing artifact or header, duplicate shader, malformed package,
stage/count mismatch, or semantic match outside the capture fails the run.

For a later area, first generate its inventory and then compare it with the
baseline:

```powershell
& tools\New-RebirthRemakeShaderInventory.ps1 `
  -CaptureManifest artifacts\validation-captures\NEW-AREA\capture-manifest.json `
  -OutputPath artifacts\analysis\NEW-AREA-inventory.json

& tools\Compare-RemakeShaderInventories.ps1 `
  -BaselinePath artifacts\analysis\rebirth-v2.2.1-remake-area-inventory.json `
  -CandidatePath artifacts\analysis\NEW-AREA-inventory.json `
  -OutputPath artifacts\analysis\NEW-AREA-delta.json
```

The delta report lists added and removed hashes by shader stage and added or
removed semantic-family matches. It rejects inconsistent inventories or donor
family identities. `tools/Test-RemakeShaderInventoryDelta.ps1` verifies both
the zero-delta case and a synthetic PS-added/VS-removed regional change.

## Permanent Remake classifications

`src/Adapters/FF7RemakeIntergrade/verified-shader-classifications.json` is the
authoritative classification boundary for hashes already proven in this
adapter. It records the complete five-variant tiled surface-light family,
upstream classifier and capsule-occlusion producers, the directional/cascade
projection pass, the material/GBuffer producers, retained evidence paths, and
the still-missing scene requirements. It deliberately excludes upstream and
material producers from contact-ray injection.

Validate that every classified hash remains present in the immutable regional
inventory with its original disassembler header and evidence, and that the
contact family still agrees with the software and live checkpoints, with:

```powershell
& tools\Test-RemakeVerifiedShaderClassifications.ps1
```

This manifest supersedes the incomplete historical pass slots in
`src/Adapters/FF7RemakeIntergrade/shader-map.json`; it does not erase that
earlier discovery history.

## Pass-to-pass coverage matrix

| Rebirth donor family | Current Remake evidence | Status and interpretation |
| --- | --- | --- |
| DirectionalLight PS | `aadc1c2374853914` is a directional/cascade shadow projection/filter, not the donor's light evaluator. No directional-light evaluator was proven in this indoor capture. | **Missing capture.** Find it in an outdoor directional-light scene. Do not substitute a shadow-map projection pass merely because its name contains shadow. |
| LocalLight PS | five tiled local-light CS variants accept the working contact-shadow port | **Behavior mapped, layout changed.** Remake moved the relevant surface/light evaluation into custom CS permutations. These are Remake adapter targets, not stock-UE4 PS descriptors. |
| LocalLightIES PS | no IES-specific identity proven among the five CS variants | **Unproven.** Capture a visibly patterned IES light and correlate all active variants. |
| ReflectionEnvironment CS | `e2aa1c8cb39e0a55` reflection/SSR composite PS; `a77b589dce5822d6` temporal SSAO PS | **Split and stage-changed.** Rebirth's combined SSGI/AO behavior requires a Remake-specific adapter, not a direct source paste. |
| SampleGI CS | no equivalent GI producer/evaluator proven | **Missing capture or classification.** Trace the GI producer and its consumers before modifying anything. |
| SSR PS | `b2bc6059f9a39c7f` SSR PS and downstream `e2aa1c8cb39e0a55` composite PS | **Mapped.** Producer and consumer are known; a stronger reflection test scene is still required. |
| PostProcessFog PS | two volumetric grid-injection PS passes plus a volumetric scattering/history CS | **Different architecture.** Analytic post fog and the volumetric grid must remain separate families. |
| PostProcessFinal PS | `af6cd28a0108a18a` and `eda405f2d455d5c7` scene-color/post passes; historical `41f1bf8b79d01319` presentation work | **Likely split.** Exact final-stage responsibilities must be proven from frame/resource flow before donor controls are ported. |
| OceanA / WaterA / WaterB PS | no relevant execution in this industrial area | **Out of current scope.** Do not generate water replacements from absent evidence. |

## Material and shadow-family boundary

`8b1f6ebe443b5615` is an observed clothing/material PS with six GBuffer MRT
outputs. It is a GBuffer producer, not the deferred light-evaluation pass where
the Rebirth donor calculates contact shadows. Hair, face, body, clothing, and
static-world material permutations may receive different native shadow
quality, but their GBuffer writers must not receive the contact-ray code merely
because disabling them changes the visible object.

The correct universal model retains both sides:

- material/model families identify what data is produced and can remain
  separately classifiable;
- directional/local/IES light families identify where contact and micro-shadow
  visibility is evaluated.

## Relationship to Universal UE4 3Dmigoto rules

The Universal UE4 fix demonstrates that repeated DXBC structure can recognize
large shader families automatically, including many shadow-related shaders.
That is strong precedent for discovery and generation. Its purpose is stereo
correction, however, so a matching Universal rule is evidence that a shader
uses a familiar position, projection, depth, or shadow structure - not proof
that it is the correct insertion point for contact shadows, SSAO, SSR, GI, or
fog.

Our effect patcher therefore uses two layers:

1. a canonical stock/near-stock UE renderer descriptor derived from ordinary
   games;
2. explicit game adapters for verified alterations such as Remake's tiled
   local-light compute family.

At the engine-semantic layer, a local-light evaluator may correspond across
games even when one game uses PS and another uses CS. At runtime, matching
remains stage-, interface-, resource-, and output-specific. Stage equality is
not required to say two passes perform a related job; it is mandatory before
applying a compiled replacement or transformation.

## Immediate consequence

The working Remake contact implementation remains valuable, but it must be
recorded as a modified-UE4 adapter. The next canonical-family work should use a
stock or near-stock UE4/DX11 capture, while Remake development continues by:

1. finishing the five known local CS variants in this area;
2. finding the missing directional and IES variants in suitable scenes;
3. retaining every original header and regional hash;
4. confirming the family in another area;
5. extracting the proven transformation into the generated universal rule.
