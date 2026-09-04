# FF7 Remake Intergrade direct-light topology

This note records the verified distinction between the FF7 Rebirth Shader
Injector donor and the current FF7 Remake Intergrade DX11 regional capture.
It is classification evidence, not permission to patch an unverified light
branch.

## Rebirth donor topology

The pinned Rebirth source exposes separate D3D12 pixel-shader families:

- `DirectionalLight` reads its light attenuation texture at `t9`.
- ordinary `LocalLight` reads light attenuation at `t9` and closest HZB at
  `t10`.
- `LocalLightIES` uses the same source include under
  `SHADER_VARIANT_LOCAL_LIGHT_IES`, adds a sampled source/profile texture at
  `t9`, and shifts attenuation/HZB to `t10`/`t11`.

Those names and register numbers are donor evidence. They are not a safe
one-to-one map onto Remake.

## Remake capture topology

The verified 184-shader regional capture contains five compatible variants of
one D3D11 tiled surface-light compute evaluator:

- `08bb8764f1840179`
- `0e97888f9a8767da`
- `5a9fbefe0ab6f815`
- `62b33a2d1e505241`
- `c30cdc8365df9840`

All five:

- consume a structured 80-byte light record;
- reconstruct the vector from the surface position to a per-light position;
- calculate squared distance and inverse-radius-squared attenuation;
- apply the native radial cutoff polynomial;
- apply a spot-cone term;
- contain a per-light branch that bypasses radial attenuation for an
  infinite/non-radial light;
- gather a shadow texture array; and
- write the shared HDR lighting output.

This is a shared light-list evaluator. The five hashes are compatible
permutations, not five independently named light types.

Three variants read an optional `t9` texture only during final output
composition and blend it with the accumulated light. That texture is the
existing lighting buffer, not an IES profile. The other two variants write the
accumulated light directly.

## What remains unproven

- The infinite/non-radial branch is structurally present, but the current DXBC
  alone does not prove that it belongs specifically to a directional light.
- No dedicated IES profile lookup is proven in the captured family. IES may be
  represented through shared light data/atlases or may simply be absent from
  this region.
- Rebirth's separate `DirectionalLight`, `LocalLight`, and `LocalLightIES`
  pixel-shader files therefore cannot be transplanted by filename or register
  position.

Before a light-type-specific transformation, runtime-own a representative
directional or IES light, identify its exact branch/data contract, and reject
variants that do not satisfy that contract. Transformations proven valid for
the complete shared evaluator can still be applied to all five compatible
variants.

Machine-readable evidence:

- `artifacts/analysis/intergrade-local-light-radial-family-scan.json`
- `artifacts/analysis/ff7-remake-intergrade-direct-light-topology.json`
- `artifacts/analysis/intergrade-rebirth-lighting-coverage-gap.json`

