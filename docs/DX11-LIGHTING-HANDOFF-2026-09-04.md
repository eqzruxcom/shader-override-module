# DX11 lighting handoff — 2026-09-04

## Read this first

User is moving to a fresh chat because this conversation became too large and slow. Continue the existing work; do not restart shader hunting or change the objective. This is an unfinished checkpoint, not a working lighting release.

Work only in `C:\Users\EQZITARA\Documents\ChatGPT\FF7 Rebirth mod\artifacts\worktrees\dx11-main`, branch `main`. Remote: https://github.com/eqzruxcom/shader-override-module.git. The root checkout is shared with a separate DX9 agent. Inspect status before edits and coordinate any shared runtime INI changes.

## User's chosen direction

Port the Rebirth ShaderInjector Maximum Quality GTVB indirect lighting/AO implementation into Remake DX11 as faithfully as possible. User explicitly accepts ugly results to learn implementation. Preserve the donor algorithm, constants and integration order; document unavoidable resource/API adaptations. Do not substitute the earlier R3D algorithm or tune away discrepancies before proving the port.

Full goal remains: guarded automatic ShaderRegex families for the five confirmed contact shaders and left-frustum fix, exact offline matching/assembly/equivalence/exception rejection before deployment, then verified indirect lighting and remaining shadow/light coverage. Prior contact milestone is `aa44e19`; inspect its evidence rather than assuming all current requirements are complete.

## Current state

Three new files implement a first compute producer:

- `src/ThirdParty/ShaderInjector/RebirthGTVB.hlsl`
- `src/ThirdParty/ShaderInjector/RebirthGTVBRandom.hlsl`
- `src/Adapters/FF7RemakeIntergrade/RebirthGTVBRemake_cs.hlsl`

FXC compiled the adapter successfully as `cs_5_0`, optimized, strict syntax, entry `main`. Disassembly confirms t0–t3, u0/u1, 8x8x1 threads and countbits. Output: `artifacts/tests/rebirth-gtvb-sm5/RebirthGTVBRemake_cs.cso` (12692 bytes) and `.asm`. These ignored build artifacts are local only.

Command from the isolated worktree:

```powershell
& 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe' /nologo /T cs_5_0 /E main /Ges /O3 /I src/ThirdParty/ShaderInjector /Fo artifacts/tests/rebirth-gtvb-sm5/RebirthGTVBRemake_cs.cso /Fc artifacts/tests/rebirth-gtvb-sm5/RebirthGTVBRemake_cs.asm src/Adapters/FF7RemakeIntergrade/RebirthGTVBRemake_cs.hlsl
```

Known warning X3557: one-iteration outer loop is forced to unroll. /WX fails on this warning. Removing the donor [loop] hint did not eliminate the warning; current file omits it. A future verifier must reject unexpected warnings and errors, not simply suppress all warnings. Compilation alone does not prove runtime bindings or equivalence.

No new GTVB INI, consumer, runtime deployment or live test exists yet. No automated GTVB contract test has been written. Do not describe the current live game as running these files. Existing experimental runtime state must be inspected before changing it.

## Donor and provenance

David Matos / frostbone25 ShaderInjector, MIT. Existing `src/ThirdParty/ShaderInjector/LICENSE.txt` retains the notice.

Reference commit: `bab25809b375f028b7c0fb603d804426f38c9b8e`.

Actual donor used is the locally extracted Maximum 2.2.1 package. Do not assume package and repository commit are byte-identical without comparison.

Archive: `F:\New folder\package\New folder\New folder\Shader Injector v2.2.1 (Maximum Quality Preset) 2153 2.2.1 2026-07-31T16-21Z sMpd9F7eU.zip`

Recorded archive SHA256: `CED1790992265E203E0DB418203881D5570A58C5AF0663E5F50C05A7996CD119`.

Extracted include directory: `C:\Users\EQZITARA\AppData\Local\Temp\som-rebirth-max-2.2.1\shader-injector-2-2-1-maximum-dood\ShaderInjector\ModifiedShaders\Includes`.

`ComputeShaderPass_ReflectionEnvironment.hlsl`: recorded SHA256 `CEBA077018F2ACBD48A86AEF82CD603B8F219C71E501947AE3E88129A715164B`. ComputeGTVBGI lines 1574–1800 normalized to LF plus trailing LF: `2131C8876E64D5D13E31E932A7352C4E6C7F7FD5565DCCF39465845E236F21B8`.

Package `LibraryRandom.hlsl` SHA256: `115462DA04A9988F37099EB6D6A7AFEAF19FFC4F2D1CF00CE24B7AF3A1967F65`.

The new random file refers to `gtvb-provenance.json`, but that JSON has NOT been created. Complete it and a source comparison before claiming exact fidelity. Current comments express intended fidelity, not completed proof.

Maximum settings confirmed from package: one ray/slice, two sides, 16 steps, width 512 pixels, thickness 75, normal bias .0005 (hair .1), animated Jenkins hash noise, 32-bit angular visibility masks. Checkerboard and basic quad denoise are disabled. No dedicated history/denoiser; donor relies on game TAA.

Output is GI.rgb * inverse pre-exposure; AO visibility in alpha; fallback = 1 - resolved GI angular coverage.

