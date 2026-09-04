# Intergrade lighting offline validation — 2026-09-04

## Outcome

Eighteen applicable offline checks pass. The live game install remains unchanged: both the pre-temporal transition and lighting-ownership capture stagers report `not-staged` after their successful `-WhatIf` preflights.

The Windows-control helper could not initialize because its own sandbox process exited with `apply deny-read ACLs`. It was reset and retried according to its recovery procedure, then abandoned without focusing the game or sending input. Live capture and visual validation therefore remain pending.

## Passed checks

1. Accepted contact-family guard rejection.
2. Accepted contact-family validation.
3. Engine-equivalent contact-family contract: exactly five of 184, split 3+1+1.
4. Directional-light coverage classification.
5. Unshadowed local-light coverage classification.
6. Lighting coverage resolution.
7. Tiled-light profile branch.
8. Tiled local-light dataflow.
9. Pre-temporal SSGI pack contract and strict compilation.
10. SSGI sampling semantics.
11. SSGI angle-dependence classification.
12. Shader census transition.
13. Lighting family model.
14. Lighting ownership capture pack.
15. Known-capture shader resource flow.
16. Atomic pre-temporal transition stage/restore.
17. Atomic ownership-capture stage/remove.
18. c473 pre-temporal resource ownership and downstream-consumer ordering.

## Raw-regex diagnostic distinction

`Test-IntergradeAcceptedContactShadowFamilyRegex.ps1` is not an engine-equivalent acceptance test. It applies only the pattern bodies and therefore reports the already documented overlap between the two T4 native bodies. The accepted family is intentionally disambiguated by exact instruction-count and binding guards (`631` versus `478`).

`Test-IntergradeGeneratedContactShadowFamilyRegex.ps1` targets an older two-family section layout and is not applicable to the accepted three-family BaseT5/BaseT4/FrustumT4 artifact.

The current acceptance oracles are:

- `Test-IntergradeAcceptedContactFamilyValidation.ps1`
- `Test-IntergradeAcceptedContactFamilyGuardRejection.ps1`
- `Test-IntergradeAcceptedContactShadowFamilyContract.ps1` with the accepted INI and generation report.

## New c473 ownership proof

The pinned frame capture proves:

- current-scene `t2` and temporal output `o0` are different resource addresses;
- their resource descriptor hash matches, supporting `copy_desc` compatibility;
- native history `t3` and motion `t4` are separately owned resources;
- `af6cd28a0108a18a-ps:t0` is the first consumer of c473 output.

This rules out intrinsic c473 input/output aliasing and independently proves why the old af6 replacement must be quarantined during the c473 experiment.

## Pending live gates

1. Capture `aadc1c2374853914-ps` outdoors and identify its first downstream consumer.
2. Capture `adb544f9a11d6c7e-cs` in a scene that actually dispatches it.
3. Stage the c473 transaction only with the game closed, then test F2 off/on for white materials, persistence, camera-angle loss, contact/frustum regression, and exact restore.

