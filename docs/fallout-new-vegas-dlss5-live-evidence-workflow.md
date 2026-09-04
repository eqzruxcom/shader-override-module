# Fallout: New Vegas DLSS5 live-evidence workflow

State: tooling verified offline; a real Fallout: New Vegas run and an
authentic NVIDIA-signed `nvngx_dlssnr.dll` 310.8.0.0 remain required.

This workflow deliberately distinguishes three claims:

1. **Transport passed**: the x86 DX9/DXVK/Vulkan process exchanged frames with
   the x64 helper and received its output.
2. **Neural execution passed**: the helper created a native-resolution 1:1
   DLAA carrier, RenoDX created Feature 18, and its evaluation counter reached
   at least 60.
3. **Full DLSS5 passed**: neural execution passed *and* live motion-vector and
   depth probes contained usable data.

Super Resolution is not part of any of these gates. The validator rejects an
`input -> larger output` DLSS carrier and requires the shared-set and DLAA
dimensions to be identical.

## Import the neural inputs

Only use runtime files obtained legitimately. The default profile pins the
currently researched hashes and will reject the known modified community
`nvngx_dlssnr.dll` whose Authenticode signature reports `HashMismatch`.

```powershell
.\tools\Import-FalloutNewVegasDlss5NeuralInputSet.ps1 `
  -RenoDxAddonPath C:\authorized-source\renodx-dlss5-v2.5.addon64 `
  -NvngxDlssPath C:\authorized-source\nvngx_dlss.dll `
  -NvngxDlssNrPath C:\authorized-source\nvngx_dlssnr.dll `
  -InputSetId fnv-renodx-nr-310.8-signed
```

The importer validates exact hashes, x64 PE architecture, file versions, and
valid NVIDIA signatures on both NVIDIA DLLs before and after copying. Its
ignored `neural-input-set.json` receipt contains no source paths and grants no
redistribution rights.

Promote only from that validated set:

```powershell
.\tools\New-FalloutNewVegasDlss5FullBundleFromInputSet.ps1 `
  -TransportBundleDirectory .\artifacts\fallout-new-vegas-dlss5-bundles\fnv-dlss5-transport-20260904-v5-repro `
  -NeuralInputSetDirectory .\artifacts\fallout-new-vegas-dlss5-neural-inputs\fnv-renodx-nr-310.8-signed `
  -PackageId fnv-dlss5-neural-candidate
```

The generated full bundle remains non-installing and non-runtime-eligible. Use
the existing acknowledgement-gated installer and retain its receipt.

## Capture one run without accepting stale logs

Start the capture while `FalloutNV.exe` is closed. This verifies every installed
payload hash and records the current length/hash of every relevant log without
deleting or modifying game files.

```powershell
$capture = .\tools\Start-FalloutNewVegasDlss5LiveCapture.ps1 `
  -InstallReceiptPath .\artifacts\fallout-new-vegas-dlss5-installs\<install>\install-receipt.json `
  -SessionId fnv-transport-run-01
```

Launch the returned `LaunchCommand`, exercise gameplay, take the requested
screenshot(s), and exit cleanly. For neural validation, move the camera for at
least 600 rendered frames so the guide probes have a meaningful opportunity to
sample motion.

Complete a transport capture:

```powershell
.\tools\Complete-FalloutNewVegasDlss5LiveCapture.ps1 `
  -CaptureSessionDirectory $capture.SessionRoot `
  -EvidenceId fnv-transport-run-01 `
  -TransportSplitScreenshotPath C:\captures\fnv-mode1-split.png
```

Complete a neural A/B capture:

```powershell
.\tools\Complete-FalloutNewVegasDlss5LiveCapture.ps1 `
  -CaptureSessionDirectory $capture.SessionRoot `
  -EvidenceId fnv-neural-run-01 `
  -NeuralOffScreenshotPath C:\captures\fnv-neural-off.png `
  -NeuralOnScreenshotPath C:\captures\fnv-neural-on.png
```

Completion copies only log bytes written after capture start when the runtime
appended to an existing log; if a runtime replaced its log, the new file is
retained whole. Evidence is hash-closed and bound to the package manifest,
install receipt, and `FalloutNV.exe` hash without retaining the game directory.

The required runtime evidence is:

- DXVK identifies `FalloutNV.exe` and its runtime version.
- Game-side ReShade identifies Vulkan and `dlss5-feed.addon32`.
- `VK_LAYER_feed_vk` negotiates and returns `vkCreateDevice -> 0`.
- Client and host report the same IPC version and Vulkan client kind.
- At least three frames are delivered on both sides.
- Mode 1 reports the transport-only copy and includes its split screenshot, or
  mode 2 reports a same-size DLAA carrier plus signed DLSSNR initialization,
  Feature 18 creation, at least 60 successful evaluations, and distinct off/on
  screenshots.
- Fatal transport, NGX, shader-compiler, device-removal, and `0xBAD00002`
  markers are absent.
- Full success additionally requires a motion-vector probe with at least 2%
  non-zero samples during motion and a depth probe with non-zero variance and
  at least 95% finite samples.

`Assert-FalloutNewVegasDlss5LiveEvidence.ps1` reports all three verdicts. It
does not turn missing guide probes into a false full-success claim.

## Offline tests

```powershell
.\tools\Test-FalloutNewVegasDlss5NeuralInputSet.ps1
.\tools\Test-FalloutNewVegasDlss5LiveEvidence.ps1
.\tools\Test-FalloutNewVegasDlss5LiveCapture.ps1
```

The tests use disposable artifacts. Synthetic log fixtures test the parser but
are never shipped as live evidence; real capture manifests require
`policy.synthetic=false` and are created only by the two-phase capture path.
