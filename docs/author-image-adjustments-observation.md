# Author image-adjustment port: first live observation

Date: 2026-08-30.

Active stage: `artifacts/generated-runtime/FF7RemakeIntergradeAuthorImageAdjustments-live`.

The reload checker reported `passed-native-asm-and-parser-reload` at 23:03:37 UTC. Assembly loading and subsequent GPU shader creation were both seen; no matched errors were present. The exact game process remained alive and responding.

The user reported: "brightens - less brings in grey", then supplied two full-screen comparisons:

- `C:/Users/EQZITARA/AppData/Local/Temp/codex-clipboard-29b6baa3-2577-430a-a03e-c38061e1a681.png`
- `C:/Users/EQZITARA/AppData/Local/Temp/codex-clipboard-522cf3d7-a53a-453b-a8c6-e2e0b4dc7d02.png`

At the displayed size, the first image has a brighter, flatter-looking foreground; the second has deeper shadows. The visible HUD appears unchanged. The user did not label which image is state 0 or state 1, so do not assign those states solely from the filenames or this visual impression. Character movement is not evidence of the effect. No pixel-by-pixel measurement was performed.

Accepted finding: the author exposure/gamma adjustment produces a visible brightness/tonal change in this scene. The greyer appearance is consistent with lifted dark tones; it is not evidence that the saturation control was reduced. The source defines saturation=1, vibrance=0, tint factor=0, exposure=-0.45 EV, and gamma=1.15. Nonlinear per-channel gamma can change perceived color/contrast despite neutral explicit saturation.

This observation does not establish preference, full-scene/menu compatibility, exact cross-game color-domain equivalence, or reproduction of the entire Rebirth mod appearance. The original Remake tone mapping is still retained. Custom tone operators, the author's color-grade recovery, and automatic exposure remain unported to this live stage.

No runtime or preset changes were made in response to these screenshots. Keep the current Page Down comparison available. Generated manifests remain immutable pending-stage artifacts; this separate observation records the live evidence without invalidating the installed hashes.
