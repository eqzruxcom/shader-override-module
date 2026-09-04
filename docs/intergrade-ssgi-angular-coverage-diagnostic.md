# FF7 Remake SSGI angular-coverage diagnostic

Status: generated, strict-compiled, and independently verified offline; not installed.

## Question isolated

The static-surface c473 reprojection correction was necessary, but the live v2 result remained "mostly the same": a small visible light still appeared and disappeared with view angle. The current trace uses only four angular slices whose pixel-jittered phase changes with the camera.

This diagnostic changes only angular slice count:

| Page Up state | Angular slices | Radial steps | Maximum samples per pixel |
|---|---:|---:|---:|
| 0 | 4 | 16 | 64 |
| 1 | 8 | 16 | 128 |
| 2 | 16 | 16 | 256 |

Radiance source, world reconstruction, denoise passes, native c473 motion/static reprojection, private-history decay, composite strength, and hook ownership remain identical.

## Key contract

- F2: indirect-light candidate off/on master. OFF is native and clears private history.
- Page Up: cycles only 4/8/16 angular coverage while F2 is ON.
- F10: native shader reload; untouched.
- Page Down: graduated master; untouched.

## Interpretation

- If 8 or 16 slices materially stabilizes a visible emitter while 4 slices cuts out, sparse angular sampling is causal.
- If all three states cut out together, angular density is not the dominant cause; instrument temporal-history validity next.
- If a source fails only when it leaves the screen, no screen-space slice count can recover it. That requires a bounded GI-only cache or a native light/probe source.

## Offline evidence

Generate and verify:

```powershell
.\tools\New-IntergradeR3DSSGIAngularCoveragePack.ps1
.\tools\Test-IntergradeR3DSSGIAngularCoveragePack.ps1
```

The generated pack is `artifacts/agent2-r3d-ssgi-angular-coverage-pack-v1`. Ten SM5 shaders compile strictly. The 8- and 16-slice trace sources are proven byte-identical to the four-slice source except for the one slice-count constant. The verifier also proves the native OFF path, private-history routing, absence of finished-scene feedback, and reserved-key contract.

## Controlled live transition

`New-IntergradeR3DSSGIAngularCoverageLiveCandidate.ps1` packages the eleven verified Mods files with the same rebuilt x64 wrapper used by the temporal-v2 predecessor. It refuses a different wrapper or a drifted predecessor manifest.

`Stage-IntergradeR3DSSGIAngularCoverage.ps1` provides Stage, Status, and Restore operations. A stage requires the exact ten-file temporal-v2 predecessor, refuses either dense trace if it already exists, requires an explicit offline-candidate acknowledgement, and backs up every one of the twelve touched files. A real-game transition additionally requires the known executable fingerprint, accepted contact-shadow-family hash, a backup below `F:\Shader3Dmigoto\Backups`, and a closed game process.

`Test-IntergradeR3DSSGIAngularCoverageLiveStage.ps1` exercises the transition only in a disposable fake game tree. It proves early rejection, exact staging, installed-file drift detection, unsafe-restore rejection, removal of the two candidate-created traces, and byte-for-byte restoration of the temporal-v2 predecessor. Passing this test does not install the candidate or claim a live visual result.
