# Contact shadows - Rebirth Mod - Code worked

**Preserved working reference, 2026-08-31. Do not tune this copy in place.**

The original Rebirth mod is the donor. Its source-preserving Remake adaptation
worked in the user's modified-UE4 game: "its stable" and "that said it looks
working in most cases". This record is not a claim that we independently tested
Rebirth today or that the Remake port is visually finished.

## Contents

- `original-donor/`: pinned original local-light HLSL and noise helper, MIT
  license, and extraction provenance. These are reference source files, not a
  complete standalone Rebirth mod distribution.
- `original-remake/`: five untouched captured native shaders as DXBC `.bin`
  and disassembled `.asm`. These are compiled-game originals, **not original
  engine HLSL source**. Local reference only; do not redistribute game shader dumps.
- `working-remake-port/`: tested replacement payload, relevant source snapshot,
  and loading/validation receipts copied from the first working checkpoint.
- `code-record.json`: exact file hashes and provenance. Later experiments belong
  elsewhere; preserve this record and all originals.

Donor: `frostbone25/ShaderInjector`, commit
`bab25809b375f028b7c0fb603d804426f38c9b8e`, David Matos, MIT.

## Known refinement, kept separate from "code worked"

Added sword/cone shadow edges can be too hard beside the softer native Remake
shadow. User wants a softer edge, not just lower strength. Rebirth's native
shadows/lighting may differ. That observation does not establish a donor defect.
The donor traces one direction toward the light; its falloff setting changes
visibility with ray progress, not light-area sampling or a broad edge filter.
Its checkerboard AVG reconstruction is already used in the working port.

Full-resolution screenshots and user reports:
`artifacts/checkpoints/rebirth-contact-first-working-20260831-v1` in the project.
ON/OFF order is not assigned to unlabeled screenshots. Native shadows remain.

This is the known-working reference for further softness work, not a cleared
quality gate: synthetic motion failures and unverified GPU cost remain recorded.

See [the working-code list](../../docs/known-working-code.md) for the larger
Universal Unreal Engine Shader Changer design and other working results.
