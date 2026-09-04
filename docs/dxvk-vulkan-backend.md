# DXVK / Vulkan backend roadmap

State: **Paused research track**

The DXVK work is deliberately separated from SOM's native DirectX 11 engine.
The current priority is to finish and validate shader-family discovery,
resource ownership, contact shadows, indirect lighting, and remaining lighting
coverage on native D3D11.

## Purpose

The backend should let D3D9 or D3D11 games run through DXVK while SOM preserves
stable shader identities, semantic family matching, resource/pass discovery,
and controlled graphics injection. DXVK is the translation backend; it does not
by itself grant a legacy game newer engine features.

## Non-goals for the current milestone

- No DirectX 12 feature path.
- No promise of hardware ray tracing merely because Vulkan is present.
- No mixing unverified Vulkan behavior into the accepted D3D11 adapter.
- No replacement of the current FF7 Remake D3D11 proving path.

## Planned stages

1. Define a backend-neutral shader identity and event model.
2. Map D3D11 shader creation and bindings to DXVK/Vulkan module and pipeline
   identities without changing SOM's user-facing shader-family names.
3. Build an offline DXBC-to-SPIR-V identity and compatibility corpus.
4. Add resource, descriptor, render-pass, and dispatch telemetry.
5. Prove neutral replacement parity in a small D3D11 application through DXVK.
6. Prove one guarded SOM shader family in a real game through DXVK.
7. Measure compilation stutter, cache behavior, CPU overhead, and compatibility.
8. Promote the backend only after native/DXVK A/B validation passes.

## Tracking rules

- DXVK work uses the GitHub label `backend: dxvk`.
- Native D3D11 work uses `backend: dx11`.
- Shared abstractions use `engine` and must retain tests for both backends.
- Experimental code remains off by default and cannot silently alter the live
  FF7 Remake adapter.
