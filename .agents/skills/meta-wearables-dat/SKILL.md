---
name: meta-wearables-dat
description: Meta Wearables Device Access Toolkit (DAT) SDK for Ray-Ban Meta glasses — registration, permissions, Stream camera streaming, session lifecycle, MockDeviceKit testing, debugging. Use when touching MWDATCore/MWDATCamera code or the Meta glasses capture path.
---

# Meta Wearables DAT SDK

## Status
- **Branch `meta-s26`: enabled.** DAT SDK 1.0.0 (`Package.swift` `from: "1.0.0"`), gated by `FeatureFlags.metaGlassesEnabled`. The old "COMMENTED OUT FOR APP STORE SUBMISSION" comments were replaced (2026-10-28) because this build is headed to the App Store with glasses enabled.
- **`main`: disabled** since 2026-04-04 (`f60d50e`), SDK removed from `Package.swift`/`Info.plist`. Plan: ship glasses enabled in the App Store build. It was disabled in April because the Meta SDK requires Bluetooth permissions, so check the Bluetooth and local-network usage strings read well for App Review.

## Where it lives in this app
- `thing-finder/Services/MetaGlasses/MetaGlassesViewModel.swift` — consolidated SDK lifecycle (replaced MetaGlassesManager / WearablesViewModel / StreamSessionViewModel / MetaGlassesEnvironment). States: unconfigured → idle → registering → registered → requestingPermission → ready → streaming (paused / failed(reason)); drives `GlassesPhaseOverlay` via `displayPhase`.
- `thing-finder/FramePublishers/MetaGlassesFrameProvider.swift` — glasses frames → `FrameProvider`
- `thing-finder/Views/MetaGlassesSettingsSection.swift`, `MetaGlassesSetupView.swift`, `InputView.swift`, `App/App.swift` (SDK init, `onOpenURL`)
- Capture source selection: `DetectorContainer.computeCaptureSource()`; glasses selected ⇒ always `.metaGlasses`.
- Known bug history: phone-camera fallback / re-pair race — see `KNOWN_BUGS.md`.

## Required config (fails silently if missing)
- `Info.plist`: `MWDAT` dict (`AppLinkURLScheme` `thingfinder://`, `ClientToken` `$(META_CLIENT_TOKEN)`, `DAMEnabled` true, `MetaAppID` `$(META_APP_ID)`, `TeamID`), URL scheme `thingfinder`, `NSBonjourServices`, `UIBackgroundModes` `bluetooth-central`.
- Build settings (`INFOPLIST_KEY_*`): `NSBluetoothAlwaysUsageDescription`, `NSLocalNetworkUsageDescription`.
- `thing-finder.entitlements`: `com.apple.developer.networking.HotspotConfiguration` and `wifi-info`. Without these (plus Bonjour/local network) the SDK falls back to a degraded transport and streams stall with no error on any channel (`8beb068`).
- Stream: `.raw` codec, `.high` (720x1280), 30 fps, always. Tokens come from `Secrets.xcconfig` — never print them.
- Glasses: Developer Mode on in Meta AI app (resets after firmware updates).

## Rules that matter most
- The SDK is fully async: use `async/await`, observe via publisher `.listen {}` / `AsyncSequence`, update UI on `@MainActor`, never process frames on the main thread.
- Call `Wearables.configure()` once at launch, then use `Wearables.shared`.
- Do not restart a session while `paused`; wait for `streaming`/`running` or `stopped`. Release resources only after `stopped`.
- Opening hinges does not restart sessions; start a new one when the device is available again.
- `DeviceStateSession` was removed in 0.7; use `Wearables.deviceStateStream(for:)`. `StreamSession` types were renamed `Stream`/`StreamConfiguration`/`StreamState`/`StreamError` in 0.7.

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
