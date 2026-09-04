# Agent 2: Remake indirect-bounce integration candidate

## Visual target

The requested reference is the bottom comparison image: a clearly stronger
warm indirect-light response around the fixtures, wall, clothing, and face.
That appearance is not produced by making AO darker. The two effects remain
separate:

- Remake's native temporal SSAO continues to supply contact/crease visibility;
- the Agent 2 candidate adds RGB screen-space indirect radiance.

F2 ON is intentionally a visible `1.25` strong diagnostic so an A/B capture can
establish whether the new RGB bounce is present. It is not a promoted default.

## Verified Remake injection contract

`tools/Analyze-IntergradeR3DSSGIInjection.ps1` rechecks the original capture and
fails closed unless all of these statements remain true:

- local-light compute events 1028-1032 write resource `3a9ee32b`;
- the same resource is RT0 at reflection composite event 1096,
  `e2aa1c8cb39e0a55`;
- e2aa t0 is the verified world-normal buffer and t5 matches the active depth
  resource;
- that same depth resource is explicitly cleared to `0.0` at event 11, so the
  adapter rejects the captured reversed-Z clear value rather than forward-Z `1.0`;
- native e2aa proves t0 decodes as `normalize(encoded.xyz * 2 - 1)`, and the
  adapter uses that exact normal decoder;
- receiver depth uses an integer point fetch, trace neighbors and radiance keep
  R3D's UV-filtered path, and every A-trous source/depth/normal tap uses an
  integer fetch to avoid inventing geometry across silhouettes;
- e2aa b0 rows 40-43, 57, and 59 provide the native world-position, depth, and
  camera contract;
- event 1138 (`c473ab75b7519f7e`) is a temporal resolve with current scene,
  history, and motion inputs;
- the verified UI-safe final scene-color pass is later at event 1141.

The resulting order is therefore:

1. copy accumulated HDR lighting before e2aa;
2. trace half-resolution R3D-style horizon SSGI;
3. run donor-matching A-trous radii 16, 8, 4, and 2;
4. depth-aware upsample four filtered taps with a 5 cm reconstructed-depth
   tolerance, inverse-tonemap them, and multiply by Remake's native receiver
   diffuse term `t2.rgb * (1 - t1.x metallic)`;
5. add the resulting RGB bounce to the HDR lighting target;
6. retain native e2aa reflection/environment composition;
7. retain native temporal resolve and final post-processing.

## Offline F2 owner-integration pack

Canonical output:

`artifacts/agent2-r3d-ssgi-f2-owner-integration-pack`

The generator requires the exact current shared owner SHA-256
`EFA15E2A820D6CEE6A919AD3B14B736A8ED428B9C779693FF832479B2CC40ECD`.
It refuses owner drift or an existing F2 binding. The generated copy preserves
the shared F3 rolling A/B block and emits no F1 binding.

The six strict `/Ges /WX /O3` `ps_5_0` passes are:

- one horizon SSGI trace;
- four edge-aware A-trous passes;
- one additive HDR composite.

Because 3Dmigoto custom shaders restore render state but do not automatically
restore texture/SRV bindings, the injected owner block saves `ps-t110` through
`ps-t114` before the first pass and restores all five after the composite. Each
pass still nulls its temporary high-slot bindings before returning. The static
semantics test pins this behavior to the official 3Dmigoto backup/restore
example and fails if ordering or any slot drifts.

### Unreal distance-unit adapter

Epic's UE4 unit contract is 1 Unreal Unit = 1 centimeter:
https://dev.epicgames.com/documentation/unreal-engine/world-settings?application_version=4.27

The native e2aa reconstruction therefore remains in centimeters, but all R3D
distance-domain decisions convert by `0.01` before applying donor defaults.
This preserves the donor's 3 cm same-surface threshold, meter-scale
`1 / (1 + distanceSquared)` bounce falloff, and A-trous plane rejection. Using
the donor constants directly on centimeter-valued deltas would make indirect
light and filtering nearly vanish beyond a few centimeters.

`tools/Test-IntergradeR3DSSGIF2OwnerIntegrationPack.ps1` builds the pack twice,
compares all hashes, checks the key contract and pass order, and proves the
shared runtime owner did not change.

Each generated pack also includes `evidence/sampling-semantics.json`. That
report checks the native e2aa normal/material equations, the pinned R3D trace,
denoise, depth-aware upsample, inverse-tonemap, and diffuse-consumer paths, then
verifies the emitted DXBC uses the required `ld` versus filtered sample
instructions. Generation fails closed if any of those contracts drift.