Donor consumer order: GTVB AO replaces screen AO; apply material AO and character adjustments; GTAO multibounce to native diffuse/specular; diffuse *= fallback; diffuse += max(.0002, GI * boost), boost PI except hair/eye/preintegrated skin use 1; then material diffuse/specular lobes; pre-exposure; final additive output. Read full donor main to preserve other active settings. Merely adding GI to final diffuse registers is not equivalent to adding before the material lobe.

## Remake mapping and remaining risks

Target reflection/ambient PS: `e2aa1c8cb39e0a55`, captured event 1096. Fixture: `src/Tests/Fixtures/UE4Semantic/e2aa1c8cb39e0a55-ps.asm`.

External decompile: `F:\Shader3Dmigoto\snapshot-20260831-114015-080\project\artifacts\captured-shaders\e2aa1c8cb39e0a55-ps\e2aa1c8cb39e0a55-ps_decompiled.txt`.

Native inputs: t0 normal, t1 material/shading ID, t2 base color, t5 depth, t6 screen AO, t11 SSR-like. CB0 has 154 float4s. Adapter uses its own compact t0 direct-light snapshot, t1 normal, t2 depth, t3 material mapping.

View fields: [57] depth conversion; [40..43] world reconstruction; [59].xyz camera; [121].xy view rect minimum; [122].xy view size; [126] buffer size/inverse; [128].x/y pre-exposure/inverse; [139].w frame index bits. Verify these against captures. Native fixture evidence for [122] includes `6edf7b59fdaa4548-ps.asm` and `53fca3b84eeecea5-ps.asm` in local validation captures.

Two corrections made offline: use actual [122] view size, and add .5 pixel center exactly once. These were bugs in the new adapter; they are not proven causes of previous live angle dependence.

Adapter uses camera-relative world coordinates instead of donor view-space rotation. Angular operations should be invariant under a rigid rotation, but projection/ray depth normalization and numerical equivalence still require proof. Also audit shading-model IDs, normal decoding, sky depth threshold, exposure and nonzero view rectangles. Current sky threshold 1e-7 differs from donor >0. Do not silently declare these exact.

Native final registers: r7.xyw diffuse, r6.xyz specular; final add and exposure. Exact earlier diffuse irradiance/material-lobe splice is unresolved.

## Next implementation steps

1. Pin package source provenance, compare extracted core and compatibility substitutions, and validate adapter coordinates against native reconstruction. Fix only demonstrated discrepancies.
2. Build offline pack/verifier: private direct-light snapshot, explicit compute dispatch, private GI/AO and fallback outputs, exact consumer integration. Include rejection tests for wrong shaders/resources. Keep the full 1:1 target; debug output is only a diagnostic milestone.
3. Candidate hook is BEFORE e2aa, where current-frame direct/local lighting is believed available. Prove contents and copy timing in a capture. Save required PS inputs/CB, copy o0 to private SRV, unbind conflicting outputs, dispatch CS, restore state, let native consumer use results. Never let the source contain previous injected output.
4. `draw = from_caller` at a PS hook replays a draw; it cannot launch the intended compute. Use explicit dispatch groups derived from captured view dimensions. Capture dimensions before unbinding RT; verify expression evaluation. Review `docs/3dmigoto-compute-wrapper-contract.md` and fork CommandList.cpp.
5. Explicitly preserve/restore SRV slots (e.g. t110/t111) if used. Do not assume CustomShader restores all SRV bindings. Cross-stage CB references must be verified.
6. Only after offline gates, backup exact current live files and install diagnostic. Verify execution/output before final compositing. Test motion, multiple angles, resolutions and FOV, skin/material correctness, no feedback/history freeze. Record failures honestly.

## Prior findings / avoid repeating

Latest previous commit `458af4a`: captured native red-beacon lists maxed at 16 of 64, not saturation. `d9c8fc2`/`3bf3923` contain capture/correlation work. This disproves saturation for sampled captures, not every scene.

Old R3D experiments (`R3DSSGITraceE2AA_ps.hlsl`, later c473 path) are a different algorithm. Earlier self-feedback froze light until F10. Preserve that evidence; do not reuse its source timing blindly. User observed both white skin and angle-dependent contributions; screenshots alone do not prove correct GI.

## Keys / interaction / ownership

F10 is shader reload only; never repurpose it. Page Up is lighting test cycle; Page Down is the graduated master according to earlier contract. F1–F3 originated with the other agent; current indirect experiment was using F2. Audit active INIs and ownership before binding F2. Preserve contact/frustum/clothing baselines and exact backups; do not replace them casually.

User authorized game control/testing and asked for clear completion indication. Latest screenshot preference was foreground, short settling delay, screenshot, prompt when done; older background PrintWindow captures were unreliable. Inspect existing AHK/IPC helpers and current computer-use instructions rather than invent commands. Do not touch Batman or DXVK; separate agent owns DX9. No game action is needed to finish this handoff.

## Tool friction

Windows sandbox process/patch helper often fails with `apply deny-read ACLs`; approved escalated commands take about 25–30 seconds. Batch independent reads. apply_patch additions worked; updates failed. The previous turn used temporary root *.patch files then escalated git apply. They are ignored scratch files, not release content. Avoid spending a turn retrying equivalent failed operations.

## Completion criterion

This checkpoint proves an SM5 compilation only. Goal stays active. Finish faithful integration and runtime validation before declaring lighting complete or universal template ready.
