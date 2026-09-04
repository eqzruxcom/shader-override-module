# 3Dmigoto native-D3D11 release runtime

3Dmigoto remains the native-D3D11 reference runtime while the DXVK backend is
being proven. The current binary already supports release operation; no
separate stereo-stripped DLL is required. Stereo work is inactive with
`force_stereo=0` and `automatic_mode=0`.

The release candidate changes only four diagnostic/development settings:

- `calls=0`;
- `hunting=0`;
- `verbose_overlay=0`;
- `dump_usage=0`.

It deliberately preserves `allow_check_interface=1`. That setting controls
D3D11.1 device/context interface compatibility, not 3D Vision work. It also
preserves all reload keys, shader overrides, mod includes, and stereo-disable
settings.

`tools/New-Intergrade3DmigotoReleaseIni.ps1` stages an offline candidate and a
hash manifest under `artifacts/3dmigoto-release-ini-candidate-20260831-v1`.
The manifest records whether the game was running and always records
`installed=false`; the generator never writes to the game directory.

`tools/Test-Intergrade3DmigotoReleaseIni.ps1` verifies the four-setting change
against an isolated fixture and confirms that shader-override content survives
unchanged.
