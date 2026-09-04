# FF7 Remake Intergrade SSGI character-material compatibility

## Confirmed ownership

- `e2aa1c8cb39e0a55-ps` is the live full-screen reflection/environment composite used by the standalone SSGI experiment.
- `c58358673087aaf8-ps` is a downstream bloom-pyramid resample stage. It carries an upstream over-bright result into bloom but does not generate geometry-aware indirect lighting.

## Rebirth donor behavior

The Rebirth Shader Injector decodes the shading-model ID from the low four bits of packed GBuffer B alpha. Its material library declares:

- `2`: subsurface, marked unused by that game
- `3`: preintegrated skin
- `5`: subsurface profile
- `7`: hair
- `9`: eye

The donor recognizes subsurface profile (`5`) in its supported-material and lighting paths. However, its final SSGI boost reduction only special-cases preintegrated skin, hair, and eye (`3/7/9`). It does not include subsurface profile (`5`) in that final reduction.

## Remake live evidence

- A bounded-HDR composite still made Cloud's skin white.
- Reducing only `3/7/9` from a `0.25` material boost to `0.025` produced no visible correction.
- Because `0.025` limits the maximum additive response to a very small value, the unchanged result is evidence that Cloud is not entering the current `3/7/9` branch.

## Current diagnostic

The staged diagnostic assigns zero SSGI receiver contribution to `2/3/5/7/9` while preserving the reviewed world-surface response. This test distinguishes:

1. a missing Remake character shading-model classification (especially subsurface profile `5`), from
2. a more fundamental mismatch in the `e2aa` composite inputs or ownership.

Do not modify `c583` to resolve this test. That would alter bloom globally and conceal the upstream classification result.

## Composite-state audit

The standalone `e2aa` injection is configured as an additive pass rather than an overwrite:

- the composite uses `blend = ADD ONE ONE`;
- its shader returns alpha `0`;
- the native `e2aa` draw is not skipped;
- the copied scene target is used as trace input, while the final SSGI result is added back to the original render target;
- high SRV slots `t110` through `t114` are restored after the custom passes.

This makes an accidental full-frame replacement less likely. The live zero-response material-family test remains the decisive next gate.
