# Contact-shadow light binding audit

Date: 2026-09-03

## Result

The five accepted FF7 Remake Intergrade tiled local-light compute shaders expose
the data required to trace toward a local light, but this audit did **not** find
a verified physical emitter/source radius suitable for penumbra control.

The common light path reads:

- `cb4[light + 0].xyz`: local-light position.
- `cb4[light + 0].w`: inverse attenuation radius; the native shader squares it
  and uses it in distance attenuation.
- `cb4[light + 512].xyz`: light color.
- `cb4[light + 512].w`: a branch/flag used by the native attenuation path.

The same field pattern occurs in all five accepted compute variants:

- `08bb8764f1840179-cs`
- `0e97888f9a8767da-cs`
- `5a9fbefe0ab6f815-cs`
- `62b33a2d1e505241-cs`
- `c30cdc8365df9840-cs`

## Donor behavior

The retained Rebirth contact tracer names the inverse-radius input
`DeferredLightUniforms_InvRadius`. It converts that to an attenuation radius only
to reserve a small exclusion region around the light and limit the maximum
screen-space ray distance. It does not identify that value as a light-source
size and does not derive a physical penumbra from it.

## Consequence

Do not reuse inverse attenuation radius as an emitter radius. Doing that couples
shadow softness to the light's range and changes native attenuation behavior;
the rejected local-light falloff experiment already demonstrated why those
controls must remain separate.

The next softness candidate should therefore use an explicit virtual source
radius and preserve all native light fields. It should grow the penumbra with
blocker/receiver separation, so near-contact character detail remains sharp
while separated sword and scenery shadows can soften. It remains an offline
candidate until numerical tests pass and a Page Up visual comparison is ready.

The existing eight-ray prototype in
`src/Effects/Lighting/RebirthContactSoftness.hlsl` already follows the field
separation rule, but its fixed sample count, spatial pattern, cost, and motion
quality are not approved.
