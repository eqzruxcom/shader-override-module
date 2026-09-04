# Fallout: New Vegas DX9/DLSS5 transport

State: **offline transport and full-neural candidate tooling built; live game validation pending**

This is the first target on the `DX9` branch. It is deliberately separate from
the paused FF7/D3D11 DXVK shader-identity backend in Issue #3. No FF7 adapter,
native D3D11 runtime, or accepted shader family is changed by this work.

## First boundary

The first build proves only this path:

```text
FalloutNV.exe (x86 D3D9)
  -> DXVK 3.0.2 x86
  -> Vulkan x86
  -> local VK_LAYER_reshade + VK_LAYER_feed_vk
  -> dlss5-feed.addon32
  -> dlss5-feed-host64.exe
```

`dlss5-feed.cfg` is fixed to `mode=1` and `async_home=0`. Mode 1 performs the
cross-process texture/fence round trip without calling NGX and displays a split
result. That separates transport failures from neural-consumer, NGX, depth, and
motion-vector failures.

The local launcher sets `VK_LAYER_PATH` and `VK_INSTANCE_LAYERS` for one process
only. It does not add Vulkan registry keys and does not require ReShade's global
Vulkan registration. This explicit-layer route is structurally validated but
must still be proven against a real `FalloutNV.exe`.

## Implemented tooling

- `tools/New-FalloutNewVegasDlss5Bundle.ps1` stages a non-installing bundle only
  below `artifacts/`. It rejects wrong-bitness PE files and refuses overwrite.
- `tools/Assert-FalloutNewVegasDlss5Bundle.ps1` re-hashes every listed file,
  rejects unlisted files, checks the x86/x64 boundary, checks both layer
  manifests, and enforces the transport-only configuration.
- `tools/Test-FalloutNewVegasDlss5Bundle.ps1` covers a valid package, tampered
  runtime rejection, unlisted-file rejection, wrong-architecture rejection,
  and the no-network/no-registry/no-game-write boundary.
- `src/Adapters/FalloutNewVegas/runtime-bundle.schema.json` records the manifest
  shape and fixed renderer contract.
- `tools/New-FalloutNewVegasDlss5FullBundle.ps1` promotes a validated transport
  package with exactly one x64 RenoDX DLSS5 consumer and user-supplied x64
  `nvngx_dlss.dll`/`nvngx_dlssnr.dll`; it rejects frame-generation payloads.
- `tools/Assert-FalloutNewVegasDlss5FullBundle.ps1` proves transport provenance,
  mode-2 configuration, complete hashes, bitness, and consumer exclusivity.
- `tools/Install-FalloutNewVegasDlss5Bundle.ps1` requires a mode-specific
  acknowledgement, fingerprints the x86 executable, backs up every collision,
  and hash-verifies every copied target.
- `tools/Restore-FalloutNewVegasDlss5Bundle.ps1` preflights all targets before
  changing any of them, rejects drift, restores prior files, and removes only
  package-created files.
- `tools/Test-FalloutNewVegasDlss5Install.ps1` and
  `tools/Test-FalloutNewVegasDlss5FullInstall.ps1` prove acknowledgement gating,
  exact backup, atomic drift rejection, and complete restoration in disposable
  game trees.

The first real artifact is generated under
`artifacts/fallout-new-vegas-dlss5-bundles/`. Artifacts are intentionally ignored
by Git; the source scripts and pin list are the reproducible deliverable.

## Pinned inputs used for the first build

| Component | Revision or version |
| --- | --- |
| DXVK | 3.0.2 release archive, SHA-256 `9C538924110A7CDEF871CA36DEE218C0774124374FFDEB38AF4B76BE55BDF7C2` |
| DLSS5-Feeder | `792755324574ff4703eb441a7bc14c724e125b84` (0.12.0 source) |
| Vulkan-Headers | `ee2ec5fd83dafce291024683b50dc89219333076` |
| NVIDIA DLSS SDK | `a291cc7d2cc642a51566f3dfd5376f635cd1b284` (310.7.0 SDK; build headers/import library only) |
| ReShade | 6.8.0 add-on installer, SHA-256 `AFE4C8F13048306307983B8B3D41D5BF00A86820440B0E57DEA10950E1176445` |
| LumeniteFX | `76fa3e4d601c97e9bc63f119c01405b7b9938885` |
| ReShade shader headers | `6db142b4b1a05c764222e5b0bd9a644b7ccfe1dc` (`slim` branch) |

The Feeder x86 add-on, x64 helper, and x86/x64 fallback layers compile locally
with Visual Studio. The staged DXVK `d3d9.dll` is the official x86 release
binary. No neural consumer and no `nvngx_dlssnr.dll` are compiled or distributed
by this repository.

## Live promotion gates

1. Install or locate an unmodified Fallout: New Vegas build and fingerprint
   `FalloutNV.exe` before any overlay is staged.
2. Create an exact backup/rollback manifest for every target path.
3. Run the transport bundle and retain `ReShade.log`, `dlss5-feed.log`,
   `feed-vk-layer.log`, and `host64/dlss5-feed-host.log`.
4. Prove ReShade attached to Vulkan, both explicit layers loaded, the x86 client
   negotiated the same IPC version as the x64 helper, frames were delivered,
   and the mode-1 split appeared.
5. Only then promote the validated bundle with exactly one user-supplied RenoDX
   consumer plus `nvngx_dlssnr.dll`/`nvngx_dlss.dll`, install it with
   `-AcknowledgeFullNeuralCandidate`, and require the Feature-18
   creation/evaluation counters to grow.
6. Validate Generic Depth selection and non-zero Lumenite motion-vector probes
   before judging image quality.

## Shader-specific work after the generic path

The generic Feeder sees final colour, selected hardware depth, and optical-flow
motion. New Vegas-specific work should be promoted only when it measurably
improves one of those inputs. The likely order is pre-HUD scene separation,
stable scene-depth selection across clears, camera-cut/reset detection, and
native camera/geometry motion reconstruction. Those are quality improvements;
none is required to prove the transport itself.

## Frame-generation boundary

This package intentionally stops before frame generation. DLSS-G cannot be
made reliable by adding another shader: an x64 presentation owner must receive
colour, depth, motion vectors, HUD-less/UI separation, camera matrices, reset
state, and Reflex timing markers, then own the D3D12 swapchain and Streamline
present path. It also needs resize, alt-tab, loading-screen, and pacing recovery.

The practical order is transport mode 1, RenoDX neural rendering mode 2, stable
pre-HUD/depth/motion inputs, and only then a separate x64 Streamline/DLSS-G host.
Until those earlier gates pass in the real game, bundling `nvngx_dlssg.dll` or
Streamline plugins would create an attractive package with no verified presenter.

## Sources

- <https://github.com/jlrouzies-fr/DLSS5-Feeder>
- <https://github.com/perseval-BLR/dlss5-classic-games>
- <https://github.com/doitsujin/dxvk/releases/tag/v3.0.2>
- <https://github.com/KhronosGroup/Vulkan-Headers>
- <https://github.com/NVIDIA/DLSS>
- <https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS_G.md>
- <https://github.com/umar-afzaal/LumeniteFX>
