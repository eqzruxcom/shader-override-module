# Contact-shadow refinements, 2026-08-31

Keep the verified code-worked checkpoint unchanged. The new work is a separate
refinement candidate, not a replacement of the historical donor or success record.

## User observations

- Added contact-shadow edges are too hard/sharp on the sword and a nearby cone.
  Native shadows are softer. Requested improvement is edge softness, not merely
  lower opacity. Native shadows should remain present.
- Camera movement causes an artifact at the very screen edge, reminiscent of
  the user's earlier 3D Vision frustum issues. Apparently left-sided in the
  current view; neither exclusivity nor exact width is confirmed. "1/80" was
  explicitly a guess, not a measurement.
- New screenshot pair, preserved under
  `artifacts/contact-refinement-observations-20260831/`: filenames retain the
  user attachment IDs. Both are unedited; no ON/OFF order is asserted.

## Inspection scope

Check biased ray origins crossing the clip boundary; clip-plane logic; viewport
versus buffer bounds; point-depth clamping; camera/receiver mapping rejection;
and checkerboard reconstruction before choosing an edge treatment. An edge fade
cannot recover offscreen occluders and must not be called a geometry fix.

For softness, the donor's falloff contrast changes visibility along the ray,
not a physical penumbra. Its 2x2 averaging reconstructs checkerboard lanes; it
is not a general edge-aware spatial filter. Preserve the original and label
any additional sampling/filtering as a project refinement.

### Screen-edge fade fallback (user raised during validation)

Test-control preference: when testing multiple variants or percentages, use the
top-row number keys 1–9 as direct preset selectors, without modifiers. Publish
the exact key-to-preset mapping for each test; do not require cycling repeatedly.
Home remains the existing effect OFF/ON control unless explicitly changed.
This is a preference for future multi-preset tests, not authorization to silently
rebind the current viewport-only test or overwrite unrelated key assignments.

The user supplied Google's suggestion to fade screen-space shadows near the
screen boundary and recalled a 3D Vision hotkey that hid frustum artifacts with
an actual edge bar. Retain this as relevant precedent, not proof of the current
engine cause. User chose to continue the tests first.

If valid offscreen information is missing, clipping cannot reconstruct it.
A candidate fallback should fade ONLY added contact occlusion toward neutral
visibility (1), preserving native lighting/shadows and the HUD; no opaque bar.
For strength `f`, `visibility = lerp(1, contactVisibility, f)`. This is not an
ambient-light boost. Fade width remains tunable; the earlier 1/80 estimate must
not be treated as a measured boundary.

Evaluate hit/ray-boundary confidence as well as receiver position: a blocker
can leave the viewport while its shadow receiver remains inside. A receiver-only
border fade may not remove that pop. No fade has been added to the viewport-only
candidate. It is a fallback to test, not a promise to eliminate every artifact.

Work order: fix and validate the present area, reconfirm in a second area,
then build the universal script. No new-area test requested from the user yet.

## Video and baseline

The user's 5.63-second, 1280x720/30fps clip is preserved unmodified in the same
observation folder: `FINAL FANTASY VII REMAKE 2026.08.31 - 11.38.58.01.mp4`.
SHA256: `C067F1107FC4C67DB23070FFFB7B3A327FD2910785DA05465D0CB708F6E38B96`.
Inspection focused on the yellow/black pole beside the fallen cone at the left
edge, using extracted sequential crops. It does not establish the exact cause.

The six installed payload hashes were rechecked against the preserved working
checkpoint during this refinement. See `docs/backup-latest.md` for the separate
verified F-drive snapshot. Historical donor and successful port stay unchanged.

## Viewport-only experiment (not live-confirmed)

Isolated source root: `artifacts/contact-viewport-development-20260831-v1`.
The original donor clips the ray's exit, but not an outside biased origin's
entry. The derivative clips both ends and constrains UV checks to the viewport,
with boundary-roundoff clamping. No hardcoded edge width/fade, changed light
settings, softness filter, or recovered offscreen geometry is involved.

- `artifacts/contact-viewport-clip-20260831-v3`: 64 analytic interval checks pass.
- `artifacts/contact-viewport-ray-20260831-v2`: identical full-ray fixture in
  baseline/refinement, 128 rays and 256 checks per build at 8/16/32 samples.
  Reproduces baseline misses on all four full-screen edges and out-of-viewport
  sample coordinates for subviews. Refinement corrects those cases; clear,
  interior, outside-receiver and exiting-ray controls pass. The baseline's
  expected-failure reproduction is not a correctness pass.
- Fork `artifacts/viewport-tests-v2`: six compiles; ray 34/34, resources 56/56,
  donor inputs 34/34, reconstruction 34/34, adapter reconstruction 448/448.
