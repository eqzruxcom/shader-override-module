# Remake / Rebirth / Universal UE shader coverage audit

> The exact Shader Injector v2.2.1 pass/stage inventory and corresponding
> Rebirth-to-Remake status are maintained in
> [`rebirth-v2.2.1-pass-coverage-matrix.md`](rebirth-v2.2.1-pass-coverage-matrix.md).
> This audit's shorter mapping table should be read through that modified-UE4
> distinction.

Date: 2026-08-31

## Bottom line

Hard/direct lighting, ambient occlusion, contact shadows, reflections, fog, and
post processing are reusable **effect families**. Their mathematical ideas are
generally portable. The bytecode stage, bindings, output contract, insertion
point, permutations, and renderer scheduling are not universal and must be
resolved for each engine/API adapter.

The user's central coverage concern is confirmed: a reliable universal changer
cannot stop after one shader hash or one stage. It must discover every compatible
variant in a family, transform each proven variant, and flag unmatched or
ambiguous shaders for review.

This audit also confirms why that cannot be a blind instruction replacement:
Cloud's observed clothing shader `8b1f6ebe443b5615-ps` matches generic Universal
UE4 lighting patterns, but frame/resource evidence identifies it as a six-MRT
material/GBuffer producer. It writes inputs consumed by deferred lighting; it is
not itself a proven light-evaluation pass.

## Scope and evidence boundaries

- Target: Final Fantasy VII Remake Intergrade, modified UE4, DX11, SM5.
- Current capture: one regional shader cache, not the whole game.
- Donor: Final Fantasy VII Rebirth, different renderer revision, DX12, SM6.6.
- Donor use: behavioral and source-level reference, never direct hash/binding
  equivalence.
- Ocean and water packages are excluded from the current priority.
- Original headers on the five live contact compute shaders were restored and
  retained. The accepted left-edge fade remains isolated to
  `62b33a2d1e505241-cs`.

Machine-readable evidence is in
`artifacts/shader-coverage-audit-20260831-v1/coverage-audit.json`. The directory
also contains CSV inventories for the Remake cache, Rebirth donor packages,
Universal candidates, and exact old-Remake Helix intersections.

The current authoritative accepted/rejected family boundary is
`src/Adapters/FF7RemakeIntergrade/verified-shader-classifications.json`.
`tools/Test-RemakeVerifiedShaderClassifications.ps1` fails if a classified
hash is absent from the immutable regional inventory, loses its original D3D
disassembler header, lacks retained evidence, disagrees with the exact
five-variant contact checkpoints, or drops a required missing-scene target.
The older `shader-map.json` remains discovery history rather than the current
coverage authority.

## Rebirth donor inventory, excluding water

The pinned donor has four game-version packages for each pass below. There are
32 relevant packages after excluding 12 Ocean/Water packages.

| Donor pass | Stage | Packages | Main relevance |
| --- | --- | ---: | --- |
| DirectionalLight | PS 6.6 | 4 | directional direct light, contact shadows, micro shadows, direct-light AO, BRDF |
| LocalLight | PS 6.6 | 4 | point/spot direct light, contact shadows, micro shadows, occluded-light handling |
| LocalLightIES | PS 6.6 | 4 | IES permutation of local light |
| ReflectionEnvironment | CS 6.6 | 4 | ambient/GI, SSAO/SSGI AO, bounce light, reflection environment, specular behavior |
| SampleGI | CS 6.6 | 4 | baked-GI sampling and character ambient shaping |
| SSR | PS 6.6 | 4 | SSR ray count, steps, thickness, roughness behavior |
| PostProcessFog | PS 6.6 | 4 | near/far fog and atmosphere controls |
| PostProcessFinal | PS 6.6 | 4 | exposure, tonemap, bloom, sharpening, image adjustments |

There are no donor VertexShader packages. That describes this donor package,
not a universal claim that vertex shaders are irrelevant. The old Remake Helix
set and our live frame evidence both contain vertex partners and vertex fixes.

### Contact-shadow coverage in the donor

