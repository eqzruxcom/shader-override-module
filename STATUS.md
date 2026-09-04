# Shader Override Module status

Updated: 2026-09-04

This ledger distinguishes proven behavior from experiments. A feature is not
called working merely because it compiled or produced a visible change.

## Framework

| Capability | State | Evidence |
| --- | --- | --- |
| DX11 interception and replacement | Working foundation | x64 wrapper builds and loads in FF7 Remake Intergrade |
| Automatic ShaderRegex families | Working foundation | Exact guarded matching and rejection diagnostics implemented |
| Background input IPC | Working foundation | Deterministic one-event F2/F10 delivery demonstrated |
| Background screenshot IPC | Working foundation | Window capture and foreground fallback demonstrated |
| Dynamic resource `clear_on_create` | Built, offline verification pending | x64 Release DLL builds; live deployment not yet performed |
| Cross-game semantic catalog | Experimental | Fail-closed candidate and review tooling exists; broader game proof remains |
| DXVK D3D11 shader identity | Paused research track | Separately documented; not part of the current DX11 lighting milestone |
| DX9 / New Vegas DLSS5 transport | Built offline, live pending | 25-file hash-closed bundle plus acknowledgement-gated, backup-verified install and drift-safe rollback pass disposable-tree tests |
| DX9 / New Vegas DLSS5 neural candidate | Built offline, live pending | Validated transport can be promoted with one x64 RenoDX consumer and x64 DLSS/NR runtimes; mode-specific install and exact rollback pass disposable-tree tests; frame generation is excluded |

## DXVK / Vulkan backend

The D3D11 shader-identity backend remains a separate paused research track. The
DX9 branch instead isolates a Fallout: New Vegas transport proof that leaves the
FF7 adapter untouched. Its source-built x86 Feeder, x64 helper, local explicit
Vulkan layers, validators, transport/full package promotion, and reversible
install tests pass offline; the game is not installed on this machine, so live
transport, neural-rendering, and frame-generation claims remain pending. See
[the New Vegas transport checkpoint](docs/fallout-new-vegas-dlss5-transport.md)
and the [DXVK backend roadmap](docs/dxvk-vulkan-backend.md).

## FF7 Remake Intergrade proving adapter

| Feature | State | Notes |
| --- | --- | --- |
| Contact shadows | Verified baseline | Five confirmed shaders are covered by a guarded automatic family |
| Left-side frustum cutoff | Verified baseline | User-confirmed stable under movement and camera rotation |
| Character/clothing participation | Verified baseline | Restored without the earlier all-lights-out regression |
| Screen-space indirect-light candidate | Experimental | Real local lighting response at `c473ab75b7519f7e`; currently angle dependent |
| Separate temporal GI history | In progress | Designed to prevent both immediate disappearance and recursive frame feedback |
| Remaining light/shadow families | Pending | Resume after the indirect-light resource path is stable |

## Current technical issue

The indirect-light result is screen-space evidence. When an emitter leaves the
view, the native `c473ab75b7519f7e` history clamp can reject the injected result.
Reusing the finished scene buffer caused recursive feedback that persisted until
shader reload. The current solution is a separate, motion/depth-aware GI history
resource with deterministic initialization on creation or resize.

## Control contract

- **F10:** shader reload only
- **F2:** indirect-light experiment on/off
- **Page Up:** active foreground test cycle only when explicitly configured
- **Page Down:** graduated master toggle only when explicitly configured

## Next checkpoint

1. Validate `clear_on_create` offline and package the rebuilt x64 wrapper.
2. Build and compile the separate temporal-GI candidate.
3. Prove reset, resize, disocclusion, and no-feedback behavior offline.
4. Back up the live install, deploy, relaunch, and run controlled F2 comparisons.
5. Return to remaining light and shadow coverage using guarded shader families.
