# DXVK D3D11 MSVC build readiness

## Confirmed official path

The pinned official DXVK revision contains a Windows CI workflow that builds
with Visual Studio 2022, Meson, MSBuild, and glslang. A MinGW cross-compiler is
therefore not required for this first Windows-native backend build.

The official workflow builds every API target and downloads legacy D3D8 SDK
headers. Our first backend needs only DXGI and D3D11, so the reproducible local
configuration disables the separate D3D8, D3D9, and D3D10 DLL targets:

```text
-Denable_dxgi=true
-Denable_d3d11=true
-Denable_d3d10=false
-Denable_d3d9=false
-Denable_d3d8=false
```

This does not remove D3D10 compatibility implemented by `d3d11.dll` itself.
DXVK's `src/d3d11/meson.build` always compiles the internal D3D10 interface
sources into D3D11. It only avoids building the separate `d3d10core.dll` target
and avoids unrelated D3D8/9 dependencies.

## Local state

Already present:

- pinned official DXVK source and initialized submodules;
- Visual Studio 2022 Native Desktop Build Tools and MSBuild;
- Python 3;
- the cleanly applying D3D11 shader-override patch;
- strict compile coverage plus a native concurrent test for its bounded,
  refreshable replacement-file cache.

The reviewed workspace-local Meson and glslang inputs are now staged and pass
the prerequisite audit. They remain isolated below `artifacts/toolchains` and
are not installed system-wide or into a game.

The acquisition state is recorded in
`src/Backends/DxvkD3D11/toolchain-inputs.json`. Meson 1.12.0 is pinned to its
exact official PyPI wheel, byte size, and SHA-256. glslang 16.5.0 is pinned to
Khronos' versioned Windows x64 release archive and the SHA-256 published with
that GitHub release. This deliberately avoids DXVK CI's mutable helper-binary
URL. The staging script validates the archive before extracting only the
standalone compiler.

No dependency has been installed or downloaded automatically. Run
`tools/Test-DxvkMsvcBuildPrerequisites.ps1` to produce the current structured
readiness result.

`tools/Acquire-DxvkMsvcBuildPrerequisites.ps1` is the separate network boundary.
Without `-AllowNetwork` it exits before creating a directory. With explicit
authorization, it permits only the two HTTPS hosts recorded for these inputs,
downloads to a partial file below `artifacts/downloads/dxvk-msvc`, verifies the
reviewed byte length where available and both SHA-256 values, and refuses to
overwrite a mismatched file. `-Stage` passes the verified local files to the
non-network staging script. It never installs system-wide or into a game.

```powershell
.\tools\Acquire-DxvkMsvcBuildPrerequisites.ps1 -AllowNetwork -Stage
```

`tools/Stage-DxvkMsvcBuildPrerequisites.ps1` can later accept a local Meson
wheel and a local standalone glslang executable. It uses pip with `--no-index`
and `--no-deps`, hashes both inputs, and stages them only beneath
`artifacts/toolchains/dxvk-msvc`. It contains no downloader, performs no
system-wide installation, and writes nothing into a game. The readiness audit
and builder automatically recognize that workspace-local toolchain.

The staging command must pass both recorded hashes:

```powershell
.\tools\Stage-DxvkMsvcBuildPrerequisites.ps1 `
  -MesonWheel <local-wheel> `
  -GlslangArchive <local-release-zip> `
  -ExpectedMesonSha256 71f133147fa0fcfe8f4df49fa1045771064947834538409e5d97b3613aac8b4e `
  -ExpectedGlslangArchiveSha256 06b71298b750268c127f2ee7ae0ef7525e2068120c6c8a3a08b2f58ca6f325ce
```

## Build behavior

`tools/Build-DxvkD3D11Msvc.ps1` is intentionally non-installing:

1. verifies the exact pinned source revision and submodules;
2. refuses output outside this workspace's `artifacts` directory;
3. exports the exact committed root and every exact committed submodule tree,
   ignoring any local edits in the source mirror;
