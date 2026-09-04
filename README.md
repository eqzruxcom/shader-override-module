# Shader Override Module (SOM)

A DirectX 11 graphics-injection framework for automatic shader-family matching,
rendering-pass discovery, controlled resource injection, and reusable graphics
upgrades. **Final Fantasy VII Remake Intergrade** is the proving adapter for an
eventual cross-game Unreal Engine effects-control framework.

Created by **EQZITARA**, developed with **OpenAI Codex**. Built on and inspired
by credited open-source graphics projects; see
[Authors and acknowledgements](AUTHORS.md), [third-party notices](THIRD_PARTY_NOTICES.md), and the preserved license files.

The project ports visual algorithms, not the Rebirth DX12 injector. Each game
adapter owns its shader hashes, resource bindings, coordinate conventions, and
pass integration.

For the concise live state, see [Project status](STATUS.md). For changes to the
framework itself, see [Changelog](CHANGELOG.md). The future Vulkan translation
track is documented separately in the [DXVK backend roadmap](docs/dxvk-vulkan-backend.md).

## Current status

Latest working-code record: [Known working code](docs/known-working-code.md).
**Contact shadows - Rebirth Mod - Code worked** is preserved separately, with
the original donor, native Remake shader references, and tested port. The user
reports it works in most cases; hard sword/cone shadow edges remain a refinement.
See [the current live experiment](docs/rebirth-contact-live-experiment.md).
Older control assignments below are historical and do not override that record.

- The five confirmed Remake contact-shadow shaders are generated as a guarded automatic 3+1+1 ShaderRegex family from tracked, canonical-hash-pinned inputs. Fresh generation is byte-identical across LF/CRLF worktrees, exact engine-equivalent matching accepts only five of 184 captured shaders, and deliberately widened T4 guards fail closed.
- The private temporal indirect-light candidate now matches native c473 moving/static reprojection and avoids finished-scene feedback. Live testing showed the visible-source angle cutoff remained mostly unchanged, so it was not graduated. An offline-verified Page Up diagnostic now isolates 4/8/16 angular trace slices while F2 remains the candidate master and F10/Page Down remain untouched. See [the angular-coverage diagnostic](docs/intergrade-ssgi-angular-coverage-diagnostic.md).

- Implementation order is now governed by the [Remake-first priorities](docs/remake-first-priorities.md): selected micro/contact-shadow and material-lighting techniques first, followed by a separate Remake-specific research backlog. The offline GT7 candidate is on hold; no live shader was changed during this review.
- Official 3Dmigoto and Rebirth Shader Injector sources are pinned locally.
- Rebirth's two v2.2.1 presets now have a deterministic, archive-hash-verified
  audit and portable family catalog. A second catalog preserves all 29
  header-complete Remake shaders in 10 verified DXBC families. Their
  hash-pinned relation ledger accounts for all 11 Rebirth donor families and
  promotes only the proven LocalLight-to-five-CS semantic adapter; the other
  ten remain explicitly unresolved rather than being matched by name. See the
  [portable shader-family catalogs](docs/portable-shader-family-catalogs.md).
  A third catalog promotes the bounded UE4 DXBC semantic descriptors into the
  same portable format. Its deterministic regional scan currently discovers
  one non-fast-path alias candidate (`EDA405F2D455D5C7-ps`), which is recorded
  as pending in a hash-pinned family-alias review ledger and remains ineligible
  for catalog mutation or runtime replacement. Reviewed acceptance now has a
  separate deterministic publisher that writes a validated derived catalog,
  updates structural and exact indexes atomically, and cannot publish the
  current pending entry.
- The target Intergrade executable is fingerprinted in the shader map.
- A Shader Model 5-compatible post-processing library and compile smoke test
  are present under `src/`.
- Official 3Dmigoto 1.3.16 x64 is installed in the target executable directory.
- Live logging confirms that 3Dmigoto wraps Intergrade's D3D11 device, immediate
  context, 3840x2160 swap chain, and shader creation.
- A full 3840x2160 gameplay capture records 1,175 draw/dispatch records and
  a complete `ShaderUsage.txt` map.
- Pixel shader `41f1bf8b79d01319` with vertex partner `6535922fb9c9160a`
  is the final presentation boundary. Skipping the whole pass freezes/removes
  the world and destabilizes UI, but a selective scene-only assembly edit now
  has a successful native reload and user-confirmed dimming with unchanged HUD.
  The first actual author `AdjustImage` port (-0.45 EV, gamma 1.15) is compiled
  and live-tested before native tone mapping. The user confirmed a brightness/
  tonal difference, not a preference or whole-game validation. Its Page Down
  comparison remains installed; older control assignments below describe
  historical stages, not necessarily the currently active overlay.
  See [the current author-port stage](docs/author-image-adjustments-port.md) and
  [the live observation](docs/author-image-adjustments-observation.md).
