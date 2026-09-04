# Architecture

> **Current control policy:** [`hotkey-policy.md`](hotkey-policy.md) supersedes
> older per-effect key assignments below. Page Down is reserved for a master
> injected-code A/B; Page Up is reserved for the current development
> feature A/B. Historical key descriptions remain evidence of earlier builds,
> not the target runtime design.

## Scale decision and delivery order

Manual hash-by-hash replacement is a discovery and verification workflow. It
is not the final architecture and cannot cover the number of shader variants
encountered across complete games and UE generations.

The required delivery order is:

1. Finish the FF7 Remake adapter in one area, validate it in additional areas,
   and prove that every accepted transformation reaches all compatible shader
   variants that appear.
2. Extract the proven pass families, match rules, controls, and transformations
   into the Universal Unreal Engine Shader Changer.
3. Generate game/version adapters and runtime replacements from shared source;
   do not require a user or developer to play an entire game and manually
   collect every regional hash.

Shader Injector v2.2.1 for FF7 Rebirth is direct design precedent. Its two
presets each contain 158 files, of which 143 are identical. Shared pass-level
HLSL is referenced by small game-version entry points, structural fingerprint
JSON identifies compatible runtime shaders, and compiled blobs are deployment
artifacts. The Performance and Maximum Quality presets alter only three shared
source files; they do not duplicate the whole implementation. Our DX11/UE
system must provide the same separation using family descriptors,
ShaderRegex/fingerprint matching where proven, shared HLSL, and generated
runtime output.

The official source confirms the scalable mechanism: direct hashes are the
fast path, while stage/size/reflection gates and normalized semantic analysis
discover compatible variants, reject ambiguity, and persist learned aliases.
See [`shader-injector-family-matching-study.md`](shader-injector-family-matching-study.md)
for the verified pipeline and API boundary, and
[`shader-injector-v2.2.1-preset-diff.md`](shader-injector-v2.2.1-preset-diff.md)
for the exact preset comparison.
The donor's complete stage/pass inventory and its non-equivalent mapping onto
Remake are recorded in
[`rebirth-v2.2.1-pass-coverage-matrix.md`](rebirth-v2.2.1-pass-coverage-matrix.md).
It confirms that the donor modifies nine PS families, two CS families, and no
VS families; Remake's custom renderer moves several related jobs to different
stages and therefore requires explicit adapter descriptors.

Accepted Remake identities are retained separately in
`src/Adapters/FF7RemakeIntergrade/verified-shader-classifications.json` and
checked by `tools/Test-RemakeVerifiedShaderClassifications.ps1`. That boundary
keeps complete light-evaluation families eligible while explicitly excluding
upstream capsule/classifier passes and material/GBuffer writers from contact
injection.

## Renderer scope order

The Universal Unreal Engine Shader Changer targets renderer families in this
order:

1. UE4 / DirectX 11.
2. UE3 / DirectX 11.
3. UE3 / DirectX 9.

Where practical, use comparable DX11 and DX9 builds of the same UE3 title as
the bridge between steps 2 and 3. The paired builds let one reviewed lighting,
shadow, material, or post-process intent be traced across SM5 and SM3 without
pretending that bytecode, bindings, or replacement binaries are interchangeable.

This is one project with shared effect intent, shader-family semantics, test
cases, and transformation descriptions. It is not one interception binary:
capture, bytecode parsing, resource binding, patch emission, and runtime
injection are backend-specific for DX11 and DX9. UE3/DX11 is the first proof
that the system is not coupled to UE4; UE3/DX9 then proves portability to the
older shader model and Helix-era pipeline.

The user-supplied BioShock Infinite DX11 transformer script and Mass Effect 3
DX9 override corpus are analyzed in
`docs/helix-ue3-shader-transformer-evidence.md`. They establish semantic
family-rewrite precedent across both UE3 backends while keeping the closed
wrapper and cross-game generality claims explicitly unproven.

FF7 Remake is a modified UE4 renderer and must not define the canonical UE4
family model. It is the first implementation because it is the active project,
and it is valuable as a difficult compatibility test. Canonical UE4/DX11
descriptors must ultimately be derived and verified against stock or near-stock
UE4 games. Remake-specific pass layouts, altered lighting/shadow behavior, and
custom bindings belong in the FF7 Remake adapter as explicit exceptions.

## Layers

1. **Portable effects** contain SM5-compatible math, color, tonemapping,
   lighting, reflection, and GI algorithms. They have no game hashes or fixed
   resource declarations.
2. **Engine adapters** define conventions shared by renderer families, such as
   reversed-Z reconstruction, GBuffer decoding, and pre-exposure handling.
3. **Game adapters** record verified shader hashes, stages, partner filters,
   resource slots, constant-buffer offsets, and version fingerprints.
4. **Pass-execution contracts** separate the game event used as a trigger from
   the work that executes there. A pass may preserve the caller draw, or own
   its shaders, geometry/dispatch, fixed state, resources, and restoration.
5. **Replacement shaders** preserve a captured shader's exact inputs and
   outputs, translate its resources into portable inputs, and call effects
   when replacement is the selected execution mode.
6. **Runtime backends** activate replacements, injector-owned passes, and
   controls. Native D3D11 uses
   3Dmigoto as the discovery/reference oracle; the primary Vulkan runtime is a
   patched DXVK D3D11 backend that preserves the same original-DXBC hashes and
   replacement identities.

The engine adapter represents normal UE behavior. A game adapter may override
it, but evidence from a modified game cannot silently become a universal rule.

The DXVK backend does not redefine shader families. It consumes the same
verified identities, family descriptors, and generated SM5 DXBC that the
native-D3D11 path proves. This keeps FF7 Remake, stock UE4/DX11, and UE3/DX11
on one matcher/effect model while allowing different interception runtimes.

