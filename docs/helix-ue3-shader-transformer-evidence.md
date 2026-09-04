# Helix UE3 shader-transformer evidence

## Why these artifacts matter

Two user-supplied historical artifacts now give concrete evidence on both UE3
renderer backends:

1. BioShock Infinite / UE3 / DX11: the preserved 838-line `PSscript.lua`
   recognizes semantic names and instruction sequences in `ps_5_0` assembly,
   allocates declarations and temporaries, rewrites compatible shaders, and
   returns patched assembly.
2. Mass Effect 3 / UE3 / DX9: 758 retained SM3 shader texts show a large
   enumerated override corpus across 637 pixel and 115 vertex shader files,
   plus six root variants.

The BioShock script is associated by the user with Helix's unreleased DX11
implementation whose only known target was BioShock Infinite. It is not a
released universal wrapper and is not 3Dmigoto. The ME3 archive contains no
wrapper DLL, so it proves the override corpus and transformations, not the
closed runtime implementation.

Primary local references:

- `reference/external/Helix-BioShockInfinite-UE3-DX11/README.md`
- `reference/external/Helix-BioShockInfinite-UE3-DX11/PSscript.lua`
- `reference/external/helix-me3-new-shader-override/README.md`
- `reference/external/helix-me3-new-shader-override/ShaderOverride/`

## The user's dynamic-shadow distinction is confirmed

The ME3 headers explicitly expose separate dynamic-light and dynamic-shadow
semantics. In the supplied corpus:

- 622 pixel shaders declare both `bReceiveDynamicShadows` and
  `LightAttenuationTexture`.
- 5 vertex shaders expose `ShadowViewProjection`.
- 22 vertex shaders expose `LightPositionAndInvRadius`.
- 6 shader variants expose `ShadowDepthTexture`.

This supports the user's prior observation from DX9/3D Vision work: character
and movable-object permutations are not interchangeable with cheaper static or
baked surface paths. They may share a high-level shadow operation while using
different stages, inputs, quality assumptions, and filtering paths.

The percentages here describe Helix's selected override corpus, not the full
ME3 shader inventory. They prove that Helix enumerated many compatible variants;
they do not imply that nearly every surface in the complete game is dynamic.

## Same family, different signatures

The evidence favors a shared transformation family with multiple signatures,
not one literal text patch for every engine version:

- semantic intent is stable: shadow projection, attenuation, depth
  reconstruction, screen-space lookup, and material lighting;
- UE generation, API, compiler, shader stage, quality permutation, and game
  modifications change declarations, registers, instruction shapes, and
  scheduling;
- a family matcher must recognize the stable intent and select an exact
  compatible rewrite descriptor;
- unmatched or ambiguous variants must fail closed and enter review.

This is close to a universal rule in effect intent and recognition strategy,
while remaining adapter-specific at bytecode and binding boundaries.

## Header retention is a functional requirement

The Microsoft compiler headers are not decorative. They preserve names such as
`bReceiveDynamicShadows`, `ShadowViewProjection`,
`LightPositionAndInvRadius`, and `LightAttenuationTexture`. Helix's DX11 Lua
script directly searches comparable semantic names before choosing a rewrite.

Our universal capture format must therefore preserve, where available:

1. original bytecode;
2. full disassembly including compiler/reflection headers;
3. stage and shader model;
4. resource, constant, input, and output declarations;
5. structural instruction fingerprints;
6. the exact original and replacement hashes.

A stripped replacement file cannot serve as the only family-classification
record.

## Consequence for the Remake contact/frustum work

The five verified Remake tiled surface-light compute variants are one working
contact-light family. They are not the whole dynamic-shadow inventory. The
current classification correctly records material/GBuffer writers and the
upstream capsule producer separately, but directional, local-light/IES, and
dynamic receiver/projector families remain incomplete.

The left-edge frustum fade must remain scoped to the shader family proven to
show screen-space clipping. Native character dynamic-shadow maps, static/baked
shadows, capsule occlusion, and other receiver permutations may not share that
failure. Promoting the fade globally before family ownership is known would
hide evidence and could damage unaffected paths.

## DX9-first universal runtime interpretation

A focused DX9 runtime is a credible first implementation because SM3 has a
small register/resource model and short, readable shaders. The proposed split
is:

1. intercept the game's D3D9 shader creation and retain original bytecode;
2. hash and disassemble each shader with its compiler header;
3. classify it by semantic header plus structural signature;
4. apply a verified family transformation;
5. compile/load a compatible replacement;
6. expose capture, hunter, reload, enable/disable, and rollback controls;
7. use a modern backend for optional added passes and resources.

DX9 does not attach engine-level names such as `UI`, `world depth`, or
`ambient light` to draw calls, but those semantics are not opaque. The
runtime should classify them from combined evidence rather than require a
single label. Useful signals include:

- pre-transformed `XYZRHW` vertices or constant clip-space `W = 1`,
  orthographic transforms, depth-disabled state, alpha blending, and late draw
  order for likely UI;
- depth-target dimensions, clear/use history, draw coverage, projection
  behavior, and shader/resource identity for likely primary world depth;
- compiler comments, constant/sampler bindings, normalized instruction
  structure, render-target contracts, and neighboring draw state for lighting
  and shadow families.

No one signal is universal: fullscreen post-processing can also use `W = 1`,
and world-space UI can use perspective. Classification must therefore combine
signals, retain exact-hash fast paths, report confidence, and require review
before a structural match becomes an automatic replacement rule. This follows
the practical Helix/3D Vision precedent without claiming that DX9 itself
provides semantic API flags.

With DXVK, modern authored HLSL should compile to SPIR-V rather than accepting
precompiled DX12/DXIL blobs. The original DX9 shader defines the game's input,
constant, sampler, and output contract. Extra compute passes, UAVs, history
buffers, or textures must be explicitly allocated and scheduled by the wrapper;
rewriting a DX9 pixel shader alone does not create those resources.

This DX9-first runtime is complementary to, not a replacement for, the active
Remake/UE4/DX11 adapter work.
