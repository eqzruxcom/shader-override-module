# Shader Injector v2.2.1 preset comparison

## Result

The Performance and Maximum Quality archives each contain 158 files. Comparing
normalized relative paths and contents gives:

- 143 identical files;
- 15 different files;
- 3 different shared HLSL sources;
- 12 corresponding compiled blob differences, consisting of those same three
  pass blobs for four supported game-version groups.

The three functional source differences are:

| Shared pass | Performance | Maximum Quality |
| --- | --- | --- |
| `ComputeShaderPass_ReflectionEnvironment.hlsl` | SSGI ambient occlusion and bounce light disabled | `SSGI_AMBIENT_OCCLUSION` and `SSGI_BOUNCE_LIGHT` enabled |
| `ComputeShaderPass_SampleGI.hlsl` | character dominant-direction shading disabled | `CHARACTER_DOMINANT_DIRECTION_SHADING` enabled |
| `PixelShaderPass_PostProcessFinal.hlsl` | automatic exposure disabled | `AUTO_EXPOSURE` enabled |

There are also trivial comment-spacing differences with no runtime meaning.

## Contact-shadow conclusion

The contact-shadow HLSL and the contact-related compiled passes are identical
between the two presets. The contact-shadow port currently being tested in
Remake is therefore not specifically the Performance or Maximum Quality
variant; for contact shadows it matches both.

The four targets for `DirectionalLight`, `LocalLight`, `LocalLightIES`, and
`SampleGI` each retain one cross-version identity. Other logical families can
legitimately contain several identities: for example, WaterA changes interface
and resource identities across the supported versions. The universal matcher
must therefore treat a family as a verified set of compatible structural
variants, not assume every version of a named family has one fingerprint.

## Reproducible audit

The archive comparison is regenerated directly from the two original ZIPs,
without extracting or executing their DLL, EXE, or compiled blobs:

```powershell
& tools\Test-RebirthShaderInjectorPresetAudit.ps1
```

The analyzer verifies both archive SHA-256 values, all file counts and paths,
the exact three-source/twelve-blob difference set, all four feature defines,
all 44 fingerprint manifests, the stage split, and the per-family identity
variation. It writes the machine-readable result to
`artifacts/analysis/rebirth-shader-injector-v2.2.1-preset-audit.json`.

## Home preset control

A Home switch between Performance and Maximum Quality must not be implemented
as a contact-shadow toggle because it would be a no-op. It becomes a real
preset selector only after the differing ReflectionEnvironment, SampleGI, and
PostProcessFinal features are ported. At that point Home can select one shared
quality state consumed by all three passes while Page Down remains the master
injected-code A/B and Page Up remains the current experiment A/B.

Local archive extractions:

- `reference/external/shader-injector-v2.2.1/performance`
- `reference/external/shader-injector-v2.2.1/maximum-quality`
