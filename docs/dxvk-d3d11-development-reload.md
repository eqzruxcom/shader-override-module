# DXVK D3D11 replacement reload boundary

## First usable contract

The first DXVK backend loads canonical
`<3dmigoto-hash>-<stage>_replace.bin` files while the game creates D3D11
shader objects. A full process restart is the explicit development reload
boundary:

1. close the game;
2. update the reviewed replacement files;
3. launch the game again;
4. compare the same capture point.

This is slower than 3Dmigoto's F10 workflow, but it is deterministic and does
not pretend an already-created D3D11 shader object changed when it did not.

F10 remains reserved for 3Dmigoto reload on the native D3D11 path. Page Up
remains the current in-game experiment control where that runtime supports it.
Neither key is claimed by the initial DXVK backend.

## What the current cache can and cannot do

The patched loader checks replacement file size and last-write time whenever a
later `CreateVertexShader`, `CreatePixelShader`, or other D3D11 shader
creation call occurs. A changed file can therefore affect a newly created
shader object without restarting.

It cannot retroactively alter shader objects the game already holds. Most
steady-state UE shader objects are created during loading and then reused, so a
file change alone is not a reliable live reload mechanism.

This boundary is independent of HLSL versus DXBC. The render path accepts
compiled DXBC only; compiling a new file does not cause the game to recreate
its D3D11 object.

## Later live-reload design

A real live reload requires a D3D11 object-lifecycle layer:

- retain original identity and creation metadata for every shader object;
- compile and compatibility-check changes off the render thread;
- create a new native shader object for a compatible replacement;
- substitute the current generation when the corresponding `*SetShader`
  call binds the original object;
- preserve reference counting, class instances, deferred contexts, and
  geometry-shader stream-output declarations;
- retire old generations only after in-flight command use is safe;
- expose one dedicated development control without rebinding F10, Page Up,
  Page Down, or the AO keys.

That is feasible backend work, but it is not a shader edit and it is not needed
to prove initial 3Dmigoto/DXVK identity and replacement parity. It stays
deferred until one real FF7 replacement passes restart-based validation.

## Safety rule

Do not install the offline DLLs merely to test reload behavior. First approve a
real FF7 replacement, prove identity and fallback parity, and create a verified
game-directory backup and rollback package.
