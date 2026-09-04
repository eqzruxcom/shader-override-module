# DXVK D3D11 shader-replacement backend

## First scope

The first Vulkan backend targets D3D11 only. Its renderer validation order is:

1. FF7 Remake Intergrade's modified UE4 renderer;
2. stock or near-stock UE4/D3D11;
3. UE3/D3D11.

DX9, DXIL/D3D12, VKD3D, ray tracing, and geometry capture are explicitly out of
scope for the first backend. Keeping those out prevents the replacement path
from being designed around unverified future features.

## Compatibility identity

The backend identifies a shader from the **original DXBC bytes supplied by the
game**, before any replacement and before DXVK converts the bytecode. Identity
is the pair:

`(unseeded 64-bit FNV-1 over original DXBC, D3D11 shader stage)`

The canonical name is exactly `<16-lowercase-hex>-<stage>`, with `vs`, `hs`,
`ds`, `gs`, `ps`, or `cs`. This reproduces 3Dmigoto's `shader_hash=3dmigoto`
contract. Replacement bytes never change the public identity.

Official 3Dmigoto source revision used for this contract:

`8f329bd94fecc9bbcb9211ffd42a95dd7fe6b43e`

Its `util.h` initializes the hash to zero, multiplies by
`0x100000001b3`, then XORs each byte. This is FNV-1, not FNV-1a and not the
standard nonzero FNV offset-basis form.

## DXVK hook boundary

Official DXVK source revision inspected:

`adeda6639a09ad1b6a1b7c4158a781ffaf68947d`

`D3D11Device::CreateVertexShader`, `CreateHullShader`, `CreateDomainShader`,
`CreateGeometryShader`, `CreatePixelShader`, and `CreateComputeShader` all
receive the original bytecode and pass it to `CreateShaderModule`. The backend
must resolve a replacement at this boundary, before `ComputeShaderKey` and
`CreateShaderModule` inspect the selected bytecode.

The integration rule is:

1. calculate and retain the original 3Dmigoto identity;
2. resolve `<identity>_replace.bin`, then HLSL source forms;
3. validate and compile the replacement outside the render hot path;
4. verify replacement stage and complete DXBC interface/resource compatibility;
5. pass the replacement DXBC to DXVK's existing validator and converter;
6. include replacement content in DXVK's internal cache key while retaining the
   original identity for configuration, logging, and future family aliases;
7. fail closed to the original shader on absence or any validation error.

Geometry shaders with stream output need the same original identity, but their
DXVK internal key must still incorporate the stream-output declaration.

## Replacement resolver

The offline scaffold accepts these files in priority order:

1. `<hash>-<stage>_replace.bin`  compiled SM5 DXBC;
2. `<hash>-<stage>_replace.hlsl`  HLSL source;
3. `<hash>-<stage>_replace.txt`  3Dmigoto-compatible HLSL source name.

It deliberately ignores `<hash>-<stage>.bin`, because 3Dmigoto also uses that
name for captured original bytecode. This prevents a shader dump directory from
silently becoming a replacement directory.

HLSL compiler adapters and DXBC reflection/interface validation are the next
backend layer. The resolver alone does not authorize a replacement.

## Pinned integration patch

The first binary-only integration is stored at:

`src/Backends/DxvkD3D11/patches/dxvk-adeda663-d3d11-shader-overrides.patch`

It cleanly applies to the pinned DXVK revision, adds
`d3d11.shaderOverridePath`, and covers all six D3D11 shader creation paths,
including geometry shaders with stream output. It accepts only
`<original-3dmigoto-identity>_replace.bin` for now. Missing, unreadable,
invalid, wrong-stage, signature-incompatible, or resource-register-incompatible
replacements fail closed to the original shader.

The patch creates the original module first and compares input, output, and
patch-constant signatures plus accessed CBV, sampler, SRV, and UAV register
masks before accepting a replacement. It also compares exact serialized DXBC
declarations for samplers, constant buffers (including declared size/access
mode), typed/raw/structured SRVs and UAVs, and compute thread-group dimensions.
This is intentionally conservative. It verifies the executable declaration
contract available in DXBC, rather than source-level variable names that the
runtime does not need.

The replacement loader keeps immutable successful file snapshots in a
thread-safe 64 MiB cache. Every later D3D11 shader creation checks file size and
last-write time before reusing a snapshot, refreshes changed files, removes
deleted files, and verifies metadata again after each physical read so a file
changed during the read fails closed. This cache is below DXVK's existing
content-keyed shader-module cache: it avoids repeated filesystem reads but does
not duplicate compiled Vulkan modules. A file change can affect a subsequent
`Create*Shader` call; it does not retroactively replace an already-created
D3D11 shader object.

`tools/Test-DxvkD3D11Patch.ps1` clones the exact pinned revision into a unique
temporary directory, checks and applies the patch, strictly compiles the new
override loader, syntax-compiles the modified D3D11 device translation unit,
and asserts that the exported patch still contains the declaration gate. Its
native loader harness also runs 2,048 concurrent cache resolutions and verifies
cache reuse, metadata refresh, deletion invalidation, recreation, and
fail-closed absence. It uses initialized dependencies from the official source
mirror and does not install anything into a game.

