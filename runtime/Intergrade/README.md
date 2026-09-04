# Intergrade runtime overlay

This directory contains only project-owned 3Dmigoto additions. The official
3Dmigoto x64 release supplies the proxy DLL, compiler DLL, and base `d3dx.ini`
when the staging script runs.

Current keys:

- `F3`: toggle the cached rolling A/B pair (Previous / Current).
- `F6`: temporary global light-fog on/off toggle used during current validation.
- `F7`: cycle the selected tonemap once the post-process replacement is active.
- Numpad `0`: toggle 3Dmigoto hunting overlay.
- Numpad `1` / `2` / `3`: previous / next / mark pixel shader.
- `Insert` / `Home` / `Page Up`: previous / next / mark render target.
- `F8`: capture a log-only frame analysis (no texture readback).
- `F10`: reload configuration and shaders.

The staged original-first wrapper for verified compute pass
`ef7fe8d9c4e9ad15` replays the game's dispatch, snapshots `u0` into a temporary
SRV at `t113`, and runs a hardcoded post variant back into `u0`. Shader-side
IniParams bindings were tested and rejected because nested custom dispatches did
not receive reliable values. Runtime selection therefore happens in 3Dmigoto
command lists and chooses independently compiled variants.

The current F3 pair targets downstream reflection composite
`e2aa1c8cb39e0a55`: Previous is game-original and Current is the strict-compiled
100% SSR-radiance replacement candidate. Draw 1096 consumes the exact resource
handle written by SSR producer `b2bc6059f9a39c7f` on draw 1095. The preceding
radiance-presence probe was positive: cyan marked reflective/specular-facing
scene pixels while black regions had no SSR RGB contribution above the probe
threshold. Native-resolution neutral parity for the current 100% replacement is
the active gate before 0% and 50% strength testing.

The custom full-resolution temporal-SSAO shader `a77b589dce5822d6` is already
live-verified. X/Y carry current and reprojected AO visibility, while zero-Z/W
produced no observable presentation change. Its strength control moves only
X/Y toward neutral visibility 1.0 and preserves temporal metric Z and signed
depth W unchanged. Live 50% behavior is strongest on nearby geometry because
the original pass is view-depth weighted.

The UI-safe `af6cd28a0108a18a` scene-color pass has a strict-compiled
0/25/50/75% saturation matrix. Grayscale, 50%, and 75% are live-verified and
monotonic while the HUD remains colored. These are linear RGB interpolation
coefficients, not perceptually uniform saturation percentages.

The fog source pass blends 15% current scattering and 85% history, so its post
multiplier is `target / (0.15 + 0.85 * target)`, not the target itself. Zero,
25%, and 50% are live-verified; 75% is strict-compile verified. F6 remains a
temporary independent zero-scattering test layer. F7 is inert until a separate
tonemap replacement is integrated.

After an `F8` capture completes, analyze the newest capture with:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Analyze-IntergradeCapture.ps1
```

The default `LogOnly` profile records the Direct3D call and shader timeline
without copying every render target or depth surface. This avoids the old
3Dmigoto 1.3.16 resource-dump path that can stall or crash this game.

After the log identifies a narrow draw range, an explicit render-target
capture can be staged with `-CaptureMode RenderTargets`. That profile still
omits depth dumping and DDS fallback:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Stage-IntergradeRuntime.ps1 -CaptureMode RenderTargets
```

The analyzer links available render-target metadata to live PS/VS/CS hashes
and ranks likely fullscreen/final-pass candidates for controlled skip testing.

For broad UE4-family discovery, stage a diagnostic build with automatic DXBC
assembly export:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Stage-IntergradeRuntime.ps1 -ExportShaders
```

After installing that staged build and restarting the game, classify exported
shaders against all 204 Universal UE4 patterns with:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Match-UE4ShaderFamilies.ps1
```
