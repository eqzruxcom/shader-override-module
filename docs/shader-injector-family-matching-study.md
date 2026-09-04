# Shader Injector family-matching study

## Source and scope

This note records behavior verified in the official open-source Shader Injector
repository at commit `bab25809b375f028b7c0fb603d804426f38c9b8e`. The repository
is MIT licensed. The inspected implementation is a DirectX 12/DXIL injector;
its matching architecture is precedent for this project, but its DXIL and PSO
code is not directly reusable as a DirectX 11 or DirectX 9 backend.

Local source:

`reference/external/ShaderInjector-source-official`

## What it actually does

The injector combines exact identity, structural analysis, learned aliases,
and shared replacement packages. It is not merely a directory of manually
listed shader hashes.

The runtime path is:

1. Capture every shader stage from graphics and stream pipeline-state objects.
2. Prefer a known shader bytecode hash mapped to a `ModifiedShader` package.
3. If analysis discovery is enabled, reject candidates with the wrong stage or
   an implausible bytecode size before doing expensive work.
4. Reflect the candidate and build a portable reflection identity from shader
   stage/model, input and output interfaces, resource bindings, constant-buffer
   layouts, and execution properties.
5. Use the reflection identity as an exact gate before disassembly.
6. Disassemble the shader, normalize unstable SSA and metadata identifiers,
   discard instruction ordering by sorting a unique instruction set, and hash
   that normalized semantic set.
7. Form a cross-version identity from reflection identity, entry function, and
   semantic instruction-set hash.
8. Accept an exact cross-version identity when it identifies one target.
9. Otherwise calculate a weighted fuzzy score. The default minimum is `0.90`;
   the best result must lead the second-best result by at least `0.02`.
10. Refuse ambiguous matches instead of guessing.
11. Create a per-game `ShaderTarget`, compile the shared HLSL package with DXC,
    rebuild the affected replacement PSO, and persist the newly discovered
    bytecode hash as an alias.

The ordinary replacement lookup remains layered and cheap: known shader hash
and alias first, then captured bytecode analysis. Cached PSO hashes/content and
pipeline templates provide additional DX12-specific identity paths.

## Exact fingerprints and safeguards

The portable reflection identity includes:

- shader stage and shader-model version;
- input, output, and patch-constant parameters;
- resource type, bind point/count, flags, return type, dimension, sample or
  stride value, and register space;
- constant-buffer sizes, variable offsets/sizes, and recursive type layouts;
- geometry, tessellation, compute group, feature-level, and sample-frequency
  execution properties.

Resource names and range IDs are deliberately excluded from the strict
resource fingerprint because a compiler can rewrite them.

The semantic instruction fingerprint normalizes DXIL disassembly by removing
assignment IDs and metadata attachments, replacing SSA and metadata numbers,
normalizing labels and whitespace, sorting, and deduplicating instructions.
This is intentionally tolerant of compiler reordering. Instruction counts and
categories remain available to the fuzzy scorer.

Additional safeguards are:

- replacement discovery requires bytecode size within 5% when a reference
  length is known;
- reflection identity must match exactly before a fuzzy semantic candidate is
  considered;
- shader stage is always explicit;
- accepted aliases are persisted, so analysis is a discovery cost rather than
  a permanent per-draw cost;
- queued analysis is bounded, prioritized, and handled by background workers;
- ambiguous exact identities and close fuzzy candidates are rejected.

This directly validates the project rule: identify a shader family once,
verify it, and then apply the matching transformation to all compatible
variants instead of manually maintaining thousands of regional hashes.

## What transfers to our universal project

These concepts should be common to every backend:

- stable logical package IDs such as contact projection, character shadow,
  reflection environment, SampleGI, and final post-process;
- stage-aware direct-hash lookup followed by structural discovery;
- a normalized family descriptor rather than filenames as authority;
- strict interface and resource gates before semantic similarity;
- explicit thresholds, best-versus-second-best ambiguity rejection, and a
  quarantine path for unmatched or uncertain shaders;
- learned aliases after a match is confirmed;
- shared effect math and controls, with small backend/game adapters;
- generated runtime output and a permanent evidence manifest;
- Page Down as an injected-code master branch and Page Up as the current
  experiment branch inside each generated replacement.

The donor also confirms that shared HLSL source and deployment targets are
separate objects. One pass implementation can own multiple version-specific
targets and compiled blobs.

## What must remain backend-specific

### UE4 / DirectX 11

- Intercept D3D11 shader creation and binding, or use 3Dmigoto as the initial
  interception and replacement backend.
- Analyze DXBC with D3D11 reflection and DXBC disassembly/token data.
- Compile SM5 replacements with the DXBC compiler path.
- Replace individual shader objects; D3D11 does not expose the DX12 PSO and
  root-signature model used by the donor.
- Preserve the exact constant-buffer, SRV, UAV, sampler, and signature contract
  required by each Remake family.

### UE3 / DirectX 11

- Reuse the DX11 capture, DXBC analysis, compiler, and injection backend.
- Supply UE3-specific family descriptors and effect adapters. This is the first
  proof that recognition is not coupled to UE4 naming or GBuffer conventions.
- Do not assume a UE4 family identity transfers unchanged merely because the
  API and bytecode format match.

### UE3 / DirectX 9

- Intercept D3D9 vertex and pixel shader creation/binding and replace D3D9
  shader handles.
- Analyze shader-model 2/3 token streams and assembly semantics rather than
  DXBC/DXIL reflection identities.
- Build stage, declaration, constant/register use, sampler use, opcode-family,
  control-flow, and normalized-instruction fingerprints appropriate to D3D9.
- Compile or assemble matching `vs_2_0`/`vs_3_0` and `ps_2_0`/`ps_3_0`
  replacements with a DX9-compatible compiler toolchain.
- Share effect intent and math where the shader model permits it, but generate
  separate API/model source wrappers.

The shared product is therefore one recognition and transformation system with
DX11 and DX9 analyzers/injectors. It is not one binary parser or one compiled
shader used unchanged across all three targets.

## Implementation consequence for Remake

The current Remake hashes are training and verification samples. They should
be retained with headers and classifications, then converted into one or more
family descriptors. A family is accepted only after:

1. its original pass role is confirmed;
2. its interface/resource contract is recorded;
3. its transformation is proven in the current area;
4. new regional variants match without false positives;
5. at least one additional area reconfirms the rule.

Only then should the descriptor become a universal UE4/DX11 rule. Dynamic
character, hair/face, clothing, and static-world shadow families must remain
separately classifiable even when they share a high-level effect.

Remake is built on a modified UE4 renderer. Its samples prove that our matcher,
patcher, and effect code can survive a difficult game-specific renderer; they
do not by themselves prove a stock UE4 family. The universal extraction step
must separate:

- stock UE4/DX11 invariants confirmed in ordinary UE4 games;
- common-but-optional UE4 permutations;
- Remake-specific alterations and bindings;
- Rebirth donor behavior, which is reference evidence from a different game
  and engine revision.

This prevents the first and least-standard adapter from overfitting the whole
project.

## Implemented catalog boundary

The portable catalog and explicit relation ledger described in
`portable-shader-family-catalogs.md` now encode this distinction mechanically.
The Rebirth catalog preserves DXIL structural/cross-version identities; the
Remake catalog preserves exact stage-aware DXBC identities and all verified
family splits. Only the working LocalLight semantic relation is promoted. A
test fails if either generated catalog changes without relation review, if a
donor family is omitted or decided twice, or if a relation names a missing
family.
