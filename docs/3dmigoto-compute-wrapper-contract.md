# 3Dmigoto compute-wrapper contract

This project uses original-first compute wrappers to preserve game behavior and
apply narrowly scoped controls after the original dispatch. The contract below
is derived from the locally pinned 3Dmigoto DX11 source, not from observation
alone.

## Confirmed runtime behavior

- `draw = from_caller` is the generic replay command for both draw and dispatch
  calls. For an active `Dispatch`, the DX11 implementation calls
  `Dispatch(ThreadGroupCountX, ThreadGroupCountY, ThreadGroupCountZ)` with the
  original counts.
- `IniParams` is a `Texture1D<float4>` shader resource and defaults to slot
  `t120`. The runtime pins that SRV so game resource changes cannot unbind it.
- Nested post shaders in this project explicitly bind the `IniParams` resource
  to a dedicated SRV slot (currently `cs-t114`). This avoids relying on the
  global pin surviving custom-shader state changes and makes the binding part
  of the recorded rolling A/B specification.
- A nested custom shader receives the active caller metadata through the same
  command-list state. Therefore a compute custom shader can use
  `draw = from_caller`; there is no separate `dispatch = from_caller` command in
  this pinned version.

Authoritative local references:

- `reference/3Dmigoto/DirectX11/CommandList.cpp`, the `FROM_CALLER` switch and
  `DrawCall::Dispatch` branch.
- `reference/3Dmigoto/DirectX11/HackerContext.cpp`, `IniParams` SRV pinning.
- `reference/3Dmigoto/DirectX11/IniHandler.cpp`, default `ini_params=120`.

## Original-first snapshot sequence

1. Intercept the verified compute hash.
2. Replay the original dispatch with `handling = skip` and
   `draw = from_caller`.
3. Copy its UAV output into a custom resource.
4. Bind the snapshot to an unused compute SRV slot.
5. Bind `IniParams` explicitly to a second unused compute SRV slot when the
   post shader has runtime controls.
6. Run a second compute shader with the original dispatch dimensions.
7. Unbind both temporary SRVs before returning to the game.

## Validation gates

1. A fixed-color post must visibly mark only the intended effect volume. This
   proves the nested post dispatch and snapshot/output bindings execute.
2. A fixed-zero post must visibly remove the same contribution. This checks
   that the marker did not merely add an unrelated signal.
3. A neutral parameterized post must pass native-resolution static-region pixel
   parity.
4. A non-neutral parameter value must produce the expected directional change.
5. F3 must switch Previous and Current without requiring reload, and F10 must
   preserve the rolling-promotion invariant.

The fixed-color gate is deliberately earlier than parameter debugging: if it
does not execute, `IniParams` values are irrelevant. If it executes but a
non-neutral parameter does not, inspect the generated `t120` load and runtime
constant row before changing wrapper mechanics.
