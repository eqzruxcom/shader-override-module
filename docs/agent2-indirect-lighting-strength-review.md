# Agent 2: offline indirect-lighting strength review

This track is indirect diffuse lighting, not ambient occlusion. It does not
modify Remake's temporal SSAO producer or any AO consumer.

## Strength decision

The pinned R3D donor documents `ssgi.intensity = 1.0` as its default. That is
the defensible **Balanced** starting point. The existing Agent 2 composite uses
`1.25` as an intentionally visible diagnostic; that remains **Strong** and is
not changed by this review.

| Variant | Scalar | Meaning |
| --- | ---: | --- |
| Balanced | 1.00 | donor-neutral R3D SSGI intensity |
| Strong | 1.25 | current Agent 2 diagnostic, 25% above Balanced |

For identical traced radiance and receiver material, Balanced contributes
exactly 80% of Strong. The change is a scalar applied after decompression and
the native diffuse receiver term, so it preserves the RGB bounce hue.

Rebirth's GTVB SSGI is useful appearance evidence, not a directly portable
strength scale. Its different compute implementation uses `MATH_PI` for most
materials but explicitly reduces hair, eyes, and preintegrated skin to `1.0`
because the larger value looks wrong on characters. Therefore this review does
not copy the π boost into Remake.

## Offline package

`tools/New-IntergradeR3DSSGIStrengthReview.ps1` emits and strictly compiles two
composite-only variants at `ps_5_0`. It pins the current composite, R3D donor,
Rebirth reference, provenance, and license hashes. Generation fails closed if
any source or strength evidence drifts.

`tools/Test-IntergradeR3DSSGIStrengthReview.ps1` builds the review twice and
requires deterministic HLSL, DXBC, assembly, and manifest hashes. It also
proves that Strong is the unchanged current source, Balanced differs only by
the documented strength/comment substitution, both objects are valid and
distinct DXBC, and the numerical energy ratio is exactly `0.8`.

The review emits no INI, no F1/F2/F3 binding, and no live package. It is marked
`runtimeEligible=false`, `installed=false`, and `liveTestsPerformed=false`.
The other shader agent owns any staged live SSGI validation.
