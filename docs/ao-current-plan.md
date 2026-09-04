# FF7 Remake Intergrade ambient-occlusion plan

Date: 2026-09-01

## Current decision

The technically appropriate Remake AO candidate now is a consumer-local port of
Rebirth's **native ScreenAO fallback shaping** at Remake shader
`e2aa1c8cb39e0a55-ps`. It is an ambient/reflection AO improvement, not a new AO
producer and not a GTVB/SSGI port.

This supersedes the earlier producer-local `a77b...` power candidates as the
preferred integration target. Modifying `a77b...` changes the final ScreenAO
resource for all five tiled direct-light consumers. Rebirth instead applies its
ScreenAO power, character handling, specular occlusion, and GTAO multi-bounce
inside `ReflectionEnvironment`; Remake `e2aa...` is the verified equivalent
ownership boundary.

Everything remains offline. No live game file, runtime INI, shader override,
hotkey, Page Up/Page Down/F10 control, contact-shadow shader, lighting artifact,
or DXVK component was changed by this workstream.

## Reserved controls and current blocker

| Key | Exclusive AO role | Current package state |
| --- | --- | --- |
| F1 | Original/native AO | design metadata only; no binding emitted |
| F2 | Balanced | design metadata only; no binding emitted |
| F3 | Strong | design metadata only; no binding emitted |

The current workspace runtime has one conflicting existing claim:
`runtime/Intergrade/Mods/RebirthEffectsDX11.ini:49`,
`key = no_modifiers F3`, owned by `[KeyRebirthRollingAB]`. This AO work does not
edit it. The review package records `integrationReady=false` and must remain
uninstalled until the main task resolves that conflict and reviews integration.

Page Down remains the global retained-lighting/contact master, Page Up remains
the main lighting experiment, and F10 remains 3Dmigoto reload.

## Direct evidence from both Rebirth v2.2.1 archives

The audit reads both user-provided ZIPs in memory, pins their hashes, and does
not execute or install their payloads:

- Performance SHA-256:
  `21C8715F311B1B25CE8C19489F97729F7CBD0846B1A18AF5C976349C74EDE4BA`
- Maximum Quality SHA-256:
  `CED1790992265E203E0DB418203881D5570A58C5AF0663E5F50C05A7996CD119`
- Each archive contains 158 files: 143 byte-identical and 15 different.
- Only three shared HLSL sources differ. In `ReflectionEnvironment`, the exact
  source difference is enabling `SSGI_AMBIENT_OCCLUSION` and
  `SSGI_BOUNCE_LIGHT` in Maximum Quality. Normalizing those two lines makes the
  two 109 KB sources byte-identical.

Exact `ReflectionEnvironment` evidence:

| Preset | Source SHA-256 | Compiled blob | Active AO architecture |
| --- | --- | --- | --- |
| Performance | `CAC5ED975F537238011B6913126299EEE1F415B4DC4DEE254CCABC597C841BDE` | 47,140 bytes, `45DEEBA955778BC31C162C2BC78190470E68CCBF76F2506C14E667E98587A0E1` | Native ScreenAO fallback; GTVB AO and SSGI bounce disabled |
| Maximum Quality | `CEBA077018F2ACBD48A86AEF82CD603B8F219C71E501947AE3E88129A715164B` | 52,528 bytes, `B43F9EA7E8CB7A8D67631D3781C7064C47E97B00911F09B1CA6208E28C2BFAFA` | In-pass GTVB visibility plus SSGI bounce enabled |

All four version wrappers and fingerprint manifests are identical between
presets. The HLSL entry point is `main`; donor reflection records identify the
original game entry as `ReflectionEnvironmentCS`. All targets are `cs_6_6` with
`[numthreads(8,8,1)]`. Exact target hashes are
`8EE4A2ED727B9354`, `B0118AE85F2A8841`, `E1B12859DD745E06`, and
`F6B2E1B7C2560BAB`. The family has three legitimate cross-version identities:
`15DAFDB1ADEE8155`, `6279FF542CF393BA`, and `17DCCC9E96DB7D30`.

