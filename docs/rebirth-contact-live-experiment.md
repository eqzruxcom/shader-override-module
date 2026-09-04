# Faithful donor experiment, not a quality-approved release

2026-08-31: after disclosure of the remaining offline false shadows, the user confirmed preparation of an experimental in-game comparison with `oka`. This authorizes the bounded test, not release approval, removal of failed results, or a donor algorithm rewrite.

The separate `Stage-IntergradeRebirthContactExperiment.ps1` uses the tested 16-sample SharedQuad candidate. It requires explicit acknowledgement, verifies donor/candidate/interface/capture source fingerprints, and assembles each of the five shipped ASM files back to its tested binary hash. The normal software/motion gates and normal stager remain unchanged. A fresh motion run is recorded because the older 16-sample receipt predates a runner-helper change; failures remain disclosed.

Only five native compute replacements and `Mods/ContactShadows.ini` are in scope. All six predecessor files are backed up before installation starts. The executable, DLL, main INI, image-adjustment INI/shader, and disabled capture INI are checked and preserved. A fresh non-persistent variable defaults the new experiment to OFF; it does not inherit the earlier experiment's toggle. No keys are sent automatically.

After manual F10 reload and log verification, Home switches this donor effect OFF/ON. OFF preserves native lighting math within these five replacements, not original execution cost or an entirely unmodified game. Other installed effects are unchanged. Do not use F3 as the primary comparison: it is the previous shader set, not the native reference. Page Down remains the existing image-adjustment control.

First observation: standing still, compare one Home toggle for new shadows, arm banding, or obvious darkening. Accept the user's definite report. Motion/flicker and performance require in-game assessment; the software tests are not FF7's complete renderer. Stop on shader errors, freezing or an obvious regression rather than advancing to another effect.

To undo the installed experiment, run `Restore-IntergradeRebirthContactExperiment.ps1 -GeneratedRuntimeDirectory <package>`. Its `-WhatIf` mode checks all backups and current hashes without restoring. It refuses to overwrite unrelated edits. Restoration copies the six predecessor files; the user must reload afterward. No files are deleted.

After the first successful in-game shader result, build the agreed [AHK/capture workflow](live-test-workflow-milestone.md) before moving on to more shaders. Until installation and reload receipts exist, this document describes the workflow, not proof that the game is using the donor.

## Installation and reload history

The approved package was installed at 2026-08-31 14:27 UTC: `artifacts/generated-runtime/FF7RemakeIntergradeRebirthContact-experiment-live-v1`. Six installed hashes match the separately inspected offline package (`...experiment-v1`). The installer backup is `backups/GeneratedRuntimeOverlay/20260831-142739-668`; an independently verified full predecessor snapshot is also inside the live package's `preinstall-backup`. Rollback `-WhatIf` passed without restoring anything. No DLL or other protected file changed.

Fresh matching-source motion receipt: `artifacts/rebirth-contact-experiment-motion16-20260831-v1`. Its readback is bit-identical to the earlier 16-sample quad receipt: 276 false-hit samples, 351 eligible misses and 745 large changes in the moving-box fixture. This remains failing quality evidence, not a successful live shader result.

At 14:28 UTC, `contact-live-status.json` reports `pending-F10`, zero new log bytes, and process 8168 responding. This is installation only: the game has not confirmed loading any donor replacements. Next user action is **F10 once**, then check the new parser/assembly logs before asking for Home ON/OFF comparison. Do not automatically install again on a goal continuation. Use this package explicitly with the status tool; its default still names the old package.

Update at 14:40 UTC: the user reported `done`; the log verifies the Home binding, all five override sections, all five replacement ASM loads and successful shader creations, without errors. Process 8168 responds and all installed/protected hashes match. **F10 is complete; do not ask for another reload.** This was the loading result; the later visual result below supersedes the earlier pending-report state.

## Code worked; retain the successful baseline

The user reported `its stable`, then qualified the result with sword/cone shadow
examples and `that said it looks working in most cases`. The soft shadow is
native; the user identifies the hard added edge as our contact shadow. Accept
that report without repeatedly requiring another Home comparison. Softening the
edge is requested; simply reducing darkness is not the same change.

The working version, receipts, original predecessor files, source, and six user
PNGs are preserved in `artifacts/checkpoints/rebirth-contact-first-working-20260831-v1`.
The checkpoint copied 44 files and verified the live six-file payload/protected
files unchanged. Unlabeled screenshots are not assigned ON/OFF states.

User-requested list and folder: **Contact shadows - Rebirth Mod - Code worked**.
See [known working code](known-working-code.md). Original donor, native Remake
bytecode, and working Remake adaptation are distinct references. Rebirth's native
shadowing may differ, so the harsh-edge observation is not a confirmed donor bug.
The failed synthetic motion gate remains failed; this is not release approval.

AHK/capture work is paused while addressing this current shader refinement, not
deferred until all shaders are finished. No softness variant has been installed.

## Current live package supersedes the donor-only experiment

2026-08-31 16:36 UTC: the user-requested viewport-only refinement is staged as
`artifacts/generated-runtime/FF7RemakeIntergradeContactViewport-live-v1`.
See [refinement evidence and pending reload](contact-shadow-refinement-issues.md).
It preserves the working donor as rollback, keeps Home OFF/ON, defaults OFF,
and includes neither softness nor edge fade. F10 is pending; no live success is
claimed. Use the viewport package explicitly with the status tool; do not
reinstall or mistakenly compare against this page's older donor reload receipt.

Update 2026-08-31 16:45 UTC: the viewport build DID reload successfully (16:40
status, all five shaders, no errors), but the user reported no visible improvement.
At their request, all six previous working donor files were restored and verified
on disk at 16:45:52 UTC. No reload was sent; running shader state is not confirmed
restored. The viewport package retains the rollback receipt and original test
evidence. The user subsequently offered another test conditional on understanding
what a shader-only viewport fix can do. Explain before another installation/test.

Next selected experiment: [LEFT-only fade with direct 0..9 keys](contact-left-edge-fade-experiment.md).
The user chose this after the shader/overscan explanation. Zero means no fade,
not no contact shadows; start at zero. Do not reinstall the viewport experiment.

2026-08-31 17:52:58 UTC: LEFT-only fade package installed and hash-verified,
`artifacts/generated-runtime/FF7RemakeIntergradeContactLeftEdgeFade-live-v1`.
Starts contact ON, fade 0%. Top-row 0..9 selects 0%..9% and enables contact;
Home toggles added contact. All offline gates selected for this experiment pass,
but no new motion-quality/performance pass. Paused **pending-F10**, no keys sent.
See the linked experiment page for receipts and explicit status/rollback paths.
