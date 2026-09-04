# Left-edge contact-shadow fade experiment

## Requested behavior

FF7 Remake Intergrade, not Rebirth. User reports a contact shadow disappearing at
the extreme left edge as the red-lit post or striped pole leaves the screen.
The viewport experiment loaded but showed no visible improvement; it was rolled
back. Screen-space missing data is plausible, not a proven engine diagnosis.

User selected a subtle LEFT-only fade, not overscan, FOV changes, cropping, a
black border, or another viewport test. The number row directly selects widths:

- **0 = 0%**, working donor contact shadows with no edge fade.
- **1 through 9 = 1% through 9%** of viewport width, respectively.
- Digits enable contact shadows as well as selecting the width.
- **Home** toggles the added contact shadows OFF/ON.
- Initial state: contact ON, edge fade 0%. No modifiers or repeated cycling.

Widths describe the transition band, NOT overall shadow strength. Both receiver
and blocker positions are checked against the left edge. A blocker inside that
band may cast a shadow farther inside the screen, so affected receiver pixels
need not be restricted to the same band. No top/right/bottom fade is applied.

## Source separation

Original donor and the first working Remake adaptation remain unchanged.
The derivative lives in `artifacts/contact-edge-fade-development-20260831-v1`.
`src/Effects/Lighting/ContactEdgeFade.hlsl` is a project-authored reusable helper;
the fork adds `RebirthContactRayEdgeFade.hlsl` separately from the imported donor.
Controls use t120 row29.x; existing contact row31 and image-effect row30 remain.

Each hit is faded before the minimum visibility reduction. This avoids fading
away an unrelated interior blocker when another blocker approaches the edge.
At zero width the old visibility calculation is retained. Original ray clipping,
sample count, thickness and native shadowing remain. Softness is separate work.

## Offline evidence

- `artifacts/contact-edge-fade-tests-20260831-v3`: 576 helper checks,
  5,120 full-ray results per branch; all 512 zero-width rays exactly unchanged.
  Interior top/bottom/right test profiles are unchanged. Positive widths produce
  intermediate visibility and monotonically reduce the added edge shadow.
- Fork `artifacts/fade-candidate-v2`: all five native assembly candidates pass
  compile/assembly and round-trip preservation checks.
- Fork `artifacts/fade-tests-v5`: strict smoke compiles and existing donor,
  resource and reconstruction suites pass. Earlier runner/reporting failures
  are retained as evidence, not presented as shader or live-game failures.
- `artifacts/contact-edge-fade-capture-comparison-20260831-v2`: 20 zero-width
  visibility/validity output files are bit-identical to the saved-frame working
  baseline. 1% and 9% produce nontrivial fades, with validity unchanged.
- Final all-five assembled interface runs (`fade-interface-0-v3`,
  `fade-interface-1-v3`, `fade-interface-9-v3`) passed: 1,200 groups and 15
  shader-creation checks each; 307,200 lane results each at 0% and 1%, and
  2,457,600 at 9% with eight alternating light iterations. Every positive-width
  profile has nonzero intermediate fade samples.

The earlier interface runner reported zero intermediate samples because its
synthetic receiver remained at x=64 while the group moved to x=0. The fixture
now moves both together, without modifying production shader code. The coverage
report also now executes before the shared-test return. All profiles passed.
Saved-capture replays were rebuilt as `fade-capture-0-v2`, `fade-capture-1-v2`,
and `fade-capture-9-v2` because their runners also include the corrected test
header; final comparison v2 records current source hashes. Shader results match
the first replay. Earlier outputs are preserved, not rewritten.

These are analytic/saved-depth and shader-interface tests, NOT a complete engine
renderer. Existing synthetic motion failures remain; no live motion-quality or
hardware-performance pass is claimed. The fade cannot recover offscreen geometry.

## Staging and rollback

`tools/Stage-IntergradeContactEdgeFadeExperiment.ps1` requires all evidence before
staging five contact CS replacements plus `Mods/ContactShadows.ini`. It checks
numeric bindings/row29 conflicts and preserves DLL, main INI and other effects.
All six predecessor files receive hash-verified backups before installation.

`tools/Restore-IntergradeContactEdgeFadeExperiment.ps1` restores only that exact
six-file payload and refuses unrelated live edits. No gameplay key is sent.
The user must press F10 before live reload can be verified.

The existing F-drive snapshot predates this experiment; do not claim it includes
the new fade work. The original working checkpoint remains separately preserved.

## Installed, paused for F10 (2026-08-31 17:52:58 UTC)

Current package:
`artifacts/generated-runtime/FF7RemakeIntergradeContactLeftEdgeFade-live-v1`.
Exactly five contact CS files and their INI installed and hash-verified. All
protected files unchanged, game process 8168 responding. Status **pending-F10**,
zero new log bytes. No keys sent, no live load or visual success claimed.

