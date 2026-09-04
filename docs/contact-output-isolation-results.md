# Contact output isolation — 2026-08-31

One shader at a time. Suppress both scene-output u0 stores, restore that shader
before testing the next. This tests visible coverage, not only contact shadows.
Baseline and validated probes: `artifacts/contact-output-isolation-20260831-v1`.

| Test | Shader | User observation |
| --- | --- | --- |
| 1 | c30cdc8365df9840 | "seems like face"; screenshot shows bright green/white blocks over Cloud's face. Face involvement observed in this view; not proof of face-only or dynamic-only coverage. |
| 2 | 62b33a2d1e505241 | User: "seems like everything". Broad visible coverage in this scene; not a claim that every pixel or material uses this variant. Reload confirmed without detected errors. |
| 3 | 5a9fbefe0ab6f815 | User: "face and body". Character involvement observed; not proof of exclusive character coverage. Reload confirmed without detected errors. |
| 4 | 0e97888f9a8767da | User: "hair". Hair involvement observed in this view; not proof of exclusive coverage. Reload confirmed without detected errors. |
| 5 | 08bb8764f1840179 | User: "hair/face again". Hair/face involvement observed in this view; not proof of exclusive coverage. Reload confirmed without detected errors. |

Test 1 screenshot: `C:/Users/EQZITARA/AppData/Local/Temp/codex-clipboard-9fa23553-44f2-43c5-9664-ea7417ecf6f0.png`.
Preserved copy: `artifacts/contact-output-isolation-20260831-v1/test-1/user-face.png`.
Test 1 native shader reload and configuration reload were confirmed in the log,
with no detected reload errors. Output suppression can expose prior buffer
contents; the green is not an intentional marker injected by this probe.

All five observations recorded. User requested restoration after test 5.
Restore receipt: `artifacts/contact-output-isolation-20260831-v1/restore-receipt.json`.
Restoration returns to the pre-isolation working contact-shadow/left-edge profile,
not to unmodified game shaders. Native reload still requires F10.
