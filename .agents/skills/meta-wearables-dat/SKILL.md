---
name: meta-wearables-dat
description: Meta Wearables Device Access Toolkit (DAT) SDK for Ray-Ban Meta glasses — registration, permissions, StreamSession camera streaming, session lifecycle, MockDeviceKit testing, debugging. Use when touching MWDATCore/MWDATCamera code or the Meta glasses capture path.
---

# Meta Wearables DAT SDK

## Status: disabled (since 2026-04-04, `f60d50e`)
All glasses code below is commented out ("COMMENTED OUT FOR APP STORE SUBMISSION"), and the SDK has been removed from `Package.swift` and `Info.plist`. Before working on glasses, follow the re-enable checklist in `ONBOARDING.md` ("Meta glasses (disabled)") and fix the re-pair bug in `KNOWN_BUGS.md`.

## Where it lives in this app
- `thing-finder/Services/MetaGlasses/` — `MetaGlassesManager`, `MetaGlassesEnvironment`, `WearablesViewModel`, `StreamSessionViewModel`
- `thing-finder/FramePublishers/MetaGlassesFrameProvider.swift` — glasses frames → `FrameProvider`
- `thing-finder/Views/MetaGlassesSettingsSection.swift`, `thing-finder/App/App.swift` (SDK init)
- Open bug: phone-camera fallback after unpair/re-pair — see `KNOWN_BUGS.md`.

## Rules that matter most
- The SDK is fully async: use `async/await`, observe via publisher `.listen {}` / `AsyncSequence`, update UI on `@MainActor`, never process frames on the main thread.
- Call `Wearables.configure()` once at launch, then use `Wearables.shared`.
- Do not restart a session while `paused`; wait for `streaming`/`running` or `stopped`. Release resources only after `stopped`.
- Opening hinges does not restart sessions; start a new one when the device is available again.
- Avoid `DeviceStateSession` alongside a camera stream (unreliable).

## Reference (load only the section you need)
`reference.md` in this directory holds the full SDK guide. Grep it for the section heading instead of reading it all:

| Topic | Heading in `reference.md` |
|---|---|
| Info.plist, SPM, init, URL callback | `## Dev environment tips` … `## Step 6` |
| MockDeviceKit / tests without hardware | `## Testing instructions` |
| StreamSession, resolution/FPS, photo capture | `## Building and streaming` |
| Pause/resume/stop semantics | `## Session management` |
| Registration + camera permission | `## Permissions` |
| Diagnosis tree, version matrix, known issues | `## Debugging` |
| End-to-end sample ViewModels | `## Sample app` |

The API changes between SDK releases. When you need exact signatures, prefer the live docs over this file:
the `wearables` MCP server (`search_dat_docs`) if your tool has it, otherwise
https://wearables.developer.meta.com/llms.txt?full=true.
