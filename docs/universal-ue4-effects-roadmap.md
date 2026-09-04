# Universal UE4 effects-control roadmap

Project-wide A/B controls are governed by
[`hotkey-policy.md`](hotkey-policy.md): Page Down makes every generated shader
execute or skip its injected blocks, and Page Up gates only the feature
currently under development inside that master branch.
The obsolete Page Down post/fog-like comparison was removed from the live
runtime on 2026-08-31. Page Down is intentionally unbound until the per-shader
master conditions are generated.

## Goal

Finish the FF7 Remake implementation first, confirm its shader-family coverage
in additional game areas, and then turn the proven transformations into the
Universal Unreal Engine Shader Changer. Exact hashes are bootstrap evidence;
shared pass implementations plus structural family recognition and generated
game/version adapters are the scalable deliverable.

Shader Injector v2.2.1 for FF7 Rebirth demonstrates the required organization:
shared pass HLSL, tiny version entry points, structural fingerprints, compiled
runtime artifacts, and presets that change configuration without duplicating
the shader corpus. Our DX11 implementation must reach the same architecture
through 3Dmigoto ShaderRegex/family descriptors and generated replacements.

The official injector source study is recorded in
[`shader-injector-family-matching-study.md`](shader-injector-family-matching-study.md).
It confirms a direct-hash fast path plus structural/semantic discovery,
ambiguity rejection, and learned aliases. The exact preset delta is recorded
in [`shader-injector-v2.2.1-preset-diff.md`](shader-injector-v2.2.1-preset-diff.md).
The verified donor pass inventory and Rebirth-to-Remake coverage map are in
[`rebirth-v2.2.1-pass-coverage-matrix.md`](rebirth-v2.2.1-pass-coverage-matrix.md).
That matrix is authoritative for the distinction between related engine
semantics and stage-specific runtime matching.

Target renderer order is UE4/DX11, UE3/DX11, then UE3/DX9. The recognition and
transformation model is shared; DX11 and DX9 capture, bytecode, binding, and
injection layers remain explicit backends.

Prefer a UE3 title with comparable DX11 and DX9 builds for the transition
between those two backends. A paired release is a cross-backend fixture: the
DX11 build supplies SM5/3Dmigoto identities and richer reflection evidence,
while the DX9 build supplies the corresponding SM3 token stream, compiler
comments, constants, samplers, and draw state. Promote a shared semantic family
only after the pair preserves the same effect intent and each backend retains
its own exact interface and resource contract. This is stronger evidence than
developing unrelated DX11 and DX9 games independently.

Use Final Fantasy VII Remake Intergrade as the first development adapter for a
cross-game Unreal Engine shader changer. The user prioritizes older Unreal games,
not newer games alone. Retain the UE4 work below as one engine/API track.

Remake uses a modified UE4 renderer. It is the active stress-test adapter, not
the canonical source for normal UE4 shader families. After each transformation
works in Remake, stock or near-stock UE4/DX11 captures must establish the base
descriptor; Remake-specific differences remain explicit adapter overrides.

Latest corrected order (2026-08-31): finish the selected effects in one Remake
area, preserve working implementations, move to another area and reconfirm,
then build the universal runtime shader-family script. Contact-shadow hard edges
and the camera-dependent screen-edge artifact are the immediate priority.
See [known-working code and current requirements](known-working-code.md).