### Prepared live-test boundary

The owner-integration pack remains a valid offline architecture fixture, but a
read-only preflight proved that it does **not** match the current live topology.
The live `RebirthEffectsDX11.ini` owner is absent; the exact owner survives as
`RebirthEffectsDX11.ini.disabled`, `UE4EffectsGenerated.ini` intentionally
contains no runtime binding, and active F1/F2/F3/e2aa claim counts are all zero.
Activating the owner-integration pack would also reactivate its old F3 system,
so live staging correctly refused before its write boundary.

`tools/Analyze-IntergradeR3DSSGILiveTopology.ps1` records that exact
fail-closed topology. The current live-test candidate is therefore generated
separately at:

`artifacts/agent2-r3d-ssgi-f2-standalone-pack`

It contains the same six compiled/verified shaders plus only
`Agent2R3DSSGITest.ini`. The standalone INI owns e2aa only for this
experiment, binds F2 exactly once, leaves F1 reserved, leaves F3 unbound, and
does not activate or copy any rolling-A/B owner logic.

`tools/Stage-IntergradeR3DSSGIF2Standalone.ps1` provides `Stage`,
`Status`, and `Restore` for that exact seven-file standalone pack. It does
not select or modify a live directory by default. An external target must be
an exact `End\Binaries\Win64\Mods` directory, requires
`-AllowExternalTarget`, and Stage additionally requires
`-AcknowledgeOfflineCandidate` plus PowerShell confirmation. It refuses any
active owner, F1/F2/F3/e2aa claim, Agent 2 filename collision, or drift in the
disabled-owner/generated-INI baseline fingerprints.

Stage copies only seven new Agent 2 files and separately backs up both
unmodified topology fingerprints as evidence. Status detects drift in any
payload or claim. Restore needs no candidate acknowledgment, refuses modified
payloads, verifies both evidence backups, and deletes only the exact seven
package hashes. The fixture-only suite covers Stage, Status, drift refusal,
Restore, `-WhatIf`, eight baseline/conflict cases, exact tree equality, and
before/after hashing of the real live Mods directory.

After an authorized Stage and before F10,
`tools/New-IntergradeR3DSSGIF2StandaloneReloadBaseline.ps1` binds the exact
seven-file stage receipt, game process, protected fingerprints, and current
`d3d11_log.txt` byte offset. After F10,
`tools/Get-IntergradeR3DSSGIF2StandaloneReloadStatus.ps1` requires:

- the F2 key and e2aa override sections to parse from
  `Agent2R3DSSGITest.ini`;
- all six CustomShader sections and all six `ps=<HLSL filename>` compile
  entries;
- a completed ShaderFixes reload;
- unchanged payload, topology, pack-manifest, and stage-receipt hashes;
- zero matched syntax, missing-file, HLSL-read, or custom-compile errors.

The passing classification is
`passed-parser-and-six-custom-HLSL-compile-clean`. It deliberately does not
claim correct pixels, acceptable motion, or acceptable GPU cost.

`artifacts/analysis/agent2-r3d-ssgi-live-evidence-ledger.json` defines nine
separate promotion gates: parser/compile, F2 OFF parity, strong warm-bounce
still, motion/disocclusion, screen edges/subviewport, AO/SSR invariants,
camera cuts, GPU timing, and balanced-strength selection. Every gate remains
pending. The current `1.25` value is recorded as a strong diagnostic, not a
balanced default.

`tools/Stage-IntergradeR3DSSGIF2OwnerIntegration.ps1` is retained and tested
for an owner-active topology, but it is not eligible for the current live
state.

## Promotion gates

The pack is deliberately marked `runtimeEligible=false` and `installed=false`.
Before installation it still needs:

- a frame capture proving the custom half-resolution resource formats and SRV/
  RTV transitions are accepted by the live 3Dmigoto build;
- a non-default viewport or resolution capture validating neighboring
  TEXCOORD0 ray reconstruction;
- still and motion A/B images, especially warm fixtures, faces, clothing,
  disocclusions, camera cuts, and screen edges;
- GPU timing for trace plus four denoise passes;
- confirmation that native AO, SSR, F3 rolling A/B, and unrelated controls are
  unchanged.

For the current standalone topology, “F3 unchanged” means F3 remains unbound;
the disabled historical owner is not activated.

No game or live runtime files were changed by this work.
