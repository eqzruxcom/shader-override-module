# Runtime A/B hotkey policy

Date adopted: 2026-08-31

This policy applies to every effect and experiment in the Universal Unreal
Engine Shader Changer, including the current FF7 Remake adapter.

## Required controls

- **Page Down - master injected-code A/B.** State A runs every accepted block
  of code we added. State B skips every block of code we added and executes
  only the untouched original shader logic retained in each replacement file.
  This is the authoritative whole-project comparison key.
- **Page Up - current-work A/B.** One press disables only the shader feature
  currently being developed; the next press restores it. All other accepted
  replacements remain unchanged.
- Both controls are binary toggles. Feature strength presets belong on other
  keys and must not overload either comparison key.
- Every injected block must be surrounded by the Page Down-controlled
  condition. The OFF branch must contain no altered math: execution falls
  through the retained original shader instructions.
- Ctrl+Page Up remains available to 3Dmigoto's render-target hunter; the project
  toggle uses unmodified Page Up.

## Explicitly excluded comparison path

- 3Dmigoto's `[Hunting] show_original` binding is disabled. It was never
  verified as an exact comparison for this project and must not coexist as a
  second project A/B system.
- F9 is therefore not part of the project's shader-comparison workflow.

## Cleanup and implementation status

1. **Completed 2026-08-31:** the live Page Down binding for the author
   image-adjustment/final-scene comparison was removed. The user observed that
   experiment as the confusing "fog thing". Page Down currently has no active
   binding and remains reserved for the generated master branch.
2. Implement the Page Down condition around every injected code block in every
   active replacement. OFF must skip those blocks and preserve the original
   instructions for every covered hash.
3. Bind only the next active experiment to Page Up and default it to OFF unless
   the user explicitly chooses otherwise.
4. Remove obsolete experimental key blocks, temporary probes, dead parameters,
   and abandoned replacement instructions from the live payload. Preserve
   original disassembly headers and all accepted working shader code in the
   project/checkpoints before cleanup.
5. Keep disabled `.bak` and historical artifacts out of the live runtime's
   active include chain; do not treat historical evidence as active code.

## Current live inventory

Status revalidated 2026-09-01 after restoring the promoted successful contact
baseline:

- `Mods/UE4EffectsGenerated.ini` does not own Page Down. The sole active Page
  Down binding is in `Mods/ContactShadows.ini` and toggles
  `$ue4fx_master_injected_v1` between 0 and 1.
- All five active contact replacements load that master from `t120[31].x` and
  guard only their injected contact block. OFF falls through to the retained
  original Remake shader instructions.
- The accepted `//Frustum Fix` remains in `62b33a2d1e505241-cs.txt`.
- Page Up is free: no active replacement consumes the Page Up experiment slot.
- `d3dx.ini` has no active `show_original` binding. F10 remains reload-only.
- The authoritative current audit is
  `artifacts/runtime-toggle-audits/20260901-164027-570/manifest.json`: five
  active shaders, five Page Down guards, zero Page Up experiment shaders.
- Do not install `working-code/Frustum Fix/20260831-v1/accepted-runtime` as a
  complete live baseline. Its manifest says `parked-not-installed`, and its
  historical INI predates the promoted Page Down wiring. Use the six hashes in
  the authoritative audit above when restoring the promoted successful state.

## Acceptance checks

- Screenshot or frame-hash comparison proves Page Down OFF matches the same
  scene with the project additions absent.
- Page Up changes only the current feature and leaves accepted effects intact.
- Repeated Page Down and Page Up presses do not accumulate state or require F10.
- Numpad shader hunting and Ctrl+Page Up render-target hunting still work.
- The live INI contains exactly one active unmodified Page Down binding and one
  active unmodified Page Up binding.
