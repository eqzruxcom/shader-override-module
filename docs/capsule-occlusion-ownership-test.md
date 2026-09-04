# Capsule-occlusion ownership test

## Purpose

This is a focused runtime classification test for Remake compute shader
`b9e2305a994308f2`. Its assembly proves tiled capsule candidate culling and
analytical capsule occlusion, but it does not prove which visible objects own
the capsules in every scene.

The test does not disable the shader and does not inject the Rebirth contact
ray. Page Up ON changes only the final native capsule-visibility channels
`u0.xy` to their neutral value, 1.0. It preserves `u0.zw`, the `u1` candidate
list, all depth reduction and culling, and every original instruction. Page Up
OFF executes the untouched original output path. Page Down is the required
master gate around this injected edit.

Build and validate the non-installed diagnostic with:

```powershell
& tools\New-IntergradeCapsuleOcclusionOwnershipDiagnostic.ps1 `
  -OutputDirectory artifacts\capsule-occlusion-ownership-diagnostic-20260831-v1

& tools\Test-IntergradeCapsuleOcclusionOwnershipDiagnostic.ps1
```

## Runtime scene and interpretation

Use a scene containing Cloud, another moving character if available, and
nearby static geometry receiving visible soft/contact-like occlusion. Hold the
camera still first, then rotate slowly while toggling Page Up.

- A change on Cloud or another dynamic model identifies visible ownership of
  this native capsule path in that scene. It does not by itself prove the pass
  is character-only.
- A change on static receivers near a character is also expected for capsule
  shadows cast by dynamic primitives.
- No visible change means the scene has no visible capsule contribution, the
  relevant dispatch is empty, or the contribution is hidden by other terms. It
  does not overturn the structural classification.
- The test must not be interpreted as the Rebirth contact-shadow A/B. It
  isolates native Remake capsule occlusion upstream of the five surface-light
  evaluators.

The generated package remains `runtimeEligible=false` and `installed=false`
until its assembly, INI controls, and live parser load are reviewed immediately
before a user-authorized test.