- Pixel shader `af6cd28a0108a18a` is the verified UI-safe scene-color hook; its
  neutral replacement compiles strictly and was visually matched to original.
  Grayscale, 0.5, and 0.75 linear saturation levels are live-verified.
- Pixel shader `a77b589dce5822d6` is the verified custom full-resolution temporal
  SSAO hook. Its output packs current AO, reprojected AO, temporal weight, and
  signed depth. Four single-channel probes are live-tested: X controls current
  AO, Y changes the AO outline around moving geometry, and Z/W produced no
  observable presentation change. The safe 0/25/50/75/100% strength matrix
  attenuates only X/Y toward neutral visibility and preserves Z/W metadata.
  Zero removes AO; 50% restores a smaller contribution concentrated on nearby
  geometry, confirming distance-weighted behavior. The 25/75% levels compile strictly.
- Pixel shader `b2bc6059f9a39c7f` is the verified screen-space
  reflection/specular trace-and-resolve hook. It reconstructs reflected rays from
  G-buffer geometry, marches hierarchical depth, reprojects through velocity,
  and samples two scene-color/history inputs. A live magenta probe selectively
  isolated reflective materials—including strong wet-ground and metal coverage
  with weaker hair participation—while leaving the HUD intact. Its safe
  0/25/50/75/100% matrix scales radiance RGB only and preserves hit/confidence
  alpha. Safe live 0% RGB with original alpha preserved produced no observable
  difference while reflections were enabled, so this scene is not suitable for
  strength validation and the control remains blocked from runtime promotion.
- Pixel shader `e2aa1c8cb39e0a55` is the verified immediately downstream
  reflection-environment/SSR composite. Draw 1096 consumes the exact render
  target handle written by `b2bc6059f9a39c7f` on draw 1095, and its dataflow
  implements `SSR.rgb + environment.rgb * (1 - SSR.alpha)` with additional
  material weighting. The 100% full replacement passes native original parity,
  and a downstream 0/25/50/75/100% SSR-radiance matrix compiles strictly. The
  tested view showed no visible 0%-to-100% difference, but a diagnostic 1600%
  variant produced angle-dependent white screen-edge glow plus sparse reflective/
  specular scene and character-model response; F3's 0% side removed both. This
  proves the control point while leaving normal-range 0/100 and 50% validation
  pending in a stronger SSR view, so runtime packaging remains blocked.
- Volumetric injection passes `cbc771ff8a37a0b3` and `c25d7f5229662b97`, plus
  scattering/history compute shader `ef7fe8d9c4e9ad15`, are mapped to the
  120x68x96 fog grid. A decompiled full replacement was rejected after native
  4K A/B evidence exposed a lamp-shaft mismatch. The safer original-first
  snapshot/post control compiles and passed native 4K neutral pixel parity;
  0%, 25%, and 50% scattering are live-verified and 75% is strict-compile
  verified. Extinction remains deliberately untouched.
- The UI-safe `af6cd28a0108a18a` pass has 0/25/50/75/100% linear scene-saturation
  controls. Grayscale, 50%, and 75% are live-verified and monotonic; numeric
  spacing is explicitly not claimed to be perceptually uniform.
- The fail-closed FF7 adapter now independently describes temporal volumetric
  scattering, UI-safe scene saturation, temporal SSAO, and screen-space
  reflections. Runtime promotion still fails closed on any incomplete live gate.
- `New-UE4GeneratedRuntime.ps1` now materializes the eligible adapter passes as
  a clean 13-file 3Dmigoto payload: twelve non-original shader levels and one
  generated INI. The blocked SSR composite remains manifest-only and cannot leak
  into the runtime. Clean official-runtime staging plus reversible, hash-verified
  live overlay install/rollback are covered by automated tests.
- The generated payload now passes its running-game parser and functional smoke
  gates: Home cycles temporal volume, Insert cycles scene saturation, and Page Up
  cycles packed AO through original/75/50/25/0%. All three controls were returned
  to original, the game remained responsive, and the generated-runtime smoke
  gate remains clean.
  Page Down is reserved. Render-target hunting remains available through the
  Ctrl-modified versions of Home, Insert, and Page Up.
