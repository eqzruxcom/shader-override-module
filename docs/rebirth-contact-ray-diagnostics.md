# Donor-ray observation and sample-count tradeoff

2026-08-31. **Offline diagnosis, not an installed fix or a reproduction of Cloud's arm banding.** The pinned donor algorithm, native candidate, live shaders and deployment gates remain unchanged.

## Observer verification

`tools/Trace-RebirthContactMotion.cpp` reuses the existing analytic scene functions and renders the same moving-box inputs as the saved RawPixel motion test. It compiles both the original wrapper and an instrumented wrapper. The custom include loader inserts exactly one observer call into the donor text in memory, verifies that removing that insertion restores the original text, and removes only the entry-point `numthreads` attribute from the renamed motion helper. The observer stores values but does not alter the donor's calculations, branches, hit predicate or return value. Generated instrumented sources are saved for inspection.

Completed receipt: `artifacts/rebirth-contact-trace-20260831-v3/manifest.json`.

- 96 frames / 49,152 receiver results, each **bit-identical** between logged and unlogged execution.
- Every unlogged result also matches the earlier saved moving-box readback bit-for-bit.
- 695,050 tested depth intervals recorded; 14,246 accepted intersections.
- Independent analysis reproduces every recorded intersection predicate and final visibility from those accepted samples. Maximum final-visibility error: 3.1087032e-9.
- Logged depth samples match the analytic surface at the selected texel center, maximum depth error 2.8987262e-5.

Analysis receipt: `artifacts/rebirth-contact-trace-analysis-20260831-v2/analysis.json`. Four regression checks in `tools/test_rebirth_ray_trace.py` pass. Source import verification still reports unchanged pinned donor ray/noise/reconstruction statements.

Earlier trace-v1 stopped on the renamed helper's entry-point attribute. Trace-v2's visibility equivalence passed, but unwritten log slots were ambiguous; **it is not the attribution evidence**. Trace-v3 explicitly initializes every record before tracing. The analyzer also must multiply UV by buffer size in float32 **before** flooring, as the shader does: recorded UV bits `0x3f466666` select x=992, whereas promoting before multiplication incorrectly selects x=991. The depth tolerance was not relaxed to hide that discrepancy.

## What causes the synthetic false hits

Among the original 207 RawPixel false-hit samples, the first accepted sample always reads the **box**, never the receiving plane. Of those rays, 202 still miss the analytic scene even after using the logged normal/depth-biased origin; five intersect after bias/pixel reconstruction. This is not proof that all live character artifacts have the same cause.

At that first accepted sample:

| Position of the actual ray sample relative to the sampled depth volume | Cases |
|---|---:|
| In front of the biased front depth | 123 |
| Behind the back of the thickness volume | 46 |
| Inside that approximate depth volume | 38 |

The donor tests a finite interval of ray depths against one sampled surface's thickness interval. Consequently, the interval may overlap even when the ray point at the sampled UV does not. Screen-depth thickness also approximates a surface volume rather than the true box boundary. Only six first-hit samples change surface classification between the continuous UV and its texel center; nearest-texel boundary selection alone does not explain the majority.

Example, frame 1 / receiver 36 / step 5: sampled box depth 130.0331, bias 0.1389, ray-point depth 129.0117. The point is in front, but the interval spans 126.7408 to 131.3654 and therefore passes the donor's test. Another case, frame 0 / receiver 419, puts the point within the approximate depth thickness despite the biased 3D ray missing the actual box. These are separate limitations, not one wrong normal or wrong light index.

Limitations: the geometric ray comparison includes bias but not viewport clipping; the first accepted interval is attributed, not every later accepted interval. The point-depth classification uses CPU double geometry around recorded float32 inputs. No engine history, TAA, full lighting composition or hardware performance is modeled.

## Existing donor sample-count settings

The next test varied only the existing compile-time sample count, retaining the donor math and the same 96-frame scenes. Comparison receipt: `artifacts/rebirth-contact-motion-sample-comparison-20260831-v1/comparison.json`. The script checks matched active/truth masks, recomputes moving-box counts from readbacks, verifies frame summaries, and checks exact repeated endpoints.

All rows have 43,855 active moving-box samples and 2,787 eligible visible blockers. The plane and both sphere scenes retain zero false hits, misses and large changes.

| Mode | Samples | False hits | Missed eligible blockers | Large changes with unchanged tracked truth |
|---|---:|---:|---:|---:|
| RawPixel | 16 | 207 | 282 | 1,159 |
| RecomputeQuad | 16 | 276 | 351 | 745 |
| RawPixel | 32 | 169 | 163 | 814 |
| RecomputeQuad | 32 | 204 | 189 | 561 |
| RawPixel | 64 | 173 | 121 | 680 |
| RecomputeQuad | 64 | 222 | 135 | 536 |

The 32-sample setting improves all three measures over 16 in this fixture. Increasing to 64 reduces misses/variation further but increases false hits relative to 32. It is **not** a complete fix, and nominal sample counts are not measured GPU cost. All six receipts still report `regressionDetected=true`. Native shared integration has only been executed at its original 16-sample setting; the 32/64 results do not certify a different native candidate.

Artifacts: existing `rebirth-contact-{pixel,quad}-motion-20260831-v2` for 16; `rebirth-contact-{pixel,quad}-motion32-20260831-v1` and `...motion64-20260831-v1` for the added settings.

## Next decision

The port's offline wiring now matches the donor, but the donor's synthetic quality limitations remain. Do not call this a validated improvement, silently rewrite the donor algorithm, or bypass the normal deployment gate. The next user-facing decision is whether to evaluate a clearly marked experimental faithful port in-game with these limitations disclosed, or continue algorithm/quality investigation first. No live build was staged by this work.

After the **first successful in-game shader**, follow the user's [AHK/capture workflow milestone](live-test-workflow-milestone.md) before proceeding to more shaders.

## Reproduce

Use fresh absolute directories below workspace artifacts:

```powershell
.\tools\Trace-RebirthContactMotion.ps1 -OutputDirectory '<trace>'
python tools/analyze_rebirth_ray_trace.py '<trace>' '<raw-pixel-motion>' '<trace-analysis>'
python tools/test_rebirth_ray_trace.py
.\tools\Audit-ContactShadowMotion.ps1 -Implementation Rebirth -Samples 32 -Reconstruction RawPixel -OutputDirectory '<pixel-32>'
.\tools\Audit-ContactShadowMotion.ps1 -Implementation Rebirth -Samples 32 -Reconstruction RecomputeQuad -OutputDirectory '<quad-32>'
.\tools\Audit-ContactShadowMotion.ps1 -Implementation Rebirth -Samples 64 -Reconstruction RawPixel -OutputDirectory '<pixel-64>'
.\tools\Audit-ContactShadowMotion.ps1 -Implementation Rebirth -Samples 64 -Reconstruction RecomputeQuad -OutputDirectory '<quad-64>'
python tools/compare_rebirth_motion_samples.py '<sample-comparison>'
```

The comparison currently names the recorded six artifact directories explicitly; it refuses changed scene/shader inputs or overwritten output directories.
