# Agent 2: engine-neutral SSGI donor decision

## Decision

Use the open-source R3D SSGI/SSIL implementation as the primary algorithm and
pipeline reference for Remake. Do not port Final Fantasy VII Rebirth's
`ReflectionEnvironment` resource layout, shader model, or engine-specific
branches.

Pinned upstream:

- Repository: https://github.com/Bigfoot71/r3d
- Commit: `3cb964171a0b90f1d0ec97e061b25021648eec65`
- License: Zlib
- Local reference: `reference/external/r3d`

## Why this is the better boundary

R3D is not an Unreal or Final Fantasy implementation. Its SSGI shader is a
fullscreen OpenGL 3.3 fragment shader whose external contract is only:

- scene radiance;
- view/deferred normals;
- scene depth;
- camera projection/view transforms and effect settings.

It writes a dedicated half-resolution RGB16F indirect-light texture and applies
an edge-aware A-trous denoiser before ambient composition. Its SSIL alternative
uses the same three inputs and produces indirect RGB plus AO visibility in
alpha. These contracts map cleanly to Shader Model 5.0 and do not depend on
DX12 descriptor spaces, wave operations, or Rebirth's `ReflectionEnvironment`
UAV layout.

## Remake adaptation

The first integration candidate should keep Remake's verified temporal SSAO
chain native and add only R3D-style indirect diffuse lighting. This separates
two risks:

1. native AO remains stable and can still be tested with the existing F2 AO
   control;
2. SSGI is a dedicated, independently switchable fullscreen pass.

The portable shader core must expose only these bindings:

| Binding | Meaning |
| --- | --- |
| `t0` | scene radiance captured after direct lighting |
| `t1` | normal buffer |
| `t2` | scene depth |
| `b0` | inverse projection, viewport, and SSGI parameters |
| `o0` or `u0` | dedicated indirect-radiance output |

Use a pixel-shader fullscreen path first because the R3D reference proves the
algorithm does not require compute. A compute variant is optional optimization,
not an architectural requirement.

## Remake evidence update

The resource and scheduling identity is now proven by
`artifacts/analysis/agent2-r3d-ssgi-injection.json`. A strict-compiled offline
owner-integration candidate is documented in
`docs/agent2-r3d-ssgi-remake-integration.md`.

## Evidence still required before a live build

- live acceptance of the proposed half-resolution resource formats and custom
  pass sequence;
- non-default viewport validation of neighboring reconstruction rays;
- GPU timing and motion/disocclusion captures.

No live files or key bindings are emitted by this decision. F1 remains reserved
for the eventual global on/off control; F2 remains the current single-change
test control.
