# FF7 Remake private temporal indirect-lighting candidate

Status: offline verified and live-tested, but not graduated; native moving/static reprojection matches retained c473 assembly, while the visible-source angle cutoff remains materially unchanged.

## Why this revision exists

The earlier indirect-lighting experiment copied the active finished-scene render target before the native lighting draw. That target could still contain the prior frame, including the injected result, so the effect fed itself back into later frames. The visible symptom was angle-dependent lighting that could become stuck until an F10 shader reload recreated the resource.

This candidate removes the finished-scene feedback path. It keeps only filtered indirect RGB and a depth-validity key in a private half-resolution `R16G16B16A16_FLOAT` history texture.

## Runtime contract

- `F10`: native shader reload only; unchanged.
- `F2`: this indirect-lighting candidate off/on. Off also clears its private history.
- `Page Up`: existing test-cycle ownership; unchanged.
- `Page Down`: existing graduated master ownership; unchanged.
- Native scene color is used only as the current-frame radiance source.
- The private history is cleared when first allocated, when recreated after a size change, and while F2 is off.
- History is rejected across depth discontinuities and invalid viewport reprojection.
- No native game shader replacement is shipped by this candidate.

## Wrapper extension

The DX11 ResourceCopy parser accepts `clear_on_create` only when it is combined with `copy_desc`. The destination is cleared only when a compatible resource is newly created or recreated; ordinary frame-to-frame copies do not clear it.

Example:

```ini
ResourceHistory = copy_desc clear_on_create ps-t2
```

## Verified offline gates

- Release x64 wrapper builds successfully through `StereovisionHacks.sln`.
- Rebuilt `d3d11.dll` is PE x64 and exports `D3D11CreateDevice` and `D3D11CreateDeviceAndSwapChain`.
- Eight SM5 shaders compile strictly.
- CPU behavior tests cover initialization, F2 reset, depth rejection, viewport rejection, bounded source retention, and feedback absence.
- The live-candidate stager is transaction tested against a disposable game tree, including drift rejection and byte-exact rollback.
- Real-game staging refuses to proceed unless its exact-file backup root is under `F:\Shader3Dmigoto\Backups`.

Run the gates from the repository root:

```powershell
.\tools\Test-IntergradeR3DSSGITemporalHistoryPack.ps1
.\tools\Test-IntergradeR3DSSGITemporalLiveStage.ps1
```

## Live result — static reprojection v2

The user tested the v2 candidate beside the known small light and reported the result as "mostly the same": illumination still appeared and disappeared with view angle. This means the corrected c473 static-surface fallback is technically required but was not the dominant cause of the visible cutoff. The v2 candidate is therefore not graduated.

This result narrows the next test to source sampling. The trace still uses four pixel-jittered angular slices; a small visible emitter can fall between those directions as the camera changes the sampling phase. The next controlled candidate must compare the unchanged four-slice trace against denser angular coverage while keeping temporal reprojection, denoise, composite strength, and scene placement fixed.

## Still pending

Use F2 only as the indirect-light master and Page Up only for the sparse/dense foreground test cycle. F10 remains native reload and Page Down remains the graduated master. Validate fixed-camera parity, slow orbit, fast pan, camera cuts, character/material stability, UI, resolution/FOV changes, contact/frustum regressions, and timing before promotion. If dense angular coverage still cuts out while the source remains on screen, instrument history validity next; if only off-screen sources fail, move to a bounded GI-only cache or native light/probe source.