The shipped donor actively calls contact shadows in three raster pixel-pass
families:

- `PixelShaderPass_LocalLight.hlsl`
- the `LocalLightIES` permutation of the same source
- `PixelShaderPass_DirectionalLight.hlsl`

`ComputeShaderPass_SampleGI.hlsl` contains contact-shadow code, but its call is
inside `SPHERICAL_HARMONICS_DOMINANT_DIRECTION_DIFFUSE`. That feature define is
commented out in the shipped source, so it is not an active fourth contact path.

The local and directional passes branch on GBuffer shading-model IDs and include
default lit, cloth, preintegrated skin, subsurface profile, hair, and eye. Their
material-disable macros are off by default. The donor therefore does not patch
separate clothing/hair material PS files to create contact shadows; it evaluates
those materials inside deferred light passes.

## Current Remake capture

The current regional cache contains 184 unique shaders:

| Stage | Count |
| --- | ---: |
| VS | 70 |
| PS | 95 |
| CS | 18 |
| GS | 1 |

The live `ShaderFixes` directory is intentionally much smaller: five contact CS
replacements and three PS replacements. That live count is not coverage.

Twenty-two current shaders exactly intersect the old Remake Helix collection:
16 PS, 4 CS, and 2 VS. This is useful exact-build evidence and demonstrates that
the current area includes established shader families across all three major
DX11 stages.

### Proven current Remake roles

| Remake role | Stage/hash | Evidence status |
| --- | --- | --- |
| Tiled local-light variants | CS `c30cdc8365df9840`, `62b33a2d1e505241`, `5a9fbefe0ab6f815`, `0e97888f9a8767da`, `08bb8764f1840179` | proven adjacent dispatch family after the material/tile classifier |
| Tile material/light-list classifier | CS `f97a821dddaa328a` | proven 16x16 material-class mask/list selection |
| Tiled capsule-occlusion culling/evaluation producer | CS `b9e2305a994308f2` | proven 8x8 depth min/max reduction, buffered capsule candidate culling/list construction, analytical capsule-distance evaluation, and low-resolution occlusion/list outputs; its occlusion is upsampled before the five light-evaluation variants |
| Volumetric media field synthesis | CS `4b6fb3f0b78f9016` | proven 120x68x96 3D-field write from two noise volumes; precedes verified temporal/local-light volumetric injection |
| Temporal SSAO | PS `a77b589dce5822d6` | verified by output-channel isolation and live strength control |
| SSR trace/resolve | PS `b2bc6059f9a39c7f` | verified resource flow and amplified reflection response |
| Directional/cascade shadow projection and filtering | PS `aadc1c2374853914` | scene-depth receiver reconstruction plus four offset gathers from a Texture2DArray shadow map; outputs packed shadow factors |
| Skinned shadow-depth casters | VS `40b611d369bc7b68`, `40e368977f88f118`, `54bb7b01b6bd5196`, `741aee753c201ee6`, `7d8b4ec350c811b6`, `804f4caa626c8a94`, `8942481559f2a938`, `8c6447577e2664d5`, `fe4c1e062a2a682f` | nine header-retained variants load buffered bone transforms and blend them with `v4.xyzw` weights before emitting `ShadowDepth` |
| Static shadow-depth casters | VS `49b1908cb47c0d29`, `73012b97e989a07e` | two header-retained variants emit `ShadowDepth` without the skinned bone-buffer/blend path |
| Sampled material-coverage shadow-depth writers | PS `07a10abbef52a0f2`, `7faf10d13b4e23ec`, `d20b75105323b71d` | write `SV_DEPTH/oDepth` after Texture2D material sampling; coverage/material ownership is not assigned from structure alone |
| Direct shadow-depth writers | PS `50218fe92282b9b2`, `859e9302e9dc9520`, `ac87aba3f1feac47`, `bae7ee67de90d1d4` | write `SV_DEPTH/oDepth` without a Texture2D material sample; `ac87...` still uses a Texture3D dither/volume lookup |
| Reflection environment + SSR composite | PS `e2aa1c8cb39e0a55` | verified producer/consumer handle and composite dataflow |
| Reflection/indirect composition variant | PS `c62607f2631cf47e` | cache-unique shading-model BRDF signature and final scaling match the verified `e2aa1c8cb39e0a55` family; no shadow-map/filter contract |
| Volumetric local-light injection | PS `c25d7f5229662b97` | live verified |
| Temporal volumetric injection | PS `cbc771ff8a37a0b3` | live verified |
| Volumetric scattering/history | CS `ef7fe8d9c4e9ad15` | live verified |
| Final scene-color post | PS `af6cd28a0108a18a` | UI-safe scene-color target verified |
| Final presentation | PS `41f1bf8b79d01319` | presentation/image-adjustment role verified |
| Clothing/material GBuffer producer | PS `8b1f6ebe443b5615` | live conditional-skip confirmed Cloud clothing disappearance; six MRT outputs; not light evaluation and not proven clothing-only |

