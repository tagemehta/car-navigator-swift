# Known Bugs

## Meta Glasses: Phone camera fallback during cold-start / repair race

**Status:** Resolved

**Description:**
On a second cold launch (and after unpair/repair within a session), the camera
fell back to the phone's back camera even when glasses were selected and
permission was requested.

**Root Cause:**
The capture source in `DetectorContainer` was *derived* from several
asynchronously-populated, volatile flags (`isRegistered`, `isStreaming`,
`isReady`, `hasActiveDevice`) and recomputed via scattered `.onChange`
observers. On cold start these flags populate in a non-deterministic order, so
the detector picked `.avFoundation` first and could flip back to it mid-handshake
(e.g. while in `.requestingPermission` before `hasActiveDevice` latched true).
Each flip rebuilt the `FrameProvider`, tearing down the in-flight glasses
session, so the view settled on the phone camera.

**Fix:**
The capture source is now a pure function of durable user settings
(`settings.useMetaGlasses` / `useARMode`) — see `DetectorContainer.computeCaptureSource()`.
When glasses are selected the source is always `.metaGlasses`; connection
progress and terminal errors are surfaced via `GlassesPhaseOverlay` (driven by
`MetaGlassesViewModel.displayPhase`) instead of silently falling back to the
phone camera. `startStreaming` also has a 15s timeout so "connecting" can no
longer hang forever when no glasses are reachable.

Cross-tab navigation from the error overlay to the Meta Glasses settings section
is still a placeholder (`GlassesPhaseOverlay.onOpenSettings`) — to be wired up in
a follow-up.
