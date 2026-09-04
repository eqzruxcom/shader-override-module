# UE4 view reconstruction contract

`src/Engine/UE4/ViewReconstruction.hlsl` contains the portable equations used
by the Rebirth SSR, reflection-environment, GI, fog, and water passes. It does
not declare constant buffers or resource slots.

A game adapter must supply and verify:

- inverse device-Z-to-world-Z coefficients;
- view rectangle origin and inverse view size;
- inverse render-buffer size;
- screen-position scale and bias;
- clip-to-world, clip-to-view, screen-to-translated-world, and translated-world-
  to-view matrices as required by the selected effect;
- pre-view translation when converting between world and translated-world
  coordinates.

The equations support UE4 reversed-Z and dynamic-resolution view rectangles,
but they cannot establish where a particular game stores those values. That
mapping belongs in the game's captured shader contract.

## Validation order

1. Decode device depth and render it as a normalized diagnostic gradient.
2. Reconstruct world or translated-world position.
3. Visualize fractional world coordinates as RGB and check camera stability.
4. Reconstruct normals and compare a simple `dot(N, V)` view.
5. Only then enable contact shadows, SSR, reflection probes, fog, or GI.

This sequence isolates matrix orientation, view-rect offsets, reversed-Z, and
pre-view-translation errors before they become ambiguous lighting artifacts.
