# Changelog

All notable Shader Override Module framework changes are recorded here. Game
experiments remain marked experimental until live behavior is explicitly
accepted.

## Unreleased

### Added

- Guarded automatic shader-family matching with structured rejection reasons.
- Shader-family compute and draw support used by reusable rendering adapters.
- Background input IPC for deterministic key delivery without foreground focus.
- Background screenshot IPC with an explicit foreground capture fallback.
- `clear_on_create` custom-resource option for deterministic initialization of
  descriptor-copied resources after creation, resize, or device change.
- FF7 Remake Intergrade proving adapter and fail-closed validation tooling.
- Fallout: New Vegas DX9/DXVK transport-only bundle staging with x86/x64 PE
  validation, local explicit Vulkan layers, complete file hashing, and tamper tests.
- New Vegas transport install/restore tooling with explicit acknowledgement,
  per-target backup provenance, hash verification, atomic drift refusal, and
  exact removal of package-created files.
- New Vegas full-neural candidate promotion with one x64 RenoDX consumer,
  user-supplied x64 DLSS/Neural Rendering runtimes, mode-2 configuration,
  frame-generation exclusion, and separately acknowledged reversible install.

### Verified in FF7 Remake Intergrade

- Five-member contact-shadow family.
- Left-side frustum cutoff correction.
- Character and clothing participation in the accepted lighting baseline.

### Experimental

- Screen-space indirect-light injection at the pre-temporal scene pass.
- Motion/depth-aware private temporal history for screen-space GI.

### Fixed

- Removed recursive final-scene feedback that could freeze injected lighting
  until F10 shader reload.
- Preserved F10 exclusively as the shader-reload key.
