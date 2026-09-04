# FF7 Remake contact-shadow family on the DXVK D3D11 backend

## Status

This is offline backend evidence only. It is not installed into FF7 Remake and
is not runtime-eligible. The live 3Dmigoto package remains the visual oracle
until the user approves an in-game comparison.

The reviewed family is `tiled-surface-light-evaluation`. Its five Remake
D3D11 compute-shader variants are:

- `08bb8764f1840179-cs`
- `0e97888f9a8767da-cs`
- `5a9fbefe0ab6f815-cs`
- `62b33a2d1e505241-cs`
- `c30cdc8365df9840-cs`

These hashes identify five compatible variants of one reviewed job. They are
not a claim that every regional or later-loaded variant has already been
captured. Catalog completeness, rather than a hard-coded directory scan, is the
mechanism that scales this workflow to additional variants.

## 3Dmigoto-to-DXVK boundary

The promoted 3Dmigoto assembly uses `t120` as a controller texture. That
binding is owned by the 3Dmigoto package and is not part of the game's original
DXBC resource contract. Passing it directly to DXVK would incorrectly add a
shader binding.

`tools/Convert-MigotoTextureConstantsForDxvk.ps1` specializes the reviewed
controller reads into constants before assembly:

- controller slot 29: `[0.06, 0, 0, 0]`
- controller slot 31: `[1, -1, 1, 100]`

It removes the `t120` declaration, rejects unrecognized uses, and emits a
hash-closed evidence manifest. The resulting assembly therefore retains the
original game's executable binding contract.

## Reproducible family pipeline

The family build is catalog-driven:

```powershell
& tools/Build-DxvkD3D11AssemblyFamily.ps1
```

For each catalog target it:

1. resolves exactly one reviewed family implementation and variant;
2. requires the authoritative original captured DXBC;
3. verifies the 3Dmigoto FNV-1 identity from those original bytes;
4. specializes the 3Dmigoto-only controller reads;
5. assembles with the pinned assembler through
   `tools/Build-DxvkD3D11AssemblyReplacement.ps1`;
6. requires DXBC magic and full executable interface/resource compatibility;
7. records the family, variant, version group, tool hashes, source hashes and
   output hashes in `family-build.json`.

The authoritative automated build is:

`artifacts/dxvk-d3d11-contact-family-automated-20260901-v2`

Its `family-build.json` SHA-256 is
`0871E40D696BBF9408F8AF6C3BE7F5222FBD59D6392897510FE6897DCB777AF7`.
An independent manual build produced byte-identical replacement binaries for
all five variants.

`tools/Test-BuildDxvkD3D11AssemblyFamily.ps1` rechecks the retained positive
evidence and proves the publisher fails closed when its output already exists,
the requested family is not reviewed, or even one catalog target lacks a
source shader. This prevents a partial regional capture from being mislabeled
as a complete family build.

`tools/Assert-DxvkD3D11AssemblyFamilyBuild.ps1` is the independent publishing
gate. It recalculates every original FNV-1 identity, requires exact catalog
coverage, verifies every source/tool/output hash and child-manifest crosslink,
checks that executable assembly no longer uses `t120`, reruns DXBC
compatibility, and rejects unlisted files. Its mutation regression,
`tools/Test-AssertDxvkD3D11AssemblyFamilyBuild.ps1`, proves rejection of an
extra payload, a forged replacement hash, mismatched reviewed-family
provenance, and incomplete catalog coverage.

## Patched-DXVK runtime-object gates

`tools/Test-DxvkD3D11RealShaderCreation.ps1` loads the workspace's patched
DXVK DLLs and performs real D3D11 compute-shader creation. Every variant passed
three isolated cases:

- compatible replacement selected and shader object created;
- missing replacement falls back to the original;
- corrupt replacement is rejected and falls back to the original.

The hash-closed five-shader evidence bundle is:

`artifacts/dxvk-d3d11-runtime-bundles/FF7RemakeIntergrade-DXVKContactFamily5-offline-20260901-v1`

It contains five replacements and fifteen case logs. It has `Valid=true`,
`Installed=false`, and `RuntimeEligible=false`.

## Remaining live gate

The native 3Dmigoto contact-shadow checkpoint is now the accepted visual
oracle. Every source hash in the automated five-shader DXVK family build
matches the corresponding live accepted shader byte-for-byte. This closes the
real-FF7 replacement-provenance gate, but not the live Vulkan gate.

Do not install the bundle merely because its offline gates pass. The separate
preinstall snapshot now exists at
`F:\Shader3Dmigoto\Backups\FF7Remake-DXVK-preinstall-20260902-084200-915`.
It independently verifies the original `d3d11.dll`, seven absent package
targets, seven native comparison files, and copied bundle/rollback provenance.
The guarded installer refuses a running game, refuses native-state drift, and
requires explicit acknowledgement that the DXVK test replaces 3DMigoto's
`d3d11.dll`; it does not stack the two wrappers. The guarded restore tool only
restores the backed-up DLL or removes files whose hashes identify them as this
exact package.

The disposable transition regression
`tools/Test-IntergradeDxvkLiveTransition.ps1` passes the full eight-file install
and rollback path, preserves all seven native comparison files, and rejects a
drifted-file deletion. It reports `RealGameDirectoryTouched=false`.

The remaining controlled game test must still verify image behavior, motion
stability, compatible replacement selection, missing/corrupt fallback and an
actual rollback. The current native live comparison keeps F10 only as
3DMigoto reload and Page Down only as the injected-effects master toggle.
