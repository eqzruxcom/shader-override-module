# Contact-shadow refinement: current constraints

Runtime-control policy: `docs/runtime-toggle-policy.md`. Page Down is the sole
master A/B control. Page Up is temporary current-test code and must be removed,
along with its variable, binding, and branch, when a test graduates into the
retained effect.

## User priorities, 2026-08-31

Current live test: `artifacts/contact-frustum-everything-only-20260831-v1`.
User accepted preset 2 (LEFT opacity 0 at edge, full at 6%), then requested
that the workaround be saved separately while shader coverage is investigated.
Saved version: `working-code/Frustum Fix/20260831-v1`, labeled `//Frustum Fix`.
Pre-fade shaders were restored via `artifacts/contact-pre-frustum-restored-20260831-v1`.
Latest request: apply the saved fade ONLY to 62b33a2d1e505241, the shader the
user labeled "everything" during output isolation. This does not prove that
the shader is static-only. Dynamic versus non-dynamic issue scope is unconfirmed.
Installed one annotated shader and its INI override (x29=.06, y29=0).
The other four contact shaders remain byte-identical to the pre-fade versions.
All ten protected files, including the user's clothing shader, remain unchanged.
The annotated shader assembles byte-identically to the validated fade candidate.
Old contact hotkeys (including Home and numeric edge presets) are disabled;
contacts default ON. F9/F10 and unrelated controls remain untouched.
Completed configuration and shader reloads were observed in the native log;
installed and protected hashes still match (see current package reload-check.json).
The single-variant visual result is pending. The user's earlier acceptance of
preset 2 is not proof that this narrower application fixes the issue.
No temporal buffers, blur, native-shadow or global strength edits were added.
After this bounded comparison, follow the recorded A-D order below.

User subsequently said to keep working and clarified A as literal header copying.
Original disassembly headers have now been copied above all five modified contact
shaders, retaining the Frustum Fix comment on 62b33a2d1e505241. All five before/after
assemblies compile to identical bytecode. Existing 41f1bf8b79d01319 headers and
user-edited 8b1f6ebe443b5615/e70021f467623b89 files are unchanged. No INI changes.
Current installed hashes supersede the one-variant receipt's text-file hashes;
see `artifacts/shader-header-restoration-20260831-v1/receipt.json`.
The main candidate generator now copies the original header when emitting its
modified shader, while retaining instruction-only normalization for matching.

- Latest scope correction: user said "lets not go crazy" in response to the
  proposed surface-age/history approach. PARK native temporal-history work and
  targeted motion capture. Keep cutoff refinement to the existing spatial
  left-edge fade for now. Do not install new history buffers or capture INIs.
  This simpler scope does not promise a fixed 0.2-second fade-in.

- The current contact-shadow shading looks good on Cloud. Preserve it.
- The sharply defined shadow cast near the sword tip onto the ground is the
  softening reference, not the blade's surface shading.
- Do not apply global softening or global strength changes that alter the
  character appearance the user wants to keep.
- Contact-shadow strength / distance falloff is NEXT, after the current
  screen-edge fade / softening work; leave that curve unchanged for now.
- True 0.2-second fade-in remains requested for screen-edge snap-in. A spatial
  fade is not a timed fade. Motion history/reprojection integration is unresolved.

## Current isolated work

### Live Page Up softness comparison, 2026-09-01

The user subsequently motion-tested the accepted 62b-only Frustum Fix by
running and spinning and reported that it works phenomenally: the edge behavior
became unobtrusive enough to forget it was occurring. This is strong live
evidence for the tested 3840x2160 scene and current camera settings. It is not
proof for every aspect ratio, letterboxed viewport, or FOV. The implementation
uses normalized active-viewport width, so its intended invariant is the leftmost
6 percent of that viewport rather than a fixed pixel count.

The exact accepted Frustum Fix branch was preserved in
`artifacts/contact-softness-combined-development-20260901-v1`. Its rebuilt 62b
baseline is byte-identical to the accepted binary
`B7AA425C5AFB42171E3C3F7E4F1CBF4921EED472A126064367EA975331D3A2DF`.
The combined Page Up candidate is
`D7279079727272E07AC93F4367CB48B58EA0B4E1D691F98DAC117207188C4879`.
The updated eight-ray helper again passed 2,048 GPU numerical checks: the
analytic transition widened from 22 samples at blocker distance 1 to 51 samples
at blocker distance 3, with no non-monotonic steps and no interior weakening.

Installed package:
`artifacts/generated-runtime/FF7RemakeIntergradeContactSoftness62b-live-v1`.
Rollback:
`artifacts/live-rollbacks/contact-softness-62b-20260901-104226-498`.
Only `62b33a2d1e505241-cs.txt` and `Mods/ContactShadows.ini` changed. Page Down
remains the master for all five contact shaders. Page Up defaults OFF and selects
the eight-ray virtual-emitter path only for 62b, initially at radius 5 engine
units. Page Up OFF executes the exact accepted hard trace plus Frustum Fix. The
other four shader files were fingerprinted before and after installation and
were not changed. Live reload, visual quality, motion stability and cost remain
pending user validation.

Refinement fork: `artifacts/contact-edge-softness-development-20260831-v1`.
The exact header `//Remake Left Side Frustum Fix` was added to the top of
`ContactEdgeFade.hlsl` and `RebirthContactSoftness.hlsl` in this fork only.
The label does not establish engine frustum culling as the verified cause.
Preserved donor and live game files were not changed by these edits.