The five tiled-light CS variants are not proven to mean five exclusive object
types. User isolation observations (face, hair, face/body, broad/everything) are
retained as empirical coverage notes. Their shared architecture indicates
material/tile permutations selected through the classifier and indirect lists.

### Static versus dynamic shadow-caster evidence

The user's historical observation that dynamic/skinned character models use
special shadow shader permutations is directly confirmed in this Remake capture.
Every one of the nine skinned `ShadowDepth` vertex shaders declares a buffer at
`t0`, reads indexed transform rows from it, accepts `v4.xyzw`, and performs the
four-weight blend before projection. The two static `ShadowDepth` vertex shaders
omit that bone-buffer and blend path. This is the concrete version of describing
static environment shadow paths as "weaker": they can use a cheaper transform
permutation, while deforming characters require additional real-time work.

The seven `ShadowDepth` pixel shaders split again by material coverage: three
sample a Texture2D before writing `oDepth`, while four do not. One of the latter
uses a Texture3D lookup, so it is retained as a direct-depth/dithered variant and
not mislabeled as universally opaque.

These 18 shaders are shadow-map **casters/writers**, not contact-shadow or
deferred-light evaluators. They prove that a universal rule must enumerate
static, skinned, and material-coverage permutations. They do not prove that all
downstream shadow receivers have been found in this regional capture. Receiver
and per-light evaluation coverage remains a separate required family audit.

## Universal UE4 stereo-rule matcher result

The existing Universal UE4 **3D Vision correction** matcher compiled all 204
regex patterns with zero failures and zero timeouts, then scanned all 184 current
Remake shaders. These patterns identify shader structures that needed stereo
correction. They are not intended to inventory every renderer effect pass: a
shader absent from this rule set may simply have been handled correctly by the
driver's automatic stereo conversion.

- 115 raw pattern matches
- 45 unique shader candidates
- All 45 candidates now have an evidence-backed role
- 0 remain candidate-only
- Lighting candidates span 6 CS and 28 PS shaders

This proves the structural discovery and runtime-patching approach can find broad
PS/CS shader families, including shaders first created in later areas. It does
not measure complete effect coverage. It also proves why discovery and semantic
verification must remain separate:

- The five real tiled-light CS variants are found.
- `b9e2305a994308f2-cs` is found by lighting rules, but assembly plus frame
  flow identify it as upstream tiled capsule-occlusion culling/evaluation. It
  writes a low-resolution occlusion texture and candidate-list data that are
  consumed through a later depth-aware upsample, not the per-light BRDF/contact
  evaluation performed by the five surface-lighting variants. The offline
  ownership diagnostic now neutralizes only its final `u0.xy` visibility while
  retaining `u0.zw`, `u1`, and all original work; it is validated, defaults
  off, and remains uninstalled pending a focused live scene.
- `8b1f6ebe443b5615-ps` is found by both lighting and object/material patterns,
  but frame evidence says it is a GBuffer producer.
- `b2bc6059f9a39c7f-ps` is found by both lighting and SSR rules; resource flow
  proves SSR.
