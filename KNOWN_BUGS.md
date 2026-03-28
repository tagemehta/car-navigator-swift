# Known Bugs

## Meta Glasses: Phone camera fallback after unpair/repair in same session

**Status:** Open

**Description:**
When unpairing and repairing Meta glasses within the same app session, the camera falls back to the phone camera instead of using the glasses stream.

**Root Cause:**
`DetectorContainer.captureSource` requires `streamSessionVM.isStreaming || streamSessionVM.hasActiveDevice` to be true before returning `.metaGlasses`. However, when registration completes, these values are not yet populated because:
1. `hasActiveDevice` depends on `AutoDeviceSelector.activeDeviceStream()`, an async stream that doesn't emit immediately
2. `isStreaming` is only true after the stream has started

By the time `captureSource` is evaluated, both values are still `false`, so it returns `.avFoundation` (phone camera).

**Workaround:**
Close and reopen the app after repairing glasses.

**Potential Fixes (not yet implemented):**
1. Proactively start streaming when registration completes (in `MetaGlassesEnvironment`)
2. Use `wearablesVM.devices.isEmpty` as the guard instead of `hasActiveDevice`
3. Add a delay/retry mechanism when registration completes to wait for device availability
