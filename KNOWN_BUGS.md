# Known Bugs

Last verified against code: 2026-10-27. Add new entries at the top. Note the evidence (`path:line`) and a status for each.

## Per-frame Vision tracking is a no-op (suspected)

**Status:** Open (suspected, found during a doc audit on 2026-10-27; not yet confirmed on device)

**Description:**
`TrackingManager.tick` only runs requests in `requestMapping`, and nothing populates that map. `addTracking(_:)` (`thing-finder/Services/Pipeline/TrackingManager.swift:63`) has no callers in app code. `CandidateLifecycleService` (`:133`) and `DriftRepairService` (`:127`) create `VNTrackObjectRequest`s and store them on the candidate without registering them. As a result `performTracking` returns early (`TrackingManager.swift:38`), and a candidate's `lastBoundingBox` moves only when `DriftRepairService` re-associates it, once every 15 frames.

**Impact:** Boxes, and the direction, beep, and depth cues derived from them, lag up to 15 frames behind the car. `CandidateLifecycleService` only resets `missCount` on overlap (`:173-180`) and does not move the box.

**Potential fix:** Call `tracker.addTracking(_:)` wherever a candidate's `trackingRequest` is created or replaced. Remove stale requests when candidates are removed. Add a `FramePipelineCoordinatorTests` case that asserts boxes move between drift-repair frames.

## Verification: OCR can leave a candidate `.partial` forever

**Status:** Open (found in the 2026-10-27 doc audit)

A candidate whose OCR reads never pass the confidence or regex check stays `.partial` even after `maxOCRRetries` (30) is reached (`thing-finder/Services/Pipeline/Verification/VerifierService+OCR.swift:62-68`). It should end in a definite state, for example a retryable reject.

## Verification: escalation thresholds are ineffective

**Status:** Open (found in the 2026-10-27 doc audit)

- **Hybrid:** choosing one engine zeroes the other's counter (`VerifierSelector.swift:151,154`), so a failing candidate simply alternates TrafficEye → TwoStep → TrafficEye. `llmAttempts` never exceeds 1, so `maxLLMRetries = 3` never applies.
- **Paratransit:** the comments (`VerifierSelector.swift:12-19`, `VerificationConfig.swift:27-30`) describe TrafficEye → AdvancedLLM escalation, but the selector always picks `AdvancedLLMVerifier` (`:241-244`). The TrafficEye instance (`:122`) and the paratransit retry constants (`:78,80`) are dead code.
- `VerifierService.swift:177-199`: this failure branch is unreachable, because the selector's `.catch` turns every error into an outcome.

## Verification: minor

- `TwoStepVerifier.swift:133` sends JPEG bytes labelled `data:image/png`.
- `VerifierService.swift:125` comment says 15%, but the minimum box-area check at `:129` is 1%.
- `TwoStepVerifier` uses `URLSession.shared` directly, so it can't be network-mocked in tests.

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
