# Shared Rebirth contact rays in Remake's native lighting loop

2026-08-31. **Offline implementation, not an installed fix.** Uses the same pinned donor ray, IGN, checkerboard parity and AVG reconstruction. It changes SM5 inter-thread plumbing, not the shadow algorithm. Earlier motion-quality failures remain unresolved.

## Native boundary established

`tools/audit_rebirth_shared_boundary.py` checks the five pinned original binaries and normalized instruction streams. Receipt: `artifacts/rebirth-contact-shared-boundary-20260831-v2/boundary.json`.

Each variant maps a 16x16 thread group to one tile via its specialization's tile-list segment. Its outer lighting loop has a common read-only light list, count clamped to 64, counter initialized to zero and incremented once per iteration. The contribution-accumulation anchor is directly in that loop, outside the material/attenuation/shadow branches. The earlier shadow-packing loop can diverge but finishes before this boundary; the only early debug return is group-uniform. Native shaders declare no shared memory.

Thus the earlier blanket description of a "divergent light loop" was too broad: its **inner branches vary, but its outer light iteration and selected insertion boundary are group-uniform**. A barrier inside the old per-pixel zero-contribution gate would still be unsafe. Microsoft documents group synchronization as undefined in divergent branches. [GroupMemoryBarrierWithGroupSync](https://learn.microsoft.com/en-us/windows/win32/direct3dhlsl/groupmemorybarrierwithgroupsync)

This audit is deliberately specific to the pinned shaders, not a general proof for another executable, shader permutation or UE4 game. The generator verifies both binary and normalized-instruction hashes against the audit. Timestamp comments are not compared as instructions.

## Implementation

- `RebirthContactShared.hlsl`: 256 floats / 1,024 bytes of group-shared storage. Selected pixels evaluate the donor ray; unselected valid pixels read their actual 2x2 quad and apply the unchanged donor average. Every lane writes neutral or ray visibility before the first barrier. Invalid receivers do not skip synchronization.
- `RebirthContactSharedKernel_cs.hlsl`: strict SM5 compilation wrapper. The generator replaces its temporary b13 input with an isolated native register containing group origin and captured light index, and replaces its u7 output with a register move. Neither extra resource binding is introduced into the game shader.
- `New-IntergradeContactShadowCandidate.ps1 -Reconstruction SharedQuad`: inserts the shared block at the audited common boundary **before** the per-pixel contribution gate. All native instructions are retained except the expanded temporary declaration; physical diffuse/specular masks and untouched lanes are verified by token checks and byte-identical assembly round trips.

The donor helper contains a terminal group barrier, but FXC eliminates it in the single-call compilation wrapper. The generator requires that observed one-barrier shape and restores a second `sync_g_t` after the translated block, before any subsequent native light can overwrite shared data. An unexpected compiler barrier/return shape is rejected. Consecutive-light WARP execution now passes as described below; this is not proof against every hardware scheduling race.

Zero native contributions remain unchanged, including negative zero, but their threads still participate in shared work: a selected neighbor can be needed by an unselected pixel. This differs from the raw/recompute gate that skipped all ray evaluation for zero-contribution pixels. The explicit terminal barrier also executes for unselected lights when the outer enabled control is on. Do not assume the reduced ray count automatically means lower total GPU cost.

The fully eligible shared path evaluates approximately **0.5 rays per pixel**, versus 1.5 for neighbor recomputation. Odd viewport origins intentionally return neutral because absolute-screen quads could cross group boundaries. Native even-origin mapping is audited; arbitrary group origins are not supported. Provisional native phase, raster/helper coverage, engine TAA, and hardware cost remain unverified.

## Verified results

Candidate: `artifacts/rebirth-contact-shared-candidate-20260831-v2`.

| Native variant | Native temps | Shared candidate temps | Candidate bytes |
|---|---:|---:|---:|
| c30cdc8365df9840 | 39 | 54 | 67,724 |
| 62b33a2d1e505241 | 24 | 39 | 52,352 |
| 5a9fbefe0ab6f815 | 29 | 44 | 56,856 |
| 0e97888f9a8767da | 30 | 45 | 57,204 |
| 08bb8764f1840179 | 31 | 46 | 57,632 |

The general variant was 214,008 bytes in the earlier recomputation prototype. This is compiled size, not a timing/FPS measurement.

`artifacts/rebirth-contact-shared-runner-20260831-v1` passes the existing 606 donor HLSL/resource checks. `artifacts/rebirth-contact-shared-interface-20260831-v1/manifest.json` records **15 shader-creation checks and 1,200 passing full-group cases / 307,200 lane results**. Each case executes the actual assembled injection block with all 256 threads and compares every lane to barrier-free donor recomputation plus independent CPU parity/averaging of raw ray outputs.

Coverage: five native variants, three noise indices (0, 61, 12345), both checkerboard phases, mixed ID-1/ID-7 packed materials, strength/selection, poisoned alternate depth slot, translated/rotated cameras, native diffuse/specular physical masks, zero/negative-zero/negative contributions, empty/outside/partial viewports, odd-origin neutrality, and mixed invalid receivers. The material-profile argument is superseded by the mixed-material fixture texture in reconstruction tests; it is not three independently uniform material profiles.

Limitations of that first receipt: one light evaluation per fixture dispatch; native contribution sentinels are uniform within the group. This is not complete native tiled shading, scene animation, engine TAA, quality approval, or a GPU-cost test. The single-thread interface script explicitly rejects SharedQuad instead of misusing its old fixture contract.

### Consecutive-light / mixed-contribution verification

Current fixture generator output: `artifacts/rebirth-contact-shared-repeat-candidate-20260831-v1`. All five **production candidate hashes are unchanged** from shared-candidate v2 above. Only offline validation fixtures were added. The runner `artifacts/rebirth-contact-shared-repeat-runner-20260831-v3` passes the existing 606 HLSL/resource checks.

- `artifacts/rebirth-contact-shared-repeat-interface-20260831-v2/manifest.json`: 15 shader-creation checks, **1,200 passing group cases / 2,457,600 light-lane results**. Every fixture dispatch loops through eight alternating light evaluations in the same 16x16 group and reuses the same shared storage. The exact production injection block is retained inside that fixture-only loop.
- `artifacts/rebirth-contact-shared-single-interface-20260831-v3/manifest.json`: the single-light regression rerun passes 15 creation checks and **1,200 group cases / 307,200 lanes** with the same current sources.

Neighboring pixels deliberately alternate zero diffuse, zero specular, both negative-zero, or original contributions; the pattern moves each iteration. Both lights have valid radii and opposite directions. The independent reference uses separate dispatch-Z groups per light, with recomputation plus CPU averaging of four raw ray results; it does not reuse shared storage. Every output is compared, including repeat-to-repeat identity, untouched physical lanes and signed zero. Each profile must exhibit both differing light results and shadowed zero-contribution lanes, preventing a vacuous all-neutral pass. For example, the general variant/frame-0 profile records 630 adjacent-iteration visibility differences and 208 shadowed zero-contribution lanes.

Earlier repeated-reference attempts are preserved, not passing evidence: an outer HLSL reference loop caused excessively slow software execution and was stopped; the subsequent reference compiled its masked float-bit light index to constant light 0. Disassembly established that reference defect. Host-decoded integer light indices in a separate reference-only b8 buffer corrected it. No production shader change was made to hide those mismatches. Aborted interface-v1/single-v2 directories lack passing manifests.

### Matched captured resources

Fresh receipts: `artifacts/rebirth-contact-capture-shared-20260831-v2`, `artifacts/rebirth-contact-capture-raw-20260831-v3`, `artifacts/rebirth-contact-capture-quad-20260831-v3`, and `artifacts/rebirth-contact-capture-shared-comparison-20260831-v2/comparison.json`.

The shared result is **bit-identical to barrier-free recomputation for all five saved lights**, covering 518,400 samples per light / 2,592,000 enabled comparisons. Maximum difference from independent CPU reconstruction of raw rays is 2.3841858e-7. All three paths also produce finite in-range outputs and exact neutral visibility when disabled. Each shared light includes 11,520 valid sample positions in a partial final group; out-of-grid lanes still reach synchronization before returning.

This replay uses the actual saved normal, depth, material and cb0/cb1/cb4 resources. Complete 2x2 quads are sparsely sampled; they are not complete contiguous native tiles or a final-frame render. Native tile membership, complete lighting composition, animation, TAA, temporal phase progression, hardware cost and live visual quality remain unverified. Captured phase 5 and noise index 61 represent only one frame.

The legacy Raw generator also still assembles all five variants (`artifacts/rebirth-contact-raw-generator-compat-20260831-v1`). The source importer confirms the pinned donor statements remain unchanged. No runtime stager, quality gate, live shader, INI, DLL or key binding was changed.

## Next

1. Investigate the remaining donor-ray false hits using individual sampled-depth/hit diagnostics. The new pixel-truth analysis in [reconstruction notes](rebirth-contact-reconstruction.md#pixel-center-truth-diagnostic) shows receiver sampling does not explain most failures.
2. Verify native temporal phase progression and hardware cost when a focused live test is warranted.
3. Resolve quality questions before deployment. Equivalence to the current donor prototype does not fix its known quality tradeoffs.

Update: step 1 now has [bit-identical donor trace evidence and a bounded sample-count comparison](rebirth-contact-ray-diagnostics.md). Synthetic failures originate in accepted box-depth intervals; increasing samples is not a complete cure. Before changing donor behavior further, obtain direction on a clearly disclosed experimental live evaluation. After the first successful in-game shader, build the [agreed capture/control workflow](live-test-workflow-milestone.md).

Reproduction (fresh absolute artifact directories):

```powershell
python tools/audit_rebirth_shared_boundary.py '<prior-native-candidate>' '<boundary>'
.\tools\New-IntergradeContactShadowCandidate.ps1 -Implementation Rebirth -Reconstruction SharedQuad -SharedBoundaryDirectory '<boundary>' -OutputDirectory '<candidate>'
.\tools\Test-ContactShadows.ps1 -Implementation Rebirth -OutputDirectory '<runner>'
.\tools\Test-RebirthSharedContactInterface.ps1 -CandidateDirectory '<candidate>' -TestBuildDirectory '<runner>' -OutputDirectory '<interface>'
.\tools\Test-RebirthSharedContactInterface.ps1 -Repeated -CandidateDirectory '<candidate>' -TestBuildDirectory '<runner>' -OutputDirectory '<repeated-interface>'
.\tools\Replay-IntergradeContactCapture.ps1 -Implementation Rebirth -Reconstruction SharedQuad -OutputDirectory '<shared-capture>'
python tools/compare_rebirth_contact_capture.py '<raw-capture>' '<quad-capture>' '<comparison>' --shared '<shared-capture>'
```
