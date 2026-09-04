# Port backlog

The implementation order below is historical. As of 2026-08-30, follow
[Remake-first priorities](remake-first-priorities.md) for the ordered author ports
and the separate later Remake-specific investigations. Preserve these rows as
a capability/evidence inventory, not proof that each effect is needed.

Integration correction: `af6cd28a0108a18a` is an upstream scene-color hook,
not the final native tone-mapping boundary. The current author image-adjustment
test selectively edits `41f1bf8b79d01319` while retaining native tone mapping;
GT7 remains offline. See [the final-composite study](final-composite-integration-study.md)
and [the current live observation](author-image-adjustments-observation.md).

Statuses are evidence-based: `ready-library` means portable code can be built
now; `capture-required` means no Intergrade shader identity or resource binding
has been verified yet; `verified-hook` means a live Intergrade pass is mapped;
`replacement-compiled` means a strict SM5 replacement exists;
`live-neutral-verified` means native Original/control pixel parity passed;
and `full-replacement-rejected` records a compiled
candidate that failed visual parity and is excluded from packaging.

| Legacy order | Pass/effect | Source/hook evidence | Intergrade status | Historical first proof |
|---:|---|---|---|---|
| 0 | DX11 runtime | Existing Helix/3Dmigoto support | Proven externally | Local log and overlay |
| 1 | Image adjustments | UI-safe scene-color PS `af6cd28a0108a18a` | `ready-library`, `verified-hook`, `neutral-replacement-verified` | Visible exposure change on the verified hook |
| 2 | Tonemapping | UI-safe scene-color PS `af6cd28a0108a18a`; multiple portable operators | `ready-library`, `verified-hook`, `replacement-required` | Selectable Reinhard/ACES/Khronos modes |
| 3 | Sharpening | Rebirth uses SM6 quad reads | `capture-required` | SM5 texture-neighbor version with verified texel size |
| 4 | Directional contact shadows | DirectionalLight PS; depth/GBuffer/View data | `capture-required` | One verified outdoor directional permutation |
| 5 | Local contact shadows | LocalLight and IES PS variants | `capture-required` | One point light and one IES permutation |
| 6 | Specular occlusion | Lighting/reflection passes | `capture-required` | Toggle with matched material behavior |
| 7 | Ambient occlusion | PS `a77b589dce5822d6`; custom full-resolution temporal SSAO with normal, depth, HZB, velocity, and AO history | `verified-hook`, `packed-channel-isolation`, `X/Y-live-verified` | Preserve temporal weight/depth while exposing controllable AO strength |
| 8 | SSR | Producer PS `b2bc6059f9a39c7f` plus downstream composite PS `e2aa1c8cb39e0a55`; exact `o0` to `t11` resource handoff | `verified-hook`, `live-coverage-verified`, `downstream-radiance-positive`, `100%-neutral-verified`, `0%-to-100%-current-view-inconclusive`, `0%-to-1600%-diagnostic-positive`, `runtime-blocked` | Find a stronger normal-range SSR view, then validate 0%/100% and 50% while preserving hit alpha and reflection-environment fallback |
| 9 | Reflection environment | PS `e2aa1c8cb39e0a55`; cube-array captures plus exact `b2` SSR-resource handoff at `t11` | `resource-flow-verified`, `semantic-descriptor-unique-1-of-184`, `radiance-live-verified`, `100%-neutral-live-verified`, `amplified-response-verified` | Retain the environment path unchanged; normal-range SSR validation requires a stronger view |
| 10 | Sample GI/SSGI | Rebirth CS; expensive/experimental | `capture-required` | Static single-frame AO before bounce light |
| 11 | Fog | Volumetric injection PS passes plus scattering/history CS `ef7fe8d9c4e9ad15`; 120x68x96 grid | `verified-hook`, `full-replacement-rejected`, `original-first-post-compiled`, `live-neutral-verified` | Visible scattering/extinction strength change, then temporal and resolution validation |
| 12 | Water/ocean | Large specialized PS families | `capture-required` | One deterministic water material |

## Runtime capture gate

Before creating an Intergrade replacement, collect:

- `d3d11_log.txt` showing D3D11 and 3Dmigoto initialization;
- exact shader hash and stage;
- dumped HLSL and original assembly;
- shader usage entry and partner stages;
- bound `t#`, `s#`, `cb#`, `u#`, render targets, and depth target;
- resource formats and dimensions;
- screenshots with the shader skipped, original, and pink-marked;
- resolution, dynamic-resolution state, graphics settings, and scene location.