Older-game exploration includes DX9-to-DX11 translation alongside native DX9
tooling. [dgVoodoo2's official documentation](https://dgvoodoo2.dege.freeweb.hu/dgVoodoo2/ReadmeGeneral/)
lists D3D9 input and D3D11/12 output; it is a candidate to investigate, not a
tested integration here. Translation and injection compatibility, resource
availability, generated shader structure, architecture, and overhead need testing.
Do not assume translated shaders have UE4 layouts or that translation alone
implements the effects. No wrapper installation is authorized by this note.

The older stock-UE4 proof sequence below remains useful for that track; it is
not a requirement to defer older UE games until all UE4 targets are complete.

## Evidence so far

- The UE4 Universal Fix 2 demonstrates that instruction-pattern regexes can
  recognize related DXBC shaders across UE4 games and engine revisions.
- Its package and FF7 contain the exact bytecode hash `18305e60b4378edb` for a
  vignette pass, proving that some UE4 shaders are reused byte-for-byte.
- The same fix labels fog matching as insufficiently universal and disables it
  by default. FF7's custom volumetric pipeline likewise needs an adapter.
- FF7 therefore exposes both sides of the intended design: a reusable UE4 core
  and explicit game/fork exceptions.
- Six independent semantic descriptors currently scan 20 captured FF7 shader
  assemblies and produce seven expected matches with zero regex timeouts and no
  licensed-regex runtime dependency. The set now covers volumetric scattering,
  scene color, temporal SSAO, SSR trace/resolve, and the downstream
  reflection-environment/SSR composite.
- The fail-closed FF7 binding input configures four passes. The generated adapter
  emits three live-eligible controls (temporal volumetric scattering, UI-safe
  scene saturation, and packed temporal SSAO) and blocks downstream SSR strength.
  The strict-compiled 100% composite replacement passes native-resolution parity
  against F9/original, and a dedicated downstream radiance mask confirms a real
  screen-space reflection contribution without conflating it with reflection-environment
  fallback. A 0%-to-100% A/B was visually inconclusive in the tested view, while a
  diagnostic-only 0%-to-1600% A/B produced angle-dependent screen-edge glow and sparse
  reflective/specular scene and character-model response that disappeared on the 0%
  side. Normal-range 0/100 and 50% validation therefore moves to a stronger SSR view.
  Negative tests
  reject stale descriptor hashes, mismatched temporal weights, licensed-input
  reports, duplicate pass bindings, wrong scene output slots, swapped SSR/composite
  inputs, and premature runtime eligibility.
- The generated-runtime layer now turns the eligible adapter passes into a clean,
  installable 3Dmigoto payload rather than stopping at metadata. It emits three
  controls, twelve non-original HLSL levels, and one generated INI (13 files),
  while carrying the blocked SSR composite in the manifest without emitting its
  hash. Clean official-runtime staging and reversible overlay install/rollback
  are automated and hash-verified. The running-game F10 parser gate passes with
  zero errors, all eligible hashes present, and the blocked SSR hash excluded.
  Home/Insert/Page Up functional cycling is user-confirmed for temporal volume,
  scene saturation, and packed AO; all controls were restored to original and
  the game remained responsive. The next portability gate is a second stock
  UE4/DX11/SM5 adapter, not more FF7-only runtime plumbing.
- Installed-game discovery is reproducible through
  `tools/Find-UE4ValidationCandidates.ps1` and
  `artifacts/ue4-validation-candidates.json`. The current machine contains no
  additional DX11/SM5 Unreal validation candidate: FF7 is the proof adapter,
  STAR WARS Zero Company is explicitly excluded as SM6-only, and the other
  discovered installations contain no Unreal evidence. An Unreal directory
  without shader-model evidence fails closed instead of being called compatible.
- The second-game workflow is now packaged independently of FF7. The neutral
  capture kit contains official 3Dmigoto runtime files and capture settings only;
  automated tests reject any FF7 hash, Mods directory, or replacement shader.
  Import-UE4ValidationCapture.ps1 accepts 3Dmigoto 16-hex DXBC binaries,
  disassembles them with Microsoft FXC, runs all semantic descriptors, and marks
  the resulting evidence local-only and non-redistributable. Generic
  install/rollback now backs up every overwritten runtime
  file, fingerprints the target executable, refuses deployment or rollback while
  the game is running, and refuses deletion of modified generated-only files.
  Capture readiness fails closed until the 3Dmigoto D3D11 device and swap-chain
  wrappers, parser health, and valid 16-hex ShaderCache binaries are all proven.
  Imported semantic matches now flow through a separate adapter-candidate report:
  it fingerprints the exact executable and all source manifests, accepts only
  capture-owned assembly/binary evidence, and schema-locks both the report and
  each candidate to `runtimeEligible=false`. Five later gates—binding contract,
  replacement shader, control pack, live visual validation, and explicit runtime
  eligibility review—cannot be inferred from a scan. A separate adapter-review
  workspace now fingerprints the candidate report, executable, and captured
  artifacts; all five gates initialize pending with null evidence and cannot be
  promoted by changing a boolean. Its verifier rejects source drift, duplicates,
  omissions, altered executable fingerprints, and pre-verified state.
  Imported-capture and installed-kit provenance now have strict schemas plus
  count, path, identity, lowercase-canonicalization, and duplicate-evidence
  assertions. Negative tests cover each fail-closed boundary, and the complete
  offline suite passes 37/37, including the dynamic UI-safe scene-post
  generator, diagnostic runtime, and reload classifier.
  Obtaining a second stock UE4/DX11/SM5 capture is now the remaining external
  portability gate.
- A license-safe scan of the archived Universal Fix shader corpus is recorded in
  `artifacts/ue4-semantic-universal-fix-corpus.json`. Replacement artifacts are
  explicitly excluded: 17 captured SM5 assemblies were checked against all six
  independent descriptors with one structural match and zero timeouts. Archived
  compute shader `b643d8fed67b4630` matches the temporal volumetric-scattering
  descriptor after its numeric history weight was correctly made adapter-specific;
  FF7 specificity remains exactly one match among 184 cached shaders. Independent
  contract analysis recovers FF7's fixed 0.85 history / 0.15 current blend, while
  the archived match uses a register-derived dynamic coefficient (including a
  recovered 0.7 scale) and therefore fails closed for FF7-style steady-state
  compensation. This is
  positive cross-corpus semantic evidence, but unknown game provenance and absent
  resource-flow/live validation mean it is not yet a second adapter. Targeted
  captures from two suitable stock UE4/SM5 games are still required.

## Architecture

1. **Semantic pass descriptors** record shader stage, DXBC instruction motifs,
   resource dimensions, slots, dispatch/draw shape, and upstream/downstream flow.
2. **Pattern detectors** match normalized disassembly and report confidence plus
   every matched instruction range; fixed hashes are optional fast paths.
3. **Adapter candidates** retain scan evidence but are never runtime eligible;
   they enumerate the binding, replacement, control-pack, live, and review gates
   still required for that exact executable.
4. **Adapter review workspaces** bind those candidates to immutable provenance
   and initialize every human/evidence gate pending; they are ledgers, not
   promotion artifacts.
5. **Generated adapters** map a validated game's resources into small stable
   effect interfaces without embedding game slots in portable effect code.
6. **Independent controls** implement neutral bypasses and adjustable behavior.
   Original-first post controls are preferred when a safe read/write boundary
   exists; full replacements require stronger equivalence proof.
7. **Validation gates** require strict SM5 compilation, no unexpected regex
   matches, neutral frame parity, visible non-neutral behavior, temporal and
   resolution checks, and rollback evidence.

## Proof sequence

1. Finish and validate the FF7 controls.
2. Convert each verified FF7 hook into a semantic descriptor.
3. Continue testing detectors against locally archived UE4 shader corpora without
   copying licensed implementations. The first replacement-filtered corpus run
   is reproducible and contains one independently detected temporal-volumetric
   match; provenance and adapter validation remain open.
4. Generate adapters for at least two additional, comparatively stock UE4 games.
   The FF7 adapter generator and binding schema support both verified integration
   types; additional-game captures and bindings remain required before
   portability can be claimed. The current installed-game survey proves that a
   suitable local SM5 candidate still has to be supplied or installed; an
   SM6-only title is not a substitute for the DX11 validation gate.
5. Classify failures as detector gaps, engine-version variants, or game-specific
   forks; add narrow exceptions without weakening neutral validation.
6. Package the universal framework only after the additional-game evidence is
   reproducible. Revisit HDR compatibility after SDR portability is established.

## Licensing boundary

The UE4 Universal Fix 2 is a research reference with restrictive redistribution
and derivative-publication terms. Its downloaded archive remains ignored local
input. This project may learn from its high-level pattern-matching approach but
must not copy or redistribute its shaders, regexes, scripts, or package contents.