`artifacts/soft-profile-baseline-v1` under the fork passed 2,048 offline WARP
checks of the existing eight-ray virtual-emitter prototype. It widened an
analytic hard edge while retaining the interior. This is synthetic evidence,
not game rendering, performance approval, or proof that Cloud is unaffected.
The helper is now connected only in the isolated 62b Page Up candidate described
above. Do NOT connect it globally now that preserving character shading is an
explicit requirement.

## Follow-up requirements recorded 2026-08-31

- Cutoff work first; clothing/family coverage and header restoration afterward.
- User's explicit order AFTER the cutoff fix:
  A. Restore the missing headers across all generated shader files.
  B. Investigate the Rebirth author's implementation and what our port misses.
  C. Inspect the 3Dmigoto Universal UE4 fix and compare its shadow-family rules
     with our existing implementation; use it as a coverage reference.
  D. Dump shaders again and investigate gaps. A runtime dump covers encountered
     shaders, not proof of every shader in unvisited game areas.
  These are queued, not completed; do not start D during the cutoff comparison.
- User identified `8b1f6e` by adding output: live filename resolves to
  `8b1f6ebe443b5615-ps_replace.txt`. User observation: clothing shader. Preserve
  their edit; do not overwrite it or claim it proves a contact-shadow hook.
- User has extensive DX9/3D Vision shader-patching experience. Use their live
  identifications as evidence and examine native specialized shadow paths, not
  only the five downstream tiled-lighting compute variants.
- Restore useful headers across generated shaders after the cutoff task. The
  current generator strips // lines in Read-Instructions; retain normalization
  for matching but re-emit identity, interface, provenance and patch information.
- Universal workflow must discover and generate fixes for compatible variants
  newly encountered beyond section 1, not rely only on the initial hash list.
  Reconfirm in another area before promoting a family rule; inspect the existing
  universal reference when coverage work resumes. Large shader counts are a
  scaling requirement, not evidence that a fixed number exists in every title.

## Temporal component: isolated implementation

`ContactEdgeTemporal.hlsl` in the refinement fork implements a maximum darkening
rate of 1 / 0.2 seconds, with immediate release, missing-history initialization,
stall reset and exact valid-input interior bypass. It needs persisted history
with verified surface/light correspondence. It is NOT included by the native
adapter or installed. Its API requires edge-dependency tracking to survive the
end of the spatial fade band; otherwise leaving that band can create a new pop.
`tools/Test-ContactEdgeTemporal.ps1` checks this math with analytic histories;
passing it cannot establish native temporal integration or game motion quality.

Evidence added during the cutoff continuation:

- `artifacts/contact-edge-temporal-math-20260831-v2/manifest.json`: 2,048 WARP
  numeric results. Full-range rise takes 0.2 seconds at 30/60/90/120/240 FPS and
  the next frame at 144 FPS (29 frames, 0.201389 seconds). Partial-strength
  targets arrive sooner at the same bounded rate; this is not a fixed-duration
  interpolation to every partial target.
- `artifacts/contact-edge-temporal-history-20260831-v3/manifest.json`: actual
  separate D3D11 dispatches with two alternating history resources, 1,740 frames
  across six frame rates / five synthetic scenarios and 111,360 receiver checks.
  Includes synthetic receiver movement, leaving the spatial band while pending,
  loss of a hit, replacement receiver/light identities, invalid reprojection,
  camera-cut reset and long-stall reset. This does NOT use native motion vectors
  or prove game motion quality.
- The first history fixture exposed flags folded to zero in a float constructor.
  Metadata is now kept as uint throughout the structured history buffer; only
  darkness is bit-cast at the arithmetic boundary. Failed v1/v2 evidence remains.
- Current live baseline rechecked: all 11 pre-isolation files still match.
  The log after the restoration offset contains successful reload messages.
  No temporal code was installed and the user's clothing output edit was not
  touched. No new F10 or other keypress is needed for these offline tests.

PARKED after the user's scope correction: choose and verify the native history
boundary only if this approach is explicitly resumed, before any live candidate.
The contact helper executes per light, so a single history value per screen
pixel must not silently blend different lights or overwrite other light passes.
Verify resource bindings, stable light correspondence, moving-receiver motion,
depth/normal rejection, per-frame initialization/swap and memory cost. The
fixture's explicit integer receiver/light keys are test inputs, NOT identified
Remake bindings. Preserve native shadows and unaffected interior contacts.
Softness and range falloff are unchanged and remain separate tasks.

## Receiver-preservation integration gate

Distinguish the RECEIVING surface (where the shadow is drawn), not merely the
casting object: Cloud's sword can cast a softened shadow on the ground without
softening shadows drawn on Cloud himself, if a reliable receiver mask exists.
The current native adapter has normal, material, depth, view and light inputs.
Its material decode distinguishes shading models and provides a special hair
bias; that is not proof of a complete character/object identity mask. Hair-only
exclusion would still leave skin, clothing, weapons and armor exposed to changes.
Inspect available receiver classification before proposing a live test. Do not
silently substitute a distance, normal-direction, or screen-position heuristic
for reliable character preservation.

## Verified distance behavior

The donor trace length is capped by the configured ray length and distance to
the light's exclusion region, then clipped to screen bounds. The current live
profile payload supplies ray length 100 in engine units (not verified feet).
Falloff is enabled. For a single hit, before screen-edge attenuation, visibility
is approximately `pow(sampleT * sampleT, 3)` = `sampleT^6`; larger visibility
means less blocked light. `sampleT` is progress along the projected trace, not
a verified linear physical-distance fraction under perspective. Multiple hits
reduce visibility by minimum. The user was told it scales, with strong shadowing
through much of the trace and more rapid fading near the end; no falloff change
has been applied.
