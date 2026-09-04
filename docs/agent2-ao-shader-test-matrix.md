# Agent 2 AO shader test matrix

The current live AO remains Remake's native temporal SSAO. Agent 2 changes only
the verified reflection/indirect consumer `e2aa1c8cb39e0a55-ps`, applying the
literal Rebirth Performance native-ScreenAO fallback shaping. It is not a new
AO producer, GTVB, GTAO replacement, or SSGI bounce pass.

## Changed and compared with F2

- `e2aa1c8cb39e0a55-ps`: F2 off preserves the existing neutral owner; F2 on
  applies ScreenAO power 2, eye lift 0.5, and character combined-AO power 1.75.

## Must remain unchanged

- Native temporal/filter chain:
  `a77b589dce5822d6-ps`, `40c795101bdaad50-ps`,
  `c9dfe2b46edf3ece-ps`, `d41207d5d61df5b5-ps`,
  `a8845c7ad73425a9-ps`.
- Five tiled direct-light consumers:
  `c30cdc8365df9840-cs`, `62b33a2d1e505241-cs`,
  `5a9fbefe0ab6f815-cs`, `0e97888f9a8767da-cs`,
  `08bb8764f1840179-cs`.
- SSR producer `b2bc6059f9a39c7f-ps`: preserve RGB radiance and hit alpha.
- Capsule producer `b9e2305a994308f2-cs` and the retained contact-shadow
  path: preserve behavior.

`c62607f2631cf47e-ps` is a possible later-region reflection/indirect variant,
but it is capture-required and must not be patched from similarity alone.

Visual coverage includes corners, hair/skin/eyes, cloth, foliage, thin rails,
wet and metallic reflections, interiors/exteriors, motion, and camera cuts.
Reject for crushed indirect detail, character over-darkening, halos/outlines,
flicker, temporal pumping, SSR changes, direct-light changes, capsule/contact
changes, or an unmatched later-region permutation.

Machine-readable evidence:

- `tools/Analyze-IntergradeAOShaderTestMatrix.ps1`
- `tools/Test-IntergradeAOShaderTestMatrix.ps1`
- `artifacts/analysis/agent2-ao-shader-test-matrix.json`