The donor binds samplers `s0-s4`; fallback cubemap `t0`; preintegrated GF `t1`;
thin film `t2`; GBuffer A-E `t3-t7`; depth `t8`; SSR `t9`; native ScreenAO
`t10`; other light inputs `t11-t12`; environment irradiance `t13-t14`; and
output UAV `u0`, with globals in `b0` and the large View buffer in `b1`.

Maximum Quality `ComputeGTVBGI` uses one ray per pixel, 16 ray-march steps,
512-pixel maximum reach, thickness 75, normal bias 0.0005, hair bias 0.1, and
animated noise. Checkerboard and the basic quad denoiser are disabled. It has no
dedicated history texture or filter pass; the source explicitly relies on the
game's TAA to blend the animated noise. AO then feeds material/character rules,
specular occlusion, and `GTAOMultiBounce`; optional bounce is added afterward.

Performance instead reads native `ScreenAO`, applies the fallback power rules,
then enters the same material/specular/multi-bounce ambient/reflection path.
That active Performance path—not Maximum Quality's new ray marcher—is the
portable subset used now.

`SampleGI` is separate baked-GI/character ambient shaping. Its spherical-
harmonics contact path remains disabled in both presets. Contact shadows,
capsule occlusion, material writers, and tiled light shaders are not AO
producers and are excluded.

## Verified Remake producer/consumer chain

| Event | Shader/stage | Verified AO role |
| ---: | --- | --- |
| 1015 | `a77b589dce5822d6-ps`, `ps_5_0` | Temporal SSAO producer. `t0` noise, `t1` normal, `t2` depth, `t3` history, `t4` velocity, `t5` HZB, `b0[21]`, `b1[140]`; packed current/history/metadata to resource `0x00000278082FB220`. |
| 1016 | `40c795101bdaad50-ps` | Depth-aware neighborhood reduction/filter. |
| 1017 | `c9dfe2b46edf3ece-ps` | Depth-aware 3x3 filter. |
| 1018 | `d41207d5d61df5b5-ps` | Wider depth-aware filter and variance-like term. |
| 1019 | `a8845c7ad73425a9-ps` | Final ScreenAO compositor; writes scalar AO to `0x0000027807DEEAE0`. |
| 1028-1032 | five tiled local-light CS variants | Consume final ScreenAO at `t5` or `t6` alongside separate capsule occlusion. Direct-light consumers, not AO producers. |
| 1096 | `e2aa1c8cb39e0a55-ps`, `ps_5_0` | Consumes final ScreenAO at `t6`, GBuffer/material data, reflection cube array `t10`, and SSR radiance/hit alpha `t11`; ambient/reflection AO consumer and current adapter target. |

`e2aa...` already combines ScreenAO with material and another native occlusion
term, derives roughness/view-dependent specular occlusion, evaluates the same
GTAO multi-bounce polynomial as Rebirth, masks reflection-environment fallback
by one minus SSR alpha, and adds SSR radiance separately. The adapter preserves
that native dataflow and output packing.

The exact decompiled source SHA-256 is
`E82E8D7A5EF91FD954B50A95CBC250B08F43B28C91450B9EC2106A82478A6716`.
Generation requires this exact SHA, the exact shader family/hash, one `t6`
ScreenAO sample anchor, and one material-AO combination anchor; otherwise it
fails closed. Current evidence covers the 184-shader regional capture only, not
all game regions/permutations.

## Offline Original/Balanced/Strong design

| Mode | Formula and scope | Source SHA-256 | Object SHA-256 |
| --- | --- | --- | --- |
| F1 Original | Native `e2aa...`; no replacement artifact | n/a | native |
| F2 Balanced | ScreenAO power 1.50, eye lift 0.50, character combined-AO power 1.375 | `401B30B75A5712BE638B58D43AC634D430813F191F6079C64A4F991781BA7908` | `75386D0682553F8C705DA47DC1D57F3FE5F8B8AB97BBB80B8BEFF35499E9DC54` |
| F3 Strong | Donor-literal ScreenAO power 2.00, eye lift 0.50, character combined-AO power 1.75 | `4F2A4B756D912272DDAC6737EFC899D546124B5FD2EA1417A953983411A7FC86` | `52199A5565EFDC836A20D982542D24280DF9FE11A1F349FD6DAADB6BAA76712A` |