- `aadc1c2374853914-ps` is a true shadow pass independent of its generic rule
  names: it reconstructs the receiver from scene depth, filters a layered
  shadow texture with four offset gathers, and outputs packed shadow factors.
- `c62607f2631cf47e-ps` is found only by generic lighting/stereo rules, but its
  distinctive shading-model BRDF block occurs in exactly one other cached
  shader: verified reflection-environment composite `e2aa1c8cb39e0a55-ps`.
  Its full-GBuffer and precomputed-lighting inputs rule out a shadow-map/filter
  pass, so it is retained as a reflection/indirect composition variant.
- Remake's verified temporal SSAO shader `a77b589dce5822d6` is not in the AO1-AO5
  stereo-correction matches. That is **not** evidence of a missing AO shader or a
  Universal defect; SSAO may already have been stereo-correct automatically.
- The verified final scene post and presentation passes likewise are not present
  in the stereo-rule matches, which is neutral evidence for effect discovery.

Our Universal Unreal Engine Shader Changer should reuse this proven mechanism,
but build separate rules for each modification family. It needs three
coordinated match layers:

1. Exact known hashes for a known game build.
2. Instruction-pattern families for wide discovery.
3. Semantic descriptors using stage, resources, constants, outputs, instruction
   motifs, frame neighbors, and producer/consumer flow.

Ambiguous or low-confidence results must fail closed and enter shader hunting,
not receive an automatic effect patch.

### Saved-frame correlation of unresolved candidates

`tools/Correlate-ShaderCandidatesWithFrames.ps1` reconstructs persistent D3D11
render-target and vertex-shader state from each frame log, then correlates every
structural candidate with execution events, draw/dispatch type, and
`ShaderUsage.txt` peers. Its current output is
`artifacts/shader-frame-correlation-20260831-v1/frame-correlation.json`.

The correlation confirmed two material groups once and those classifications are
now retained per hash instead of repeatedly reopening them:

- 20 PS shaders execute against all six material/GBuffer MRTs. They are
  material/model permutations, not deferred direct-light evaluators.
- 5 PS shaders execute as single-target forward/translucent/decal-style
  material draws. Their full material interpolants, mesh/instanced geometry, and
  depth-target use distinguish them from fullscreen or light-volume evaluation.

Four cached but unexecuted candidates are structurally resolved: one six-MRT
GBuffer permutation, two forward-material permutations, and one layered
volumetric-slice pass. The fifth unexecuted shader, fullscreen PS
`8c9e92a0895efcdc`, is resolved by its exact old-Remake Helix file: the retained
header explicitly identifies screen-space reflections with a dithering
exception. It is therefore another SSR variant, not the missing directional
light evaluator. No candidate-only shader remains among these 45 matches.
Neither saved indoor capture proves a directional-light or LocalLightIES
evaluator, so those passes must be discovered from a suitable later-area frame
rather than inferred from generic regex names.

## Rebirth-to-Remake pass mapping

| Effect family | Rebirth implementation | Current Remake evidence | Coverage gap |
| --- | --- | --- | --- |
| Local contact shadows | LocalLight/LocalLightIES PS | five tiled local-light CS variants | current area covered for observed tiled local lights; future regional permutations not yet covered; IES identity not separately proven |
| Directional contact shadows | DirectionalLight PS | no directional pass proven in this indoor capture | capture an outdoor/directional-light frame and identify every active variant |
| Direct-light micro shadows / AO | Directional/Local PS | local CS candidates proven; no equivalent transformation audited | derive insertion point in each compatible local/directional Remake light variant |
| Ambient AO / SSGI | ReflectionEnvironment CS | temporal SSAO PS verified; reflection composite PS verified | Rebirth's combined ambient/SSGI architecture is not stage-equivalent; requires a Remake adapter, not a paste |
| Baked GI character shaping | SampleGI CS | no equivalent Remake GI pass proven | capture/trace GI producer and consumers |
| SSR | SSR PS | SSR PS and downstream reflection composite PS verified | normal-range live strength scene still needed before promotion |
| Reflection environment | ReflectionEnvironment CS | reflection environment/composite PS verified | port features selectively; architecture differs CS versus PS |
| Fog | PostProcessFog PS | volumetric PS injection plus CS history chain verified | distinguish analytic post fog from volumetric grid before porting controls |
| Final post | PostProcessFinal PS | final post and presentation PS verified | lowest-risk donor controls can be adapted after lighting priorities |

