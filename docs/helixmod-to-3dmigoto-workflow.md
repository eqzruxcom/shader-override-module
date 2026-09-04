# HelixMod-to-3Dmigoto working translation

This project assumes the user's practical experience is **HelixMod shader
fixing**, especially DX9-era and UE3 work. It does not assume prior knowledge of
3Dmigoto's configuration language. Explain new controls in terms of the render
event and shader stage they affect, then give the 3Dmigoto name in parentheses.

## Direct equivalents

| HelixMod-era concept | Current 3Dmigoto/project equivalent |
| --- | --- |
| Cycle a shader and make its draw visibly wrong or absent | Shader hunting; visit a VS, PS, CS, IB, VB, or render target |
| Find the vertex/pixel pair used by one draw | Visit the peer shader; 3Dmigoto records the currently bound VS/PS combination and `ShaderUsage.txt` relationships |
| Save the shader currently being inspected | Mark/copy the visited shader into retained evidence; do not confuse the marked diagnostic with the active replacement |
| Hand-edit an assembly shader by hash | Put the replacement in `ShaderFixes/<hash>-<stage>.txt` |
| Match the same instruction structure across many variants | `ShaderRegex`; our family engine adds stage, resource, binding, output, and producer/consumer verification before applying a transformation |
| Reload the edited fix | **F10**, reserved exclusively for 3Dmigoto configuration/shader reload |
| Stop hunting and return to normal rendering | Numpad `+` (`done_hunting`) |
| Compare fixed versus original behavior | Project-controlled shader branch: Page Down for all accepted additions, Page Up for only the current experiment |

## Dumping shaders

`export_shaders=1` is the closest 3Dmigoto equivalent to automatically saving
every shader Helix sees. `export_binary=1` retains the exact original DXBC as
well as assembly output. It intercepts shaders when the game creates them; it is
not a package extractor. Therefore:

- every shader created during startup and visited areas can be accumulated;
- a shader still buried in an unloaded map/package cannot be dumped yet;
- regional shader creation in Remake remains possible;
- the cumulative census must be kept rather than clearing the folder between
  areas;
- unseen shaders can still be handled later by a verified structural family
  rule when they are first created.

The project census deliberately keeps `export_hlsl=0`. DXBC plus its original
disassembly is deterministic evidence for matching. Decompiled HLSL is useful
as a reading aid, but it is not the authoritative identity and does not need to
be generated for every shader.

## The important stage split in the current Remake scene

The confirmed Cloud clothing draw is a paired skinned material draw:

- `0fcd2a51d59b6599-vs` transforms the skinned geometry;
- `8b1f6ebe443b5615-ps` writes the clothing material into six G-buffer targets.

Those two shaders identify and prepare Cloud's material, but they do not perform
the later contact-shadow ray. The contact term is evaluated downstream by five
material/tile-specialized compute shaders:

- `08bb8764f1840179-cs`
- `0e97888f9a8767da-cs`
- `5a9fbefe0ab6f815-cs`
- `62b33a2d1e505241-cs`
- `c30cdc8365df9840-cs`

That is why the user's paired-shader instinct was correct while directly pasting
the contact calculation into the clothing VS or PS would still be the wrong
insertion point. The universal system must retain both kinds of knowledge:
which material/caster variants exist and which downstream shader actually
evaluates the lighting effect.

## Fixed key contract

- **F10:** reload only; never bind an experiment to it.
- **Page Down:** accepted injected-code master. Off executes retained original
  shader math inside every replacement.
- **Page Up:** current experiment only. Remove this branch when the experiment
  graduates.
- **F2:** separate SSGI/AO work; do not reuse it for contact or lighting tests.
- **Numpad `+`:** clear/finish shader hunting.

The active source of truth for these keys is `docs/hotkey-policy.md`.
