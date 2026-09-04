# External FF7 Game Controller

This controller lets Codex run repeatable FF7 Remake shader tests without requiring a person to press every key. It preserves the existing 3Dmigoto bindings rather than inventing a second control scheme.

## Verified behavior

- The rebuilt 3Dmigoto 1.4.9 DLL exposes per-process, named-event input channels.
- A background command is held for one input-dispatch frame, released on the next frame, and acknowledged only after dispatch.
- Offline tests prove that background `F10` and Numpad `+` virtual keys reach a real registered callback without activating the target window.
- If the live DLL does not expose IPC, the controller can fall back to one foreground virtual-key press.
- Direct `PrintWindow` capture works with the running FF7 window, including the 3Dmigoto overlay, without activating the game.

## User key contract

| Command | Existing key | Purpose |
| --- | --- | --- |
| `f2` | F2 | Current SSGI test |
| `reload` | F10 | Native 3Dmigoto shader/config reload; never repurpose |
| `frameanalysis` | F8 | Log-only frame analysis; remains available while hunting visuals are soft-disabled |
| `enter` | Enter | Menu navigation through the exact-process foreground fallback |
| `pageup` | Page Up | Current experiment or test cycle |
| `pagedown` | Page Down | Accepted effects master on/off |
| `clearhunt` | Numpad `+` | Run 3Dmigoto `done_hunting`; clear PS/VS/CS/GS/DS/HS, RT, VB, and IB selections |

The live INI's Index Buffer cycle and mark bindings were disabled on 2026-09-02 at the user's request. Their original values remain in a timestamped `d3dx.ini.pre-disable-ib-*` backup beside the live INI.

## Warning and focus contract

- Codex announces a control sequence before it starts.
- The first command waits five seconds so the user can stop or return focus to the game.
- Later commands in that same sequence use `-ContinueSequence` and do not repeat the five-second wait.
- After a meaningful gap or the end of a sequence, a new sequence gets a new warning.
- Background IPC and background captures do not need focus and do not trigger a takeover warning.

## Commands

Verify the target and delivery method without sending input:

```powershell
& .\tools\Send-FF7Input.ps1 -Command reload -DryRun
```

Start an announced sequence:

```powershell
& .\tools\Send-FF7Input.ps1 -Command clearhunt
```

Continue the already-announced sequence without another delay:

```powershell
& .\tools\Send-FF7Input.ps1 -Command reload -ContinueSequence
```

Require the rebuilt wrapper's no-focus channel and fail instead of falling back:

```powershell
& .\tools\Send-FF7Input.ps1 -Command pageup -RequireIpc
```

Capture the FF7 window without activating it:

```powershell
& .\tools\Capture-FF7Window.ps1 -Method PrintWindow
```

`Screen` capture is available as a fallback when the game is visible and unobscured.

## Tests

Parser and whitelist only; sends nothing:

```powershell
& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" .\tools\FF7-InputController.ahk --self-test
```

Isolated background IPC callback proofs:

```powershell
& .\tests\ShaderFamilyHost\Test-RemoteInputChannel.ps1 -Command reload
& .\tests\ShaderFamilyHost\Test-RemoteInputChannel.ps1 -Command clearhunt
& .\tests\ShaderFamilyHost\Test-RemoteInputChannel.ps1 -Command frameanalysis
```

The `clearhunt` test binds Numpad `+` to the real `DoneHunting` callback while hunting is soft-disabled. The rebuilt engine permits cleanup in soft-disabled mode but still refuses it when hunting is hard-disabled; this fixes the stock callback behavior that left cached IB/VB/shader selections behind.

The `frameanalysis` test proves actual `FrameAnalysis-*` directory creation, not merely a synthetic key or log marker. The rebuilt engine permits read-only frame analysis while hunting is soft-disabled, so the game's shader/IB/VB hunting visuals can remain hidden during unattended captures.

## Deployment status

The running game uses the rebuilt 3Dmigoto 1.4.9 DLL. It was installed on 2026-09-03 from `artifacts/3dmigoto-remote-input-f8-20260903-214352`; the pre-install live files are preserved at `F:\Shader3Dmigoto\FF7Remake\20260903-214544-pre-install-remote-input`. The installed `d3d11.dll` SHA-256 is `B155853614D3177CB4761C8DBC8BA80DE0152FB6E086E64CB2B5266DAF48CF1F`.

Live validation proved background `F10`, `clearhunt`, and F8 frame analysis without foreground activation. F8 created a real capture while `hunting=2` (soft-disabled). Enter intentionally remains an exact-process foreground command because it is menu input rather than an injector callback.