## Priority order for Remake

1. **Finish contact-shadow coverage in one area.** Preserve the known-working
   local-light code and Frustum Fix. Confirm all five local variants, then capture
   a directional-light scene and an IES-heavy scene. Do not touch material
   GBuffer shaders merely because they match a lighting regex.
2. **Add direct-light quality features.** Micro shadows, direct-light SSAO
   application, contact falloff/softness, and selected BRDF behavior belong next
   because their target light-pass family is closest to the working contact port.
3. **Map ambient/GI/AO.** Keep Remake's verified temporal SSAO separate from
   Rebirth's ReflectionEnvironment SSGI/AO. First locate the Remake ambient/GI
   accumulation pass and prove its inputs/outputs.
4. **Reflection environment and SSR.** The producer/composite chain is already
   mapped, but controls need a stronger reflection test view.
5. **Fog.** The volumetric chain is mapped; the donor's post-fog architecture is
   not assumed equivalent.
6. **Final post.** Adapt exposure/tonemap/bloom/sharpen/image controls only after
   the lighting stack is stable.
7. **Exclude Ocean/Water until requested.** They do not influence the current
   lighting investigation.

## Regional workflow and universal-generation requirement

The accepted current-area ShaderCache baseline is
`artifacts/analysis/intergrade-shader-cache-before-next-region-20260901.json`
(SHA-256
`1799A01376C15EA0D6CB3AB7AC07E580D371A0E6C2547EBBA8098306153369DC`):
184 original identities (`vs=70, ps=95, cs=18, gs=1`). It excludes
`*_replace` artifacts. Create the later-area snapshot with
`tools/New-IntergradeShaderCacheSnapshot.ps1`, then compare it with
`tools/Compare-IntergradeShaderCacheSnapshots.ps1`. The comparison reports
new identities by stage and treats changed bytecode under an existing identity
as a separate anomaly. The isolated regression
`tools/Test-IntergradeShaderCacheSnapshots.ps1` proves deterministic output,
replacement exclusion, added-identity detection, and binary-drift reporting.

For each new area:

1. Dump newly compiled shaders without deleting the previous corpus. Take an
   after-area identity snapshot and compare it with the pinned baseline before
   importing or hunting, so unchanged shaders are not re-reviewed.
2. Run `tools/New-RebirthRemakeShaderInventory.ps1` against the new capture
   manifest, inventory every hash/stage pair, and retain full original headers.
   Keep the generated JSON beside the capture as its machine-readable evidence.
   Compare it with the prior accepted area using
   `tools/Compare-RemakeShaderInventories.ps1`; review every added shader and
   semantic-family match rather than rescanning the unchanged corpus.
3. Run the existing Universal stereo rules as structural evidence, then run our
   changer's effect-specific family discovery over the accumulated corpus.
4. Run semantic matching and compare frame/resource contracts.
5. Apply transformations to every proven compatible variant in the family.
6. Flag new, ambiguous, or structurally exceptional variants for hunting.
7. Reconfirm the known working effects in motion before accepting the area.

Only after the same transformations survive multiple areas should they become a
Universal Unreal Engine Shader Changer rule. 3DMigoto can test such structural
rules when an unseen shader is first drawn or created and cache the patched
result, so exhaustive playthrough/hash collection is not required. Representative
multi-area validation is still required to catch structural variants and reject
false positives. The generated rule must preserve a game/API adapter layer
because UE3/DX9, UE3/DX11, UE4/DX11, and UE5/DX12 expose the same high-level
effects through different bytecode, resources, and render graphs.