- A game-neutral UE4/DX11 validation kit is generated under
  `artifacts/ue4-validation-capture-kit`. It contains official capture runtime
  files only—no FF7 hashes, Mods, or replacement shaders. The paired importer
  disassembles captured DXBC with FXC, runs the independent semantic matcher,
  and records local-only/non-redistributable evidence. Generic installation and
  exact rollback are hash-verified, refuse to modify a running target, and refuse
  to delete a changed generated-only DLL. A readiness checker verifies the
  executable fingerprint, 3Dmigoto device/swap-chain wrapping, parser health,
  and valid ShaderCache inventory.
- `New-UE4AdapterCandidateReport.ps1` binds an imported capture to its exact
  executable fingerprint and converts semantic matches into review-only
  candidates. Every report and every candidate is schema-locked to
  `runtimeEligible=false`; binding, replacement, control-pack, live-visual, and
  explicit eligibility-review gates remain missing by construction. Replacement
  artifacts, stale executable fingerprints, mismatched capture IDs, and evidence
  outside the captured assembly are rejected. Capture and install manifests now
  satisfy strict schemas before any consumer trusts them; duplicate identities,
  mismatched counts, inconsistent evidence, and non-canonical shader filenames
  fail closed. `New-UE4AdapterReviewWorkspace.ps1` then creates an immutable
  review ledger tied to the candidate-report hash, executable fingerprint, and
  captured artifacts. All five gates begin pending with null evidence, and both
  the workspace and every candidate remain schema-locked to
  `runtimeEligible=false`; `Assert-UE4AdapterReviewWorkspace.ps1` rejects source
  drift, duplicate candidates, omitted gates, pre-verified state, and changed
  executables. The complete offline suite passes 37/37, including the dynamic
  UI-safe scene-post generator, diagnostic runtime, and reload classifier.
  `Invoke-UE4ValidationCapturePipeline.ps1` performs import, semantic scan,
  executable binding, fail-closed candidate emission, and pending-review
  workspace creation in one command.
- After an abrupt game termination, the last 3Dmigoto log contained no parser or
  device error but exposed two still-active legacy diagnostic INIs, including an
  SSR A/B hook that ran the same custom shader on both sides. Those diagnostics
  are now disabled with hash-verified rollback evidence. A clean relaunch loaded
  only `UE4EffectsGenerated.ini`, produced zero parser warnings, and remained
  responsive. Future generated-overlay installs refuse active legacy diagnostics.
  Get-IntergradeRuntimeHealth.ps1 now snapshots the live process, locked log,
  parser state, loaded runtimes, file hashes, and the final 80 log lines; abrupt
  exits therefore retain actionable evidence instead of only disappearing.
  Watch-IntergradeRuntime.ps1 can attach a bounded observer to an exact PID and
  automatically write startup, exit, and summary evidence without changing the game.
- The exact installed files and rollback location are recorded in the ignored
  `artifacts/installed-intergrade-runtime.json` manifest.

## Design rule

Portable effects never hard-code a game's resource slots. Adapters translate
game resources into small effect interfaces, and replacement shaders provide
the final integration with the captured shader's original signature.

See [architecture](docs/architecture.md), [source manifest](docs/source-manifest.md),
[port backlog](docs/port-backlog.md), [UE4 regex strategy](docs/ue4-regex-strategy.md),
and the [universal UE4 roadmap](docs/universal-ue4-effects-roadmap.md).

## Shader compile check

Run the strict Shader Model 5 smoke suite with the Windows SDK compiler:

```powershell
.\tools\Test-Sm5Shaders.ps1
```

The command compiles the post-processing, lighting, runtime-settings, and UE4
  view-reconstruction libraries with warnings treated as errors. Compiled objects,
assembly listings, and `sm5-smoke-test-manifest.json` are written to `artifacts/`.

## Controlled live shader probes

Inspect the live configuration without changing it:

```powershell
.\tools\Set-IntergradeShaderProbe.ps1 -Action Status
```

Install one temporary pixel-shader skip probe, then press F10 in-game:

```powershell
.\tools\Set-IntergradeShaderProbe.ps1 -Action Install -ShaderHash af6cd28a0108a18a
```

Restore the exact pre-probe configuration, then press F10 again:

```powershell
.\tools\Set-IntergradeShaderProbe.ps1 -Action Restore
```

The command refuses to stack probes, records their hashes under
`backups/live-probe/`, and verifies that restoration removes the controlled
probe block.
