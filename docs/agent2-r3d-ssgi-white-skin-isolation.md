# R3D SSGI white-skin isolation

## Scope

This investigation is limited to the standalone F2 indirect-light experiment
on Remake pixel shader `e2aa1c8cb39e0a55`. The accepted contact-shadow files
are protected and must not be changed during these tests.

The indirect-light source is scene radiance plus depth, normals, material and
albedo data. The downstream bloom pair `56528003870d00b3-vs` /
`c58358673087aaf8-ps` is documented separately and is not the injection source.

## Confirmed evidence

- `00-true-noop` was visually verified by the user on 2026-09-02: F2 caused no
  visible change.
- Therefore the F2 binding, the `e2aa1c8cb39e0a55` override claim, and merely
  declaring the custom resources and shaders do not cause white character skin.
- `01-references-only` was visually verified by the user: F2 caused no visible
  change. Saving, referencing and restoring the high SRV slots is therefore not
  the white-skin trigger.
- `02-scene-copy-only` was visually verified by the user: F2 caused no visible
  change. Copying the currently bound scene-color target into the custom scene
  resource is therefore not the white-skin trigger.
- `03-trace-only` was visually verified by the user: F2 caused no visible
  change. The reload log also proves all six CustomShader sections parsed and
  all six HLSL files compiled with zero errors, live-file drift, or protected
  shadow drift. The trace allocation, state, draw and math are therefore not
  the white-skin trigger when run without denoise or composition.
- `04-trace-denoise` was visually verified by the user: F2 caused no visible
  change. Its reload parsed all six CustomShader sections and compiled all six
  HLSL files with zero errors or file drift. The trace plus all four denoise
  passes are therefore clean before composition.
- `05-zero-composite` failed visually: F2 changed Cloud's skin even though the
  composite pixel shader returned literal zero. Its reload log parsed and
  compiled all six passes without errors or protected-file drift. The first
  failing boundary is therefore the composite draw/state operation, not the
  trace, denoise, or indirect-lighting math.
- The first generated copies of variants 06 and 07 contained a misspelled
  `ResourceAgent2R3DSSGIScene` assignment. 3DMigoto correctly rejected it as
  an unrecognized entry. The generator now writes the declared
  `ResourceAgent2SSGIScene`, and both generator and regression test reject any
  operation that writes an undeclared resource.
- Corrected `06-zero-composite-no-depth` loaded with all six CustomShader
  sections and all six HLSL files, with zero errors or protected-file drift.
  It still changed Cloud's skin. Depth testing, depth writes, and stencil state
  are therefore not the cause.
- `07-zero-composite-no-draw` loaded with the same clean evidence and was
  visually identical when F2 toggled. The composite setup, resource bindings,
  and restoration are harmless without a draw. The proven trigger is the
  composite's inherited `draw = from_caller`, which reuses the game draw's
  geometry instead of executing an injector-owned fullscreen pass.
- A live key-ownership scan found F2 only in `Agent2R3DSSGITest.ini`, Page Down
  only in `ContactShadows.ini`, and F10 only in the native `d3dx.ini`
  `reload_fixes`/`reload_config` entries. No mod INI currently captures F10.
- The diagnostic composite HLSL returns literal `0.0` at the beginning of
  `main`; a complete pass chain that still changes the frame therefore points
  to command/resource/state behavior rather than intended indirect-light math.

## 3DMigoto state semantics

3DMigoto release v1.2.32 states that CustomShader sections save and restore all
render targets, depth targets, UAVs and viewports. The source also contains
explicit output-merger save/restore helpers. This weakens the hypothesis that
the final viewport or render target simply remains bound after a custom pass.
It does not rule out a resource alias/copy hazard, an invalid input/output use
during a pass, or a state category outside that documented set.

Primary references:

- <https://github.com/bo3b/3Dmigoto/releases>
- <https://github.com/bo3b/3Dmigoto/blob/master/util.cpp>
- <https://github.com/bo3b/3Dmigoto/wiki/Injecting-custom-shaders>
- <https://github.com/bo3b/3Dmigoto/wiki/Resource-Copying>

The official resource-copying documentation specifically supports render
targets as sources and explains that assignment into a custom resource defaults
to a real copy. Therefore `ResourceAgent2SSGIScene = copy o0` is a valid
3DMigoto operation in principle. The current live test determines whether this
particular game's bound target/format/lifetime makes that copy unsafe here.

## Ordered live tests

Each F2-on result should be visually identical to F2-off. Stop at the first
test that changes Cloud or any native lighting.

| Order | Variant | Commands added beyond the previous test | Status |
|---:|---|---|---|
| 0 | `00-true-noop` | none; branch cannot execute | pass, visually identical |
| 1 | `01-references-only` | resource save/reference/restore | pass, visually identical |
| 2 | `02-scene-copy-only` | `ResourceAgent2SSGIScene = copy o0` | pass, visually identical |
| 3 | `03-trace-only` | half-resolution trace CustomShader | pass, visually identical; clean runtime compile |
| 4 | `04-trace-denoise` | four A-trous denoise CustomShaders | pass, visually identical; clean runtime compile |
| 5 | `05-zero-composite` | zero-output additive composite | fail: Cloud's skin changes; clean runtime compile |
| 6 | `06-zero-composite-no-depth` | same zero output, with depth test/write and stencil explicitly disabled | fail: Cloud's skin changes; clean runtime compile |
| 7 | `07-zero-composite-no-draw` | bind and restore the composite state/resources, but issue no composite draw | pass, visually identical; clean runtime compile |