Balanced is a conservative interpolation toward the donor fallback. Strong is
the literal donor fallback strength, including the donor condition
`model != eye || model != hair`, whose OR makes the initial square apply to all
models; eye softening still follows. Neither candidate edits the temporal AO
producer/history or the ScreenAO resource seen by direct lights.

Expected difference: Balanced should moderately deepen existing
ambient/reflection creases and character ambient shaping. Strong should create
more contrast and carry greater hair/skin/eye and crushed-indirect-detail risk.
Neither mode adds AO reach, new rays, newly detected geometry, SSGI detail, or
bounce light.

## Why Maximum Quality GTVB/SSGI is deferred

A Remake shader replacement cannot invent Rebirth's `t3-t14` inputs, `u0`
read/write behavior, compute dispatch, frame index/noise contract, or temporal
and filtering schedule. A true quality upgrade needs a new Remake-specific pass
with captured resource formats/dimensions, an injection point before
reflection/indirect consumption, explicit SRV/UAV binding and dispatch,
disocclusion-safe temporal accumulation/filtering, performance measurements,
and later-region family coverage. Source pasting would be unsafe and is not
implemented.

## Offline review package and exact live gate

The binding-free package is
`artifacts/ao-reviewed-integration-20260901-v1/`. It contains the two compiled
variants, source/assembly/manifests, `review-manifest.json`, and
`live-test-plan.md`. It contains no INI or installer and records the F3 conflict.

After the main task reviews the package and resolves the F3 conflict:

1. Map only F1 Original, F2 Balanced, F3 Strong. Do not change Page Down,
   Page Up, or F10.
2. Use a fixed camera, resolution, and settings. Capture all three states after
   history settles for at least two seconds.
3. Repeat indoors/outdoors and at near/mid/far distances on corners, cloth,
   rails, foliage, thin geometry, and moving geometry.
4. Include Cloud and another character with hair, skin, and eyes. Reject crushed
   sockets/faces, hair-card darkening, shimmer, or flicker.
5. Fast-pan and force camera cuts. Reject trails, pumping, halos, temporal growth,
   or instability.
6. Verify all five tiled direct-light consumers, capsule occlusion, contact
   shadows, SSR radiance/hit behavior, and main lighting controls are unchanged.
7. Record GPU timing and the active `e2aa...` permutation. Stop on any unmatched
   later-region shader instead of applying a fuzzy family replacement.

Reject Strong if it damages characters or indirect detail. Reject both if
Balanced already over-darkens, if the difference grows with settled history, if
SSR changes, or if any direct-light/contact/capsule path changes.

## Deterministic tooling and evidence

- `tools/Analyze-RebirthShaderInjectorPresets.ps1`
- `tools/Test-RebirthShaderInjectorPresetAudit.ps1`
- `tools/Analyze-RebirthAOArchitecture.ps1`
- `tools/Analyze-IntergradeAOArchitecture.ps1`
- `tools/New-IntergradeRebirthFallbackAOVariant.ps1`
- `tools/Test-IntergradeRebirthFallbackAOVariants.ps1`
- `tools/New-IntergradeAOReviewPackage.ps1`
- `tools/Test-IntergradeAOReviewPackage.ps1`
- `artifacts/analysis/rebirth-v2.2.1-ao-architecture.json`
- `artifacts/analysis/remake-ao-architecture-map.json`
- `artifacts/ao-rebirth-fallback-consumer-variants/`
- `artifacts/ao-rebirth-fallback-consumer-variants-test/`
- `artifacts/ao-reviewed-integration-20260901-v1/`
