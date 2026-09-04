# First-success automation milestone

User direction, 2026-08-31: **after the first successful in-game shader result**, switch to building the capture/control workflow before continuing with more shaders. Do not defer this until the whole shader project is finished.

Initial scope:

- Launch the game and a bounded AHK helper; verify the game and 3Dmigoto actually accept its synthetic input.
- Automate explicit test-key presses and full-screen still captures, using ShadowPlay if it works on this setup. Label each capture with the shader/settings state.
- Short videos are useful for flicker and camera-angle-dependent effects, but the user can perform movement and judge motion. Do not make automated game navigation a prerequisite.
- An optional timed W/A/S/D loop is acceptable for simple repeatable motion; it is roughly a square, not precise circular navigation. Keep the camera alone initially.
- Include a reliable emergency stop, short bounded input durations, release held keys on stop/focus loss, and do not send game inputs to unrelated windows.

This is a queued implementation milestone, **not a working or installed automation**. No AHK helper has been created or started for it. Capture availability and synthetic-input compatibility still require verification. Screenshot-based inspection is not continuous real-time vision. The installed desktop helper previously failed to initialize with a Windows sandbox/ACL error; do not assume it is currently controlling or viewing the game.

Keep the first shader as the current priority. Pause when the user's live input is needed; trust definite visual reports and request screenshots only when useful or uncertain.