- Fork `artifacts/viewport-interface-single` and `viewport-interface-repeat`:
  all five assembled variants pass; 307,200 and 2,457,600 lane results. These
  validate the inserted instructions/shared storage, not the whole renderer.
- Fork `artifacts/viewport-capture-shared`: all 20 captured visibility/validity
  output files match the older shared replay byte-for-byte. The saved frame
  therefore does NOT reproduce the newly targeted entry case.
- Fork `artifacts/viewport-motion16-v2`: visibility readback identical to the
  previous failing motion audit. 276 false hits, 351 misses and 745 large changes
  remain in the moving-box fixture. No motion-quality pass is claimed.

Early test attempts remain preserved: missing WinRT include, fixture warning,
and missing provenance helper were harness problems, not live-game errors.

### Live viewport comparison staged, awaiting the user

Installed at 2026-08-31 16:36:44 UTC:
`artifacts/generated-runtime/FF7RemakeIntergradeContactViewport-live-v1`.
Only the five contact compute shaders and `Mods/ContactShadows.ini` changed.
The DLL, main INI, other effect INIs and image-adjustment shader match their
protected hashes. Game process 8168 responds. Status is **pending-F10**, zero
new log bytes; this is NOT a confirmed shader load or visual fix.

Home remains contact OFF/ON; the fresh viewport-test variable defaults OFF.
No softness or screen-edge fade is included. No keypress was sent. Next user
action: F10 once, report done/errors, then inspect fresh reload logs before
asking for the Home-enabled edge test. Pause here for user participation.
Do not reinstall automatically on continuation or treat the old donor package
as the current live one.

Rollback to the preserved working donor uses
`tools/Restore-IntergradeContactViewportExperiment.ps1` with this package path.
Its `-WhatIf` checks passed without restoring anything. All six predecessor
files are independently backed up in the package's `preinstall-backup` and in
`backups/GeneratedRuntimeOverlay/20260831-163644-809`. No files were deleted.

### Viewport result and requested rollback (supersedes pending reload above)

At 16:40:47 UTC the viewport package status confirmed parser and all five native
ASM reloads, with no errors or changed protected files. The user reported no
visible change, then requested the previous version. Accept this negative result;
the synthetic entry-clipping reproduction did not establish the live cause.

At 16:45:52 UTC the restore script restored and hash-verified all six predecessor
files. Protected files remained unchanged. The viewport source/package remain
preserved. No reload key was sent; restored disk files are NOT proof that the
running game has switched back. See the viewport package's restore receipt.

The user then offered another viewport test but first requested an explanation
of how shader-only changes could help without engine changes. Do not reinstall
or request another comparison before addressing that distinction. The patch
clips the shader's depth-tracing ray; it cannot change engine frustum culling or
recover missing offscreen geometry. New screenshots identify the red-lit post
at the far left; the user reports its contact shadow disappears near the edge.
The precise cause remains unproven, with screen-space loss a plausible hypothesis.

For a later fade experiment, top-row keys 1 through 9 must directly select fade
widths 1% through 9%, respectively, without modifiers or cycling. Not installed.

## Separate softness prototype (not integrated or installed)

`src/Effects/Lighting/RebirthContactSoftness.hlsl` reuses the donor tracer for
eight deterministic disk-emitter samples. Zero radius returns the hard path.
Emitter radius is an explicit experimental input, NOT attenuation range and
NOT a verified Remake light-source size. No screen blur or opacity reduction.

`artifacts/contact-softness-profile-20260831-v2` passes 2,048 checks. Two analytic
depth-edge profiles gain monotonic intermediate transitions (22 and 51 sampled
positions at blocker separations 1 and 3); solid interiors retain the baseline
values. This establishes an edge-softening mechanism, not game visual quality.
The first attempt had a reserved-keyword typo in the fixture, now corrected.

Remaining: eight-ray GPU cost, finite-sample banding, basis-orientation changes,
camera/object motion, native-shadow blending and a practical user control.
Do not put this into the viewport-only comparison or mark softness finished.

## Current selected direction: left-only edge fade

The user chose edge fading after discussion of the limits of shader-only
overscan. They explicitly requested LEFT only, default 0%, and key **0 = 0%**.
Keys 1..9 directly select 1%..9%; Home remains the contact toggle. This is not
the rejected viewport experiment and does not yet address hard shadow softness.
See [left-edge implementation, evidence and current staging state](contact-left-edge-fade-experiment.md).

The user later requested a custom profile on key 1: no added contact darkness
within 0.5% of the left edge, smoothly reaching full strength at 4%. This replaces
the old 1% meaning for that key only; key 0 remains no fade, and 2..9 keep their
old width-only meaning. Full-strength confidence also depends on where a ray
hits a blocker, so a near-edge blocker can affect a more interior receiver.
They also suggested slowing re-entry over time. That would need history/motion
handling and is not part of the selected spatial-only test. Native shadows stay.
