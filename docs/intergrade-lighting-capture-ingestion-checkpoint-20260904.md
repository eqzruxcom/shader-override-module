# Intergrade lighting capture-ingestion checkpoint — 2026-09-04

## Result

The remaining live ownership work now has an automatic ingestion path. `Invoke-IntergradeLightingOwnershipCaptureAnalysis.ps1` scans selected `FrameAnalysis-*` directories, runs exact resource-flow analysis for each requested shader, and aggregates executions, output resources, first consumers, overwrites, and missing-target status into one JSON report.

The default targets are:

- `aadc1c2374853914-ps`
- `adb544f9a11d6c7e-cs`

Missing targets are classified as **not observed in the selected captures**, never as unused shaders. `-RequireObserved` writes an `incomplete` report and then fails closed.

## Verification

The test fixture proves:

- multiple target results aggregate from one capture;
- `c473ab75b7519f7e-ps:o0` first reaches `af6cd28a0108a18a-ps:t0`;
- `a26b3473289dba2d-cs:u1` first reaches `58101bdcc044cd88-cs:t0`;
- duplicate target specifications are rejected;
- a required but absent target produces a retained incomplete report;
- no live game file is changed.

The focused nine-test end-to-end suite passes after this addition.

## Retained-capture ledger

All seven retained live `FrameAnalysis-*` captures were ingested. Neither `aadc1c2374853914-ps` nor `adb544f9a11d6c7e-cs` executed in those captures. New scene-specific captures are therefore required; there is no unprocessed existing hit to recover.

Persistent report:

`artifacts\analysis\intergrade-lighting-ownership-retained-captures-20260904.json`

## Live-control status

The supported Windows-control helper failed to initialize after its complete retry/reset sequence because its sandbox process could not apply deny-read ACLs. No fallback window automation was used, and no game input or live staging occurred.

