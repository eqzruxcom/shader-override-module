# First source-author image-adjustment port

## Confirmed integration boundary

On 2026-08-30 the final-composite assembly diagnostic passed native ASM reload and GPU shader creation, with no matched errors. The game remained responsive. The user answered **yes** to the explicit question whether the scene dims while the HUD stays unchanged. The log also recorded repeated 0/1 switches. This confirms the scene-only boundary in the tested view; it is not a global all-menu or all-scene guarantee.

## What is ported

`New-IntergradeAuthorImageAdjustments.ps1` extracts `AdjustImage`, its ten configuration defines, and `LuminanceRec709` from the pinned frostbone25/David Matos source. It compiles that exact standalone function with FXC for `ps_5_0` using strict syntax and warnings as errors. The specialized compiler output is inserted into Remake's original assembly, with separate temporary registers.

Source: `reference/ShaderInjector/ModifiedShaders/Includes/PixelShaderPass_PostProcessFinal.hlsl`.

Commit: `bab25809b375f028b7c0fb603d804426f38c9b8e`.

SHA256: `F2EAA2D047776D43AD9D8266516E9B27B0D386E7CDDB8D999CE6600AB91A4726`.

The active source defines, rather than their occasionally differing default comments, specify **brightness -0.45 EV** and **gamma 1.15**. All other AdjustImage settings are neutral. The compiler specializes the function to:

```
color *= 0.732042849;  // exp2(-0.45), rounded by FXC
color = max(color, 0);
color = exp2(log2(color) * 0.869565248); // reciprocal gamma 1.15
```

This is five arithmetic instructions. The source-author function and MIT notice are retained in the generated validation source, and the MIT notice is included as comments in the deployed ASM payload.

## Correct operation order

The adjustment is inserted immediately after the final scene texture sample into r2, **before** the original `0.01` scaling, PQ encoding, LUT color mapping, and alternate color branch. The earlier half-brightness diagnostic was after those operations and has been removed from this port. UI sampling/blending, output transfer, dithering, viewport behavior, and alpha remain original.

The off side skips the author block. It retains original math within the replacement shader; it does **not** select the native shader object. 134 original instruction/declaration tokens remain byte-identical, with only the temp-count declaration changed. All non-code binary sections are preserved. The original binary round trip is byte-identical. The new live result remains unverified.

This is a first subset, not the full Rebirth mod appearance: auto exposure, bloom changes, sharpening, custom tonemapping, inverse-ACES color-grade recovery, contact shadows, and GI are **not** included. Remake's own tone mapping stays active. HDR remains deferred.

## Staged state

- Adapter: `FF7RemakeIntergradeAuthorImageAdjustments`.
- Generated directory: `artifacts/generated-runtime/FF7RemakeIntergradeAuthorImageAdjustments-live`.
- Install manifest: `artifacts/installed-author-image-adjustments-overlay.json`.
- Backup: `backups/GeneratedRuntimeOverlay/20260830-225407-026`.
- Candidate SHA256: `01CB3652072A4F4A942CAB9D3BD5C5DC0DB3012F67CE4D8614E833407FDC364B`.
- Payload: `Mods/UE4EffectsGenerated.ini` and `ShaderFixes/41f1bf8b79d01319-ps.txt`.
- Root d3dx.ini hash unchanged; hunting=2, cache_shaders=0, ini_params=120 preserved.
- Exact game process: PID 48440, responding.
- Log baseline offset: 356306.
- First status read: `pending-no-reload`.

F10 reloads. Page Down alternates original calculations and the author preset, starting with original calculations. The scene may show a combination of darker highlights and lifted midtones; do not describe this as a uniform dimmer or guarantee the direction for every pixel.

Use `Get-IntergradeFinalCompositeReloadStatus.ps1 -GeneratedRuntimeDirectory artifacts/generated-runtime/FF7RemakeIntergradeAuthorImageAdjustments-live` after F10. It accepts this adapter and requires the exact native ASM success message, not merely INI parsing. The user should report the live appearance and whether the HUD remains unchanged.

Rollback with `Uninstall-UE4GeneratedRuntimeOverlay.ps1 -InstallManifestPath artifacts/installed-author-image-adjustments-overlay.json`, followed by F10, restores the preceding half-brightness diagnostic. That is not a clean unmodified runtime. The prior isolation rollback restores the upstream Reinhard comparison, whose state 0 uses actual original shaders.

## Checks run

`Test-IntergradeAuthorImageAdjustments.ps1` passed: pinned-source extraction, strict SM5 compilation, original token preservation, insertion ordering, removal of the old dimming probe, exact candidate hash, payload hashes, MIT notice, overwrite protection, and CPU numerical equivalence/monotonicity across negative, zero, and logarithmically spaced positive samples. CPU checks are not live GPU or pixel-parity evidence.

The non-installing staging preflight also passed before the backed-up two-file installation. No full-project suite claim is made for this turn. Early failed generator attempts are retained in their separate directories; only the `-live` directory above was installed.