The generated variants and exact file hashes are in
`artifacts/agent2-r3d-ssgi-f2-isolation-matrix/manifest.json`. Regenerate them
with `tools/New-IntergradeR3DSSGIF2IsolationMatrix.ps1`.

## Injector-owned fullscreen follow-up

The next branch after the caller-draw tests is no longer a replacement of the
game object's geometry. `R3DSSGIFullscreen_vs.hlsl` builds an oversized
fullscreen triangle from `SV_VertexID`; the composite CustomShader explicitly
owns its VS, nulls HS/DS/GS, selects triangle-list topology, disables
depth/stencil, selects cull-none, and issues `draw = 3, 0`. This is the first
concrete step from shader replacement as a hook toward an injector-owned
graphics-effect pass.

The literal-zero diagnostic pack is generated at
`artifacts/agent2-r3d-ssgi-owned-fullscreen-zero-pack`. Both VS and PS compile
with the pinned FXC, and `tools/Test-IntergradeR3DSSGIOwnedFullscreenZeroPack.ps1`
verifies the closed eight-file pack, five preserved caller-draw passes, owned
composite draw, F2 ownership, and an unbound F10.

Live staging is deliberately gated. The guarded
`tools/Stage-IntergradeR3DSSGIOwnedFullscreenZero.ps1` requires an explicit
diagnostic acknowledgement, accepts only known isolation hashes, verifies all
payloads and the protected contact-shadow hashes, makes a complete workspace
backup, and rolls back automatically on a partial copy. Its paired
`tools/Restore-IntergradeR3DSSGIOwnedFullscreenZero.ps1` refuses to overwrite
drifted live files and restores the exact pre-stage set, including removal of
the newly introduced VS when appropriate. The disposable regression
`tools/Test-IntergradeR3DSSGIOwnedFullscreenStage.ps1` passed a complete
stage-and-exact-rollback cycle. Variant 07 proved the inherited caller draw is
the failure boundary, so the zero-output owned-fullscreen pack was staged live
with an atomic reload baseline. Its F10 reload and visual F2 result remain the
next runtime gate.

The owned-pass reload evidence is also prepared. After a future guarded stage,
`tools/New-IntergradeR3DSSGIOwnedFullscreenReloadBaseline.ps1` records the
exact process/log boundary, eight payload files, all protected contact-shadow
files, and a zero-claim scan for F10 across active Mods INIs. Its paired status
checker requires six CustomShader sections and seven HLSL entries: the six
pixel shaders plus the injector-owned vertex shader. The disposable regression
`tools/Test-IntergradeR3DSSGIOwnedFullscreenReloadStatus.ps1` passes pending,
clean-reload, compile-error rejection, and vertex-shader-drift rejection cases
without modifying the game.

If `03-trace-only` is the first visible failure, the offline refinement matrix
at `artifacts/agent2-r3d-ssgi-trace-refinement-matrix/manifest.json` separates
descriptor allocation, CustomShader entry/exit, render-state setup, a
literal-zero draw, and the real trace math. Generate and verify it with
`tools/New-IntergradeR3DSSGITraceRefinementMatrix.ps1` and
`tools/Test-IntergradeR3DSSGITraceRefinementMatrix.ps1`. Its manifest forbids
live deployment until the parent trace-only test is visually confirmed as the
first failure.

`tools/Set-IntergradeR3DSSGITraceRefinementVariant.ps1` enforces that same gate,
accepts only a known parent/refinement INI hash, verifies every shared shader
payload, preserves F10/Page Up/Page Down, and refuses unknown existing copies of
the diagnostic zero shader. Its disposable regression
`tools/Test-IntergradeR3DSSGITraceRefinementSwitcher.ps1` passed three fixture
transitions, the missing-confirmation refusal, and the deliberate-drift refusal
without changing the real game.

## Reload evidence

`tools/New-IntergradeR3DSSGIIsolationReloadBaseline.ps1` captures the exact
variant hash, log offset, running process identity, all seven live payload
files, and all six protected accepted-shadow files before F10.
`tools/Get-IntergradeR3DSSGIIsolationReloadStatus.ps1` then distinguishes
pending F10, parser/HLSL failure, file drift, process restart, and a clean
reload. It never binds or presses F10.

`tools/Test-IntergradeR3DSSGIIsolationReloadStatus.ps1` proves the checker
classifies a pending baseline and a clean six-shader reload, while rejecting a
synthetic custom-shader compile error and live INI drift. The fixture does not
modify the real game.

## Protected accepted contact-shadow hashes

| File | SHA-256 |
|---|---|
| `Mods/ContactShadows.ini` | `850925405F890D68E03F5E66073FA8529F1FD3618193A2E0C4CAFAC9A91333E2` |
| `ShaderFixes/08bb8764f1840179-cs.txt` | `3584A654C1E231ACB5C3E01CA50C8BC89F440B85320A97098B380706F76D1A83` |
| `ShaderFixes/0e97888f9a8767da-cs.txt` | `FB8C0FA229688D79497D726832ACB00F3763324AB09389BAD1A24352BAB1AA4A` |
| `ShaderFixes/5a9fbefe0ab6f815-cs.txt` | `421A8C026982B120AB9DDE629C529EA69C5E0B7E9A81FF30D1B4877B8DB773B0` |
| `ShaderFixes/62b33a2d1e505241-cs.txt` | `AB3FC967FA59ADE7E6B226B439E77DC81644ADFDA8404906C1F6EB8475A17876` |
| `ShaderFixes/c30cdc8365df9840-cs.txt` | `2B88112FF622CE972746334C19BED9F84A9C16CC17895992793FB4799A94F94E` |
