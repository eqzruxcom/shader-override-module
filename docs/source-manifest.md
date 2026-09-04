# Source manifest

Inventory date: 2026-08-29

## Rebirth Shader Injector

- Repository: https://github.com/frostbone25/ShaderInjector
- Commit: `bab25809b375f028b7c0fb603d804426f38c9b8e`
- License: MIT
- Relevant source root: `ModifiedShaders/`
- Confirmed pass families: PostProcessFinal, PostProcessFog, DirectionalLight,
  LocalLight, LocalLightIES, SSR, SampleGI, ReflectionEnvironment, OceanA,
  WaterA, and WaterB.

Representative Rebirth final-pass metadata reports `ps_6_6`, constant buffers
at `b0` and `b1`, one sampler at `s0`, and resources for blue noise, scene
color, glare, UI composition, and color-conversion LUTs. These declarations
are evidence about Rebirth only and must not be copied into the Intergrade
adapter without capture evidence.

## 3Dmigoto

- Repository: https://github.com/bo3b/3Dmigoto
- Commit: `8f329bd94fecc9bbcb9211ffd42a95dd7fe6b43e`
- License: GPL-3.0 and upstream notices
- Selected baseline: official stable x64 release `1.3.16`
- Release archive SHA-256:
  `1E097EAED99270F2444E3A70EFF68194B751F6BE19D0EDADC40A780074152558`
- Newer upstream option: `1.4.9` is a pre-release beta and is not the initial
  compatibility baseline.
- Relevant references: `Dependencies/d3dx.ini`, ShaderRegex, CustomShader,
  resource-copy, hunting, and HLSL replacement handling.

## HelixMod Intergrade reference

- Public post: https://helixmod.blogspot.com/2022/01/final-fantasy-vii-remake-intergrade-dx11.html
- Download archive SHA-256:
  `C8CB2018C851F3E2349E9EB1C32AF8CA37C81405FBA39CD39A47911A8F48896F`
- Private reference inventory: 261 ShaderFixes files, including 80 replacement
  text shaders, 52 captured pixel shaders, 10 captured vertex shaders, and 13
  captured compute shaders.
- The package includes a large UE4 ShaderRegex set and Intergrade-specific
  overrides. Original package files remain excluded from distribution.

## Target Intergrade executable

- Path used for local verification:
  `C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\ff7remake_.exe`
- SHA-256:
  `25B54C345C94EE9F6C6876B9C7537A69E6B0EEF25F322207C32A8DDCEE816635`
- File version metadata: not populated by this executable.
