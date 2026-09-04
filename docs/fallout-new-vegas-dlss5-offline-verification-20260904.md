# Fallout: New Vegas DLSS5 offline verification — 2026-09-04

Branch: `DX9`

## Scope

This receipt covers the portions of the Fallout: New Vegas proof that can be
verified without a local game installation or the user-supplied DLSS 5 Neural
Rendering runtime. It does not claim live transport or live neural rendering.

## Reproducible source build

Validated component artifact:

`artifacts/fallout-new-vegas-dlss5-component-builds/fnv-feeder-0.12.0-repro-v2`

- DLSS5-Feeder revision:
  `792755324574ff4703eb441a7bc14c724e125b84`
- Vulkan-Headers revision:
  `ee2ec5fd83dafce291024683b50dc89219333076`
- NVIDIA DLSS SDK revision:
  `a291cc7d2cc642a51566f3dfd5376f635cd1b284`
- MSVC toolset: `14.44.35207`
- Compiler version: `19.44.35228.0`
- Linker version: `14.44.35228.0`
- Link reproducibility option: `/Brepro`
- Independent build passes: 2
- Byte-identical outputs: yes

Validated outputs:

| Output | Architecture | SHA-256 |
| --- | --- | --- |
| `dlss5-feed.addon32` | x86 | `BD94A1CA136E10CA7B225BA07F32514F6B357458D8B3E43823BFF349C93ED3C6` |
| `VkLayer_feed_vk32.dll` | x86 | `E7CAFE3066CC36621C7EFE78764F71005C7291830DF78B2CEF7267547AC72C8C` |
| `dlss5-feed-host64.exe` | x64 | `E5C29C3F9C3E78ADD581A1E1D02D40140548109521748CCF8EF28185A9B8D04F` |
| `VkLayer_feed_vk.dll` | x64 | `1FC862CAD2E4B2965BBB3FD8239B5CA4258761E85A5FF1CC37944017E8B3EB3C` |

The component validator re-hashes every file, verifies PE architecture,
requires the dependency lock, build logs, toolchain identity, two-pass receipt,
and rejects unlisted files. Its tamper test passed against the artifact above.

## Hash-closed transport package

Validated transport artifact:

`artifacts/fallout-new-vegas-dlss5-bundles/fnv-dlss5-transport-20260904-v5-repro`

- Package file count: 27
- Mode: transport-only (`mode=1`)
- Handoff: same-frame (`async_home=0`)
- Component build:
  `fnv-feeder-0.12.0-repro-v2`
- Component manifest SHA-256:
  `7624033ABB89A56AF0C26FB9EE73002CA88FB6409BAECE2DBED38966094743F2`
- Dependency lock SHA-256:
  `10D243E28549269FF9DB93927C6D33E7E1E9D4E008758379CEF99C6EA2C1CB4A`

The package validator proves that the bundled Feeder add-on, helper, Vulkan
layer, effect, and layer manifest match the copied source-build receipt. It
also verifies every package hash, rejects unlisted files, enforces the x86/x64
boundary, requires both explicit Vulkan layers, and excludes neural and frame
generation payloads from transport-only mode.

## Test suite result

The following scripts all passed in one clean sequential run:

1. `Test-FalloutNewVegasDlss5Bundle.ps1`
2. `Test-FalloutNewVegasDlss5FullBundle.ps1`
3. `Test-FalloutNewVegasDlss5Install.ps1`
4. `Test-FalloutNewVegasDlss5FullInstall.ps1`
5. `Test-FalloutNewVegasDlss5ComponentBuild.ps1`

The covered negative cases include payload tampering, unlisted files, wrong PE
architecture, re-hashed mutation of inherited transport content, conflicting
neural consumers/frame-generation files, missing acknowledgements, target
drift, incomplete backups, and unsafe restore behavior.

## Gates not yet passed

The validated transport manifest correctly records these as false:

- `gameInstalled`
- `liveTransportPassed`
- `neuralConsumerPresent`
- `ngxRuntimePresent`
- `fullDlss5Passed`

Completion therefore still requires:

1. A local Fallout: New Vegas installation and executable fingerprint.
2. A live mode-1 run proving DX9 -> DXVK/Vulkan -> ReShade/Feeder x86 ->
   host64 transport with logs and visible split output.
3. A legally obtained x64 RenoDX DLSS5 consumer and matching
   `nvngx_dlssnr.dll`; ordinary `nvngx_dlss.dll` is already available from the
   pinned NVIDIA SDK.
4. Promotion to the hash-closed mode-2 full-neural candidate.
5. A live run proving Feature 18 creation/evaluation and increasing neural
   frame counters.
6. Generic Depth and non-zero motion-vector validation before image-quality
   conclusions.

## FF7/D3D11 isolation

The New Vegas scripts and schema are confined to
`src/Adapters/FalloutNewVegas`, `tools/*FalloutNewVegas*`, ignored `artifacts`
subtrees, and New Vegas documentation. No FF7 adapter, D3D11 backend, shader
family, live INI, or runtime file is part of this proof package.