## Proven identity fixtures

`tools/Test-DxvkD3D11ShaderIdentity.ps1` compiles the portable identity and
resolver code with MSVC and checks three retained, game-captured DXBC blobs:

- `0fcd2a51d59b6599-vs`  Cloud clothing/skinned-material vertex shader;
- `8b1f6ebe443b5615-ps`  paired Cloud clothing GBuffer pixel shader;
- `62b33a2d1e505241-cs`  confirmed local-light/contact-shadow compute family.

The test also ensures captured `.bin` files are ignored as replacements,
compiled replacements take priority over HLSL, and unsupported RT stages are
not accidentally admitted into the D3D11-only backend.

## Release configuration

No special stereo-stripped 3Dmigoto binary is required for the reference/native
D3D11 path. Release builds with `force_stereo=0` and `automatic_mode=0` leave
the stereo path inactive. A final user preset should disable development work:

- `hunting=0`;
- `calls=0`;
- `verbose_overlay=0`;
- `dump_usage=0`;
- shader export/cache dumping only when explicitly diagnosing.

The DXVK backend ultimately replaces 3Dmigoto's runtime injection role. Until
hash, replacement, and fallback parity are proven, 3Dmigoto remains the native
D3D11 oracle rather than a second wrapper stacked on the Vulkan runtime.

## Current gates before live game installation

The pinned MSVC build and isolated compatible/missing/corrupt runtime smoke
test are complete. The smoke result is
`artifacts/dxvk-d3d11-smoke-runs/20260901-111128`; it records separate hashed
logs and verifies exact replacement acceptance and rejection markers in
addition to the compute outputs.

The current checkpoint can be revalidated directly with:

```powershell
.\tools\Assert-DxvkD3D11OfflineEvidence.ps1 `
  -BuildManifestPath .\artifacts\dxvk-d3d11-msvc-builds\dxvk-adeda6639-x64-20260901-104957\manifest.json `
  -SmokeResultPath .\artifacts\dxvk-d3d11-smoke-runs\20260901-111128\result.json
```

The first real-game provenance gate is now satisfied. The five replacement
inputs in `dxvk-d3d11-contact-family-automated-20260901-v2` are byte-for-byte
identical to the accepted live 3Dmigoto contact-shadow checkpoint:

- `08bb8764f1840179-cs`: `3584A654C1E231ACB5C3E01CA50C8BC89F440B85320A97098B380706F76D1A83`;
- `0e97888f9a8767da-cs`: `FB8C0FA229688D79497D726832ACB00F3763324AB09389BAD1A24352BAB1AA4A`;
- `5a9fbefe0ab6f815-cs`: `421A8C026982B120AB9DDE629C529EA69C5E0B7E9A81FF30D1B4877B8DB773B0`;
- `62b33a2d1e505241-cs`: `AB3FC967FA59ADE7E6B226B439E77DC81644ADFDA8404906C1F6EB8475A17876`;
- `c30cdc8365df9840-cs`: `2B88112FF622CE972746334C19BED9F84A9C16CC17895992793FB4799A94F94E`.

The patched runtime has also created real D3D11 compute-shader objects for all
five variants in isolated compatible, missing and corrupt cases. That proves
original-identity selection plus fail-closed object-creation behavior offline;
it does not substitute for an in-game image comparison.

The exact preinstall backup and rollback boundary is now complete. The verified
snapshot is
`F:\Shader3Dmigoto\Backups\FF7Remake-DXVK-preinstall-20260902-084200-915`.
It records all eight exact install targets, preserves the existing 3DMigoto
`d3d11.dll`, records the other seven targets as absent, and separately preserves
`d3dx.ini`, `ContactShadows.ini`, and all five accepted contact-shadow HLSL
files. `tools/Assert-IntergradeDxvkLiveTestBackup.ps1` independently verifies
every copied hash, size, absence, and provenance file.

`tools/Restore-IntergradeDxvkLiveTest.ps1` refuses to overwrite a drifted
pre-existing target or delete a file that does not match the packaged DXVK
hash. Against the current native state it reports `already-restored`, with all
eight targets verified and zero changes. The guarded installer in
`tools/Install-IntergradeDxvkLiveTest.ps1` requires the exact snapshot and
bundle, verifies the native comparison context, requires explicit
acknowledgement that DXVK replaces the 3DMigoto `d3d11.dll` provider, and
refuses to run while FF7 Remake is open. Its no-write preflight resolves all
eight targets and produces zero drift.

`tools/Test-IntergradeDxvkLiveTransition.ps1` exercises the complete transition
against a disposable workspace game tree. It installs and hash-verifies all
eight package targets, restores the original DLL and removes all seven
package-created files, proves the seven native comparison files stay unchanged,
and proves rollback refuses to delete a deliberately drifted `dxgi.dll`. The
fixture uses a hard link to the reviewed executable fingerprint, cleans up only
its validated temporary root, and does not touch the real game directory.

