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
| DXVK / Vulkan backend | Paused research track | Separately documented; not part of the current DX11 lighting milestone |

## DXVK / Vulkan backend

This is a separate backend track, not an alternate name for the current DX11
work. Its purpose is to preserve SOM shader identities and family behavior when
a D3D9/D3D11 game is translated to Vulkan. It is paused while the native DX11
engine and FF7 Remake lighting pipeline are being proven. See
[DXVK / Vulkan backend roadmap](docs/dxvk-vulkan-backend.md).

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
