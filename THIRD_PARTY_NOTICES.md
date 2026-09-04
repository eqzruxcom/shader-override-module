# Third-party notices

## Shader Injector

The portable effect work is informed by David Matos' Shader Injector project:

- https://github.com/frostbone25/ShaderInjector
- License: MIT
- Copyright (c) 2026 David Matos

The MIT copyright and permission notice must accompany substantial portions
copied from that project.

The complete notice is preserved in `licenses/ShaderInjector-MIT.txt`.
The portable contact-ray implementation in
`src/Effects/Lighting/ContactShadows.hlsl` is adapted from
`ModifiedShaders/Includes/PixelShaderPass_LocalLight.hlsl` at commit
`bab25809b375f028b7c0fb603d804426f38c9b8e`; its deliberate differences are
documented in `docs/contact-shadow-port.md`. Include the notice when packaging it.

The source-preserving path additionally copies the contact-ray section,
the interleaved-gradient-noise function, and the unchanged checkerboard parity
and AVG reconstruction statements from that same pinned commit into
`src/ThirdParty/ShaderInjector/`. `provenance.json` records the source hashes,
feature settings and the single depth-resource substitution. The complete MIT
notice is also included there as `LICENSE.txt`. The Remake compatibility wrapper
is `src/Effects/Lighting/RebirthContactShadows.hlsl`; its input mappings and
remaining caller differences are documented in `docs/rebirth-contact-source-reuse.md`.
No code from SSRT3 or Skyrim Community Shaders has been imported in this step.

## R3D

The engine-neutral SSGI feasibility work uses Le Juez Victor's R3D project as
an algorithm and pipeline reference:

- https://github.com/Bigfoot71/r3d
- Pinned commit: `3cb964171a0b90f1d0ec97e061b25021648eec65`
- License: Zlib

The pinned upstream source is retained under `reference/external/r3d`, with
selection provenance in `reference/external/r3d-provenance.json`. Any adapted
shader source must be marked as altered and retain the complete notice in
`licenses/R3D-Zlib.txt`.

## 3Dmigoto

Shader Override Module contains modified engine source based on the official
3Dmigoto project:

- https://github.com/bo3b/3Dmigoto
- License: GPL-3.0 and associated notices in the upstream repository

The upstream `COPYING.txt`, `LICENSE.GPL.txt`, source headers, authorship record,
and relevant third-party notices are preserved under
`src/Backends/3DmigotoFork/`. Distributed SOM engine binaries are accompanied
by the corresponding source under GPL-3.0. SOM's independent name and product
identity do not remove or replace upstream copyright or license obligations.

## HelixMod Intergrade patch

The downloaded Intergrade patch is retained under `reference/` as a private
game-specific engineering reference. Its original files are excluded from this
repository and are not copied into distributable project output.