`src/Engine/PassExecution/schema.json` is the backend-neutral boundary for
this distinction. A shader-family or adapter hash can schedule a pass without
donating its geometry. Injector-owned render passes must declare their own
geometry and complete fixed state, plus the state categories that the backend
restores. `r3d-ssgi-owned-fullscreen-composite.json` is the first validated
instance: Intergrade's `e2aa1c8cb39e0a55-ps` event is only the trigger, while
the composite uses a three-vertex `SV_VertexID` fullscreen triangle. The same
contract maps to a 3Dmigoto CustomShader today and an owned Vulkan graphics
pass in the DXVK backend later. It remains runtime-ineligible until its live
zero-output prerequisites pass.

`tools/Export-PassExecution3Dmigoto.ps1` is the first backend emitter for this
contract. It generates the CustomShader section and copies only its declared
VS/PS payloads. `tools/Test-PassExecution3DmigotoEmitter.ps1` proves the emitted
section is exactly equivalent, after newline normalization, to the reviewed
R3D SSGI owned-composite section. This makes the INI an output of the portable
execution description instead of the authoritative design. The emitted pack
inherits the contract's fail-closed `runtimeEligible=false` state.

## First vertical slice

The first runtime target is Intergrade's final SDR post-process pixel shader.
It is deliberately selected before lighting because it provides a bounded
proof of the complete replacement workflow:

1. Capture and mark the final full-screen shader.
2. Preserve its original shader model, input signature, and UI composition.
3. Confirm a no-op replacement with F10 reload.
4. Insert image adjustments.
5. Add one selectable tonemap at a time.
6. Add texture-based sharpening only after source texture dimensions and UV
   transforms are verified.

## Portability constraints

- Rebirth sources use Shader Model 6.6 and DX12 register spaces. Intergrade
  replacements must compile for the captured DX11 model, normally SM5.
- Wave/quad operations are not assumed. Algorithms requiring them receive an
  SM5 texture-sampling implementation or remain disabled.
- Exact hashes are game-build data, not portable identities. ShaderRegex may
  provide resilient matching only after an exact-hash implementation is
  verified and a sufficiently narrow instruction signature is proven.
- Multipass effects such as SSGI and exposure reduction require explicit
  resources, pass scheduling, and state isolation. The 3Dmigoto backend emits
  CustomShader command lists; a native backend executes the same pass graph
  directly. They are not treated as simple shader replacements.

## Generated runtime contract

Semantic detection does not create a game adapter. `Invoke-UE4ValidationCapturePipeline.ps1`
provides the one-command import and candidate path. After a neutral capture is
imported, `tools/New-UE4AdapterCandidateReport.ps1` binds the semantic report to
the capture manifest, install manifest, and current executable SHA-256. It only
emits scan-evidence candidates. The report schema fixes `runtimeEligible` to
false and records five required gates that scans cannot prove: resource binding,
replacement shader, control pack, live visual behavior, and explicit eligibility
review. `tools/New-UE4AdapterReviewWorkspace.ps1` adds a second immutable
boundary: it fingerprints the candidate report and executable, rechecks captured
artifact hashes, and initializes every required gate to pending with null
evidence. Its schema permanently fixes the initial workspace and candidates to
`runtimeEligible=false`; `tools/Assert-UE4AdapterReviewWorkspace.ps1` rejects any
source drift, duplicate or omitted candidate, incomplete gate set, or pre-verified
state. Passing this initial review-workspace assertion does not promote a shader.
Only separately authored, evidence-bearing gate artifacts and a validated game
binding can enter the generated-adapter pipeline below.

`tools/New-UE4GeneratedRuntime.ps1` converts a fail-closed generated adapter
into an installable `Mods` payload. It emits only passes present in the
adapter's eligible `passes` array, verifies every control-pack and HLSL hash,
and records blocked passes in the runtime manifest without emitting their
shader hashes or command lists. The FF7 proof package currently emits temporal
volumetric scattering, scene saturation, and ambient occlusion as twelve
non-original shader levels plus one generated INI; the downstream SSR composite
remains manifest-only.

`tools/Stage-UE4GeneratedRuntime.ps1` builds a clean official-3Dmigoto stage
containing only that generated payload. The reversible live-overlay installer
backs up every overwritten file, verifies every copied hash, and records exact
rollback state before a running-game F10 parse test. It refuses installation
while legacy `RebirthEffectsDX11.ini` or `RebirthFogGlobalDX11.ini` diagnostics
are active, preventing duplicate hash overrides from contaminating the clean
runtime.
Get-IntergradeRuntimeHealth.ps1 provides a schema-validated health or
post-exit snapshot using shared access to the live log, including parser state,
runtime hashes, active legacy diagnostics, and the final 80 log lines.
Watch-IntergradeRuntime.ps1 adds a bounded exact-PID observer that automatically
records startup and exit snapshots without mutating the target process.

Historical generated control bindings used Home, Insert, and Page Up for
strength cycles. They are superseded by `hotkey-policy.md`: Page Down gates all
injected code, Page Up gates only the active experiment, and strength or quality
presets use separate keys. The staged development runtime keeps 3Dmigoto
render-target hunting on Ctrl-modified keys so both workflows remain usable.

## 3Dmigoto control contract

The generic 3Dmigoto adapter reads user controls from the injected
`IniParams` texture at `t120`. Intergrade reserves rows 100-102 for enable,
exposure, contrast, saturation, vibrance, gamma, tint, and tonemap selection.

The final game-specific replacement must confirm that `t120` is unused by the
original pass before adopting this default. If it conflicts, the 3Dmigoto
`ini_params` setting and `REDX11_INI_REGISTER` adapter macro move together.
