# Final-composite bytecode candidate — 2026-08-30

This continues `final-composite-integration-study.md`. No live game files were
changed during the offline work described here.

## Verified results

- Built the pinned 3Dmigoto command-line assembler locally. Reproduce with
  `tools/Build-ShaderAssembler.ps1`; build-only properties in
  `tools/ShaderAssembler.Build.props` supply the installed SDK include/library
  paths without editing pinned sources or system registration. Intermediate
  directories are separate per project, under workspace artifacts.
- Disassembled the original `41f1bf8b79d01319` with Flugan's precision-preserving
  disassembler and validated its assembly round trip.
- Reassembled while preserving the original reflection/signature sections.
  The entire neutral binary has the exact same SHA256 as the original:
  `8B7DB294C666E296D4974929E41892BE44D2BF6984B0BF1511788117A6E4C263`.
- Prepared a single scene-brightness instruction before the overlay blend:
  `mul r2.xyz, r2.xyzx, l(0.500000, 0.500000, 0.500000, 0.000000)`.
- Verified all 135 original instruction/declaration tokens remain byte-for-byte
  unchanged and in order. Exactly one 40-byte instruction is inserted at index
  103. All non-code DXBC sections remain identical. The new binary assembles
  and passes disassembly validation.

Candidate binary SHA256:
`507ABAB0052E52DFC5F9A2EF4FFFB82A38AE95D48C3C67D71AB0DF501642F37E`.

Generated evidence:
`artifacts/final-composite-candidate-20260830/candidate-manifest.json`.

`tools/Test-IntergradeFinalCompositeCandidate.ps1` passed. It checks the audited
output fingerprint, source/neutral identity, pending visual status, artifact
hashes, overwrite refusal, and rejection of modified source before output is
written. The generator independently compares DXBC section bytes and each
original instruction around the inserted instruction. The reproducible build
script also completed successfully.

## What this does and does not establish

This is a scene-only half-brightness candidate *after* native color mapping,
not a replacement native tone curve. It halves numeric RGB at the selected
point, not necessarily perceived display brightness. It deliberately retains
the game's LUT/color logic, original overlay combination, output transfer, and
dithering. Visual UI preservation and rendering behavior remain pending.

The byte-identical neutral reconstruction removes HLSL decompiler uncertainty
for this method. It does not establish that the modified shader has been
accepted by the running graphics driver or that the inferred UI boundary is
visually correct. `runtimeEligible` remains false.

## Loading constraint to address next

The inspected `reference/3Dmigoto/DirectX11/CommandList.cpp` CustomShader loader
compiles its source as HLSL; it does not directly recognize an arbitrary `.bin`
or `.shdr` filename as shader bytecode. Its timestamp-matched compiled cache is
not a general bytecode-loading API. Do not simply put the assembled binary in
a `ps = ...` line or disguise it as a valid HLSL file.

The native shader-replacement/assembly route must be inspected and a reliable
original-comparison mechanism retained before staging this candidate. Do not
replace the current live diagnostic merely because offline byte preservation
passed. Keep the current Page Down/original test untouched until that loading
and comparison design is verified.
