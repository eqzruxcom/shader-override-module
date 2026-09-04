# FF7 Remake private temporal indirect-lighting candidate

Status: offline verified and installed for controlled live validation; native moving/static reprojection now matched from retained c473 assembly.

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

## Still pending

The retained c473 assembly proves both paths: nonzero t4.zx uses the decoded motion vector, while the zero sentinel uses depth plus CB1[114..117] to reproject static surfaces. Controlled live validation must now confirm the corrected wall persistence, disocclusion behavior, resolution changes, F2 off/on resets, and regressions for Cloud, emissive lights, contact shadows, UI, and native F10 reload behavior. The candidate remains isolated on F2 until those checks pass.