The remaining live gates are:

1. install only the hash-closed offline bundle for a controlled test and prove
   native-3Dmigoto versus DXVK image behavior, motion stability, compatible
   replacement selection, missing fallback, corrupt fallback and rollback;
2. keep full process restart as the explicit replacement reload boundary until
   a later object-lifecycle/`*SetShader` substitution layer is implemented and
   independently validated.

The initial practical boundary is documented in
`docs/dxvk-d3d11-development-reload.md`: replacement changes require a full
process restart. A later object-lifecycle and `*SetShader` substitution layer
can provide true live reload without stealing the existing test keys.

Controlled reflection fixtures now prove that changed math is allowed while
signature, resource declaration, constant-buffer layout, and compute
thread-group mismatches are rejected. The pinned DXVK tree also has an official
Visual Studio 2022 CI path, so MinGW is not required. The first local build can
disable separate D3D8, D3D9, and D3D10 DLL targets while retaining DXGI and
D3D11. `tools/Test-DxvkMsvcBuildPrerequisites.ps1` audits the exact local state,
and `tools/Build-DxvkD3D11Msvc.ps1` stages only non-installing workspace
artifacts. A patched `d3d11.dll` and `dxgi.dll` now exist only as offline
workspace artifacts. Their build and isolated smoke tests pass, but they remain
`Installed=false` and `RuntimeEligible=false` until the remaining live-game
gates above are satisfied.

Depth-buffer AO remains a normal shader-core effect on either D3D11 or Vulkan.
Using RT cores would require captured scene geometry and Vulkan acceleration
structures; that is deferred beyond this shader-replacement backend.

## Offline HLSL adapter

`tools/Build-DxvkD3D11ShaderReplacement.ps1` compiles canonical
`<hash>-<stage>_replace.hlsl` or `.txt` source with the Windows SDK FXC compiler.
It maps the stage to the matching Shader Model 5 profile, writes to a temporary
file, verifies DXBC magic, then emits `<hash>-<stage>_replace.bin` plus a SHA-256
manifest marked `installed=false`. Its default output is a workspace artifact
directory, never a game directory.

When `-OriginalBytecode` is supplied, the adapter recalculates the exact
3Dmigoto FNV-1 identity and refuses a mismatched filename. It then runs
`DxbcCompatibilityCheck.exe` before publishing the binary. That checker allows
changed shader math but requires equal stage, input/output/patch signatures,
resource binding types, recursive constant-buffer member layouts, and compute
thread-group dimensions. A passing manifest is still marked
`runtimeEligible=false` until the DXVK runtime gate and an isolated live sample
also pass.

Captured game DXBC may retain executable `dcl_*` bindings while omitting RDEF
resource metadata. This is verified for `EDA405F2D455D5C7-ps`: reflection
reports zero resources, while disassembly declares CB0[19], CB1[123], and
t0-t2. In that case the checker still reflects stage and signatures, then
compares normalized executable constant-buffer, resource, sampler, and UAV
declarations. It reports `passed-declaration-contract-rdef-unavailable` rather
than claiming full member-layout reflection. If RDEF exists on both shaders,
the stricter recursive reflection comparison remains mandatory. A regression
also changes t2 from float to uint and proves the stripped-RDEF path rejects the
replacement with exact original/replacement declaration diagnostics.

Supplying `-FamilyCatalogPath` adds a separate reviewed-family gate. The source
stage/hash must resolve uniquely in a strict portable catalog, the selected
implementation must be D3D11/DXBC, and its permitted shader models must include
the compiler profile. The manifest records the catalog path/hash and resolved
family, implementation, identity model, variant, and version target. An unknown
or wrong-stage identity is rejected before compilation and publishes no binary.
This is optional for generic experimentation, but it is the intended publishing
boundary for generated universal-family replacements.

This adapter deliberately runs before launch or reload. The DXVK render path
continues to accept compiled DXBC only, so an HLSL compiler, file watcher, or
unbounded compilation stall cannot enter a frame.

`tools/Test-ReviewedAliasDxvkEndToEnd.ps1` exercises the real captured
`EDA405F2D455D5C7-ps` chain: the base semantic catalog rejects it, an isolated
accepted review fixture publishes a derived catalog, the exact original FNV-1
identity is verified, retained 3Dmigoto HLSL compiles with FXC, executable
declarations match the stripped-RDEF capture, and the resulting manifest keeps
the reviewed family while remaining offline and non-runtime-eligible.

After a full patched runtime build and isolated smoke test,
`tools/Stage-DxvkD3D11RuntimeBundle.ps1` can combine only those verified products
into a hash-closed, non-installing bundle. The bundle validator rejects unlisted
files, non-x64 DLLs, unreviewed replacement provenance, and incomplete rollback
coverage. It also requires, preserves, hashes, and revalidates the independent
compatible, missing, and corrupt runtime logs so numeric smoke outputs cannot
stand alone as replacement evidence.
