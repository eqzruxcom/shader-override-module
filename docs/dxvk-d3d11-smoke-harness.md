# Isolated D3D11 replacement smoke harness

The first runtime test is deliberately smaller than a game launch. It creates a
headless D3D11 device, dispatches one compute shader, reads back one `uint`, and
reports the adapter plus result.

The two Shader Model 5 compute shaders have the same complete executable
contract: one `RWStructuredBuffer<uint>` at `u0` and a `1 x 1 x 1` thread group.
Only their math differs:

- original writes `7`;
- replacement writes `42`.

`tools/Build-DxvkD3D11SmokeHarness.ps1` compiles both with FXC, calculates the
original shader's exact 3Dmigoto FNV-1 identity, names the replacement
`<hash>-cs_replace.bin`, and requires the offline DXBC compatibility checker to
accept it. It also builds the D3D11 test executable and writes a DXVK config
pointing at the replacement directory.

`tools/Test-DxvkD3D11SmokeHarness.ps1` currently proves the native Windows
D3D11 baseline returns `7` and reports the actual loaded D3D11/DXGI module
paths. Once the patched DXVK `d3d11.dll` and `dxgi.dll` exist,
`tools/Test-DxvkD3D11PatchedRuntime.ps1` copies them only into a new workspace
test directory beside this executable and runs three cases:

1. compatible canonical replacement returns `42`;
2. missing replacement fails closed and returns `7`;
3. corrupt canonical replacement fails closed and returns `7`.

Each case also proves that the D3D11 module was loaded from the isolated test
directory. That sequence validates original identity, replacement selection,
and fallback before any game installation.
