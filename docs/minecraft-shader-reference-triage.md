# Minecraft shader references for the universal lighting work

## What the trailer frame demonstrates

The Complementary Reimagined daylight trailer frame is a useful **visual target** for:

- broad sun/sky illumination;
- soft directional-shadow presentation;
- volumetric atmosphere and aerial perspective;
- water/reflection integration;
- restrained bloom and cinematic tonemapping.

It is not the best diagnostic reference for the immediate FF7 Remake task: making a small colored practical light illuminate nearby walls and a character without lifting every dark area.

## Closest reference for colored practical lights

Rethinking Voxels is closer to that target. It adds voxelization, ray-traced occlusion checks, and colored flood-fill block lighting on top of Complementary Reimagined. Its night and interior scenes are the comparisons to retain.

The visual idea is reusable; the implementation is not directly portable. Minecraft/Iris provides a voxel light volume and block/material identifiers that FF7 Remake's existing deferred-light shaders do not expose. In Remake the practical route remains:

1. broaden the existing local-light falloff inside the authored light volume;
2. complete local-light shader-family coverage;
3. add a screen-space indirect-light pass for secondary colored bounce;
4. use a dedicated temporal/spatial denoiser to keep the result stable.

## Licensing boundary

Complementary Reimagined and Rethinking Voxels publish source, but use the custom Complementary License Agreement rather than a permissive open-source license. Treat their code as an architectural and visual reference. Do not copy it into the universal shader changer.

For reusable implementation code, prefer permissive references such as XeGTAO (MIT) and compatible SSRT/SSGI research or source after checking each repository's license.

## References

- Complementary Reimagined: https://github.com/ComplementaryDevelopment/ComplementaryReimagined
- Complementary license: https://github.com/ComplementaryDevelopment/ComplementaryReimagined/blob/main/License.txt
- Rethinking Voxels: https://github.com/gri573/rethinking-voxels
- Rethinking Voxels license: https://github.com/gri573/rethinking-voxels/blob/main/License.txt
- Complementary colored-light fog example: https://github.com/ComplementaryDevelopment/ComplementaryReimagined/blob/main/shaders/lib/atmospherics/fog/coloredLightFog.glsl