Preflight package `FF7RemakeIntergradeContactLeftEdgeFade-preflight-v1` passed
reassembly, direct-key/default validation and a restore dry run before live
installation. Live restore dry run also passed. Six predecessor files are in
the live package's `preinstall-backup` and the install backup
`backups/GeneratedRuntimeOverlay/20260831-175257-667`. Nothing deleted.

Next: user presses F10 once, reports done/error. Run the status tool with the
EXPLICIT live package above; it now checks all ten numeric key sections as well
as Home and all five shaders. Do not infer enabled state or percentage from INI
defaults after user interaction. Do not reinstall on continuation. Pause here.

## Reload confirmed (2026-08-31 18:00:32 UTC)

User reported "done" after F10. Status for the explicit left-edge live package
is `passed-parser-and-five-native-asm-reloads`: all five assembly replacements
loaded and were created successfully; Home and all ten 0..9 key sections parsed.
No logged reload errors, changed payload files or changed protected files.
Process 8168 remains responding. This confirms load, not visual effectiveness.

Next visual comparison: 0 for the unchanged contact baseline, then 1 for the
1% left-edge fade while moving the previously identified post/pole across the
left edge. Ask whether disappearance becomes gradual. Higher widths are direct
choices if needed, not a requirement to repeat every setting. Await user result;
do not edit or reinstall shaders while they compare.

## Follow-up: strength fade with a zero-strength edge zone

User confirmed the first fade works but reported that shadows still snap back;
1% was the closest old preset. This is NOT a final motion-quality pass.
They clarified that the goal is fading the added blackness at the left edge,
not a black masking bar and not changing the game's original shadows.

Final requested/preferred test supersedes the earlier 2.5% boundary:

- 0 through 0.5% from left: no added contact shadow.
- 0.5% through 4%: smoothstep strength ramp; halfway at 2.25%.
- Beyond 4%: full confidence, unless a shadow-casting ray hit is nearer the edge.
- Key 0: unchanged contact baseline, no fade.
- Key 1: this custom profile (NOT the old 1% preset).
- Keys 2..9: retained old width-only presets; Home: contact toggle.
- Start with contact ON, fade OFF. No automatic reload or gameplay keys.

Implementation is isolated in `artifacts/contact-edge-profile-development-20260831-v1`.
The old live fade fork and original working Rebirth donor remain separate.
Per-hit visibility is blended toward 1 using the smaller of receiver and hit
confidence, before combining hits. Therefore a left-edge blocker can affect a
receiver farther than 4% inside. This avoids treating a cropped blocker as fully
reliable; it does not recover any offscreen depth.

The user also suggested limiting how quickly darkness returns over time. That
would require frame history and motion handling; this test is spatial only.
A faster camera can still cross the fade quickly, and discontinuous hit validity
can still produce a pop. Do not promise a temporal fix from the smooth curve.

Offline evidence so far (not installed at this entry):
`artifacts/contact-edge-profile-tests-20260831-v2` passes 1,056 curve checks and
1,536 analytic ray checks, including reversal. Saved-capture comparison v2 passes:
20 no-fade output files match the original donor replay bit-for-bit; the new
profile never adds darkness, preserves validity, and leaves contact-OFF outputs
unchanged. Five-variant integration testing is separately required before staging.
These are shader tests, not a full engine renderer or a live motion result.

## Custom profile installed; paused for user (2026-08-31 18:46 UTC)

Current package: `artifacts/generated-runtime/FF7RemakeIntergradeContactLeftEdgeProfile-live-v2`.
Exactly five contact CS replacements and `Mods/ContactShadows.ini` installed.
DLL, main INI, image-adjustment shader, other-effect INI and capture INI unchanged.
Status at 18:46:36 UTC: **pending-F10**, zero new log bytes, process 8168 responding,
no changed payload/protected files or new errors. No keys sent; not live-validated.

Final integration evidence, in the isolated profile fork:
`artifacts/profile-interface-0-v2` passes all five variants, 1,200 group cases,
307,200 lane results and 15 shader-creation checks. `profile-interface-1-v2`
passes the same variants/groups/creation checks with eight light iterations,
2,457,600 lane results, nontrivial intermediate fade values, alternating lights
and zero-contribution preservation. Both use `profile-candidate-v1` (width/cutoff
are runtime inputs) and the rebuilt `profile-tests-v2` runner. No live-quality
or hardware-performance pass is claimed.

Preflight package and live package both passed a restore dry run. Six predecessor
files are hash-preserved in the live package's `preinstall-backup` and
`backups/GeneratedRuntimeOverlay/20260831-184602-307`. Rollback restores the earlier
left-edge fade, not the rejected viewport experiment. Original working donor
remains separately preserved. Existing F-drive snapshot predates this new test.

Next participation: when the user is ready, one F10 reload; then verify status
using the EXPLICIT current package above. Key 0 = contact shadows with no edge
fade; key 1 = new 0.5%-zero / 4%-full profile. Home toggles added contact shadows.
Wait for user observation of the same left-edge pop in motion. Do not reinstall,
automatically reload, or claim the clipping is fixed based on offline results.
