# Cloud clothing contact-shadow route

Date: 2026-08-31

## Result

The tested Cloud clothing material is written by pixel shader
`8b1f6ebe443b5615-ps`. A live Page Up conditional-skip test made Cloud's
clothing disappear, confirming ownership in the tested scene. This shader is a
six-MRT material/GBuffer producer, not a deferred light or contact-shadow
evaluator.

Live shader hunting also confirmed the paired vertex shader:
`0fcd2a51d59b6599-vs`. When it was marked, 3Dmigoto logged peer shader
`8b1f6ebe443b5615`. Its retained assembly is a buffered multi-weight skinned
material/GBuffer vertex producer. It is not the separate ShadowDepth caster
pass for Cloud's clothing.

The retained DXBC establishes the following expected downstream route:

1. `8b1f6ebe443b5615-ps` builds `r1.w` only from flag bits 32, 64, and 128,
   adds 1, converts to float, and writes `(r1.w + 1) / 255` to `o2.w`.
   Therefore the low four-bit material/shading-model ID written by this
   permutation is 1.
2. Classifier `f97a821dddaa328a-cs` reads its material-ID texture, multiplies
   by 255, converts to uint, and masks with 15. IDs 1 and 5 set class mask 1;
   class mask 1 selects specialization index 1.
3. `62b33a2d1e505241-cs` is the specialization-1 tiled evaluator: it uses the
   second indirect-argument segment (offset 12 in the verified dispatch family)
   and the corresponding light-list base offset `0x8700`.
4. In the live replacement, the injected contact visibility ends in `r25.x`.
   Immediately before accumulation, that factor multiplies both contribution
   groups, `r18.xyz` and `r17.yzw`. There is no separate cloth branch after
   this multiplication that can bypass the contact term.

## What this proves

- The user's Cloud clothing shader identity is live-confirmed.
- Its retained GBuffer packing structurally routes material ID 1 to the
  specialization represented by `62b33a2d1e505241-cs`.
- The working `62b` replacement applies its contact factor to both final light
  contribution groups.

## Rejected broad-factor diagnostic

Forcing the final `62b...` contact visibility factor `r25.x` to zero made all
local lights handled by that specialization go out. The factor controls the
complete broad light contribution. Zero means fully occluded here; it was the
wrong neutral value as well as an overly broad condition. The diagnostic was
rolled back to shader SHA-256
`46BB139D3B79BD74AD77B0DF9067ACDB169D76B56DEBB5F6315D9F82CD3751C3` and
ContactShadows INI SHA-256
`7B7319AA282B23EA64FA4A0487BD4CB4ED091805E72BAF4FA77FFB3B3398FCB2`.

## Corrected material-ID diagnostic

The offline-assembled replacement at
`artifacts/clothing-material1-contact-route-diagnostic-20260901-v1` preserves
the low four-bit GBuffer material ID in `r40.x`. Page Up changes the calculated
contact visibility to neutral `1.0` only when that ID equals 1. Page Down is the
master injected-code switch. The package is not installed or runtime-approved.

- If Cloud's clothing loses added contact darkening while local-light brightness
  remains, the material-ID 1 deferred route is confirmed. The next investigation
  is scene-depth/normal/ray input or contact strength/softness.
- If Cloud's clothing does not change, another specialization/permutation or
  incomplete live dispatch coverage must be investigated.
- If complete local lights go out, the authored diagnostic is not what the
  runtime executed and it must be rolled back.

Material ID 1 is not a unique object tag. A positive result proves the material
route used by Cloud's clothing, but other ID-1 surfaces may also change. Object-
exclusive isolation would require a safe extra GBuffer marker, which is not yet
proven and is deliberately not attempted by this package.