4. checks and applies the pinned patch to that copy;
5. imports the x64 Visual Studio environment;
6. configures a release Visual Studio solution for DXGI plus D3D11 only;
7. builds and stages only `d3d11.dll`, `dxgi.dll`, and available PDBs;
8. writes SHA-256 provenance with `Installed=false` and
   `RuntimeEligible=false`.

It contains no downloader and no game-directory path. Missing tools fail before
source staging or compilation.

A clean patched build at
`artifacts/dxvk-d3d11-msvc-builds/dxvk-adeda6639-x64-20260901-104957`
completed with zero errors. Its isolated runtime test at
`artifacts/dxvk-d3d11-smoke-runs/20260901-111128` loaded the compatible
3Dmigoto-style compute replacement (42), retained the original shader when the
replacement was missing (7), and failed closed to the original shader when the
replacement was corrupt (7). Each case has a separate hashed D3D11 log. The
test requires the compatible log to contain the exact replacement-accepted
marker, the missing case to contain neither an acceptance nor rejection marker,
and the corrupt case to contain the exact rejection marker without acceptance.
Both artifacts remain non-installed and non-runtime-eligible.

`tools/Assert-DxvkD3D11OfflineEvidence.ps1` independently revalidates the
pinned revision and patch, toolchain provenance hashes, exact x64 DLL hashes,
smoke-to-build hash linkage, three expected outputs, and all three hashed log
markers. It passes on the build and smoke paths above without requiring a
replacement bundle or touching the game.

The builder applies the patch with an explicit `git apply --directory` target
and asserts that `d3d11_shader_override.cpp` exists in the exported source
before configuring Meson. This is necessary because the exported tree lives
under the workspace repository: relying on PowerShell's provider location or
`git -C` with `--no-index` can otherwise target the parent checkout. The
pipeline regression test requires both safeguards.

Game installation still requires native-3Dmigoto versus DXVK identity and
replacement parity on reviewed FF7 shaders, plus a verified backup and rollback
boundary.

Visual Studio 17.14's SDK validation target incorrectly treats the optional
UAP `UAP.props` file as the sole proof that Windows SDK 10 is installed, even
for this desktop-only build. The builder therefore verifies the selected
SDK's desktop header and x64 import library directly, then writes a build-local
`Directory.Build.targets` that marks desktop support and supplies the same
validated SDK directories to the C++ compiler, resource compiler, and linker. It does not suppress
validation unless both desktop files exist, and it does not modify the system
SDK or Visual Studio installation.

The build-local targets also restore MSBuild's `IncludePath` and `LibraryPath`
properties. This is required because `SetBuildDefaultEnvironmentVariables`
otherwise replaces the process environment with the incomplete SDK paths just
before Meson's custom resource action runs.

Meson's Visual Studio backend runs `rc.exe` through a generated custom command,
so the builder also restores those validated desktop include paths to the
process `INCLUDE` value before Meson captures the command environment.

## Runtime-bundle boundary

`tools/Stage-DxvkD3D11RuntimeBundle.ps1` is the next non-installing boundary. It
accepts only the two DLLs named by a passing pinned build manifest, a passing
patched-runtime smoke result whose DLL hashes match that build, and one or more
reviewed replacement manifests that verified the original 3Dmigoto identity and
the DXBC compatibility contract. It stages only `d3d11.dll`, `dxgi.dll`,
`dxvk.conf`, canonical `ShaderFixes/*_replace.bin` payloads, and immutable
provenance under the workspace `artifacts` directory.

The bundle stage also requires all three compatible/missing/corrupt smoke-log
records, re-hashes their source files, validates their exact loader markers, and
copies the logs into `provenance/smoke`. The bundle validator re-hashes and
rechecks those copied logs; its regression test proves a modified log is
rejected.

`tools/Assert-DxvkD3D11RuntimeBundle.ps1` verifies every listed hash and size,
rejects unlisted files, verifies both DLLs are x64 PE images, pins the Remake
adapter/executable fingerprint, and requires a complete rollback plan. The
result remains `Installed=false`, `RuntimeEligible=false`, and
`gameDirectoryTouched=false`. It contains no installer and cannot write to a
game directory. Its strict shape is recorded in
`src/Backends/DxvkD3D11/runtime-bundle.schema.json`.
