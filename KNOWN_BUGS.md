# Known Bugs

Last verified against code: 2026-10-27. Add new entries at the top. Note the evidence (`path:line`) and a status for each.

## Test: `test_detectionHaptic_coolsDownBetweenNearbyCars` fails

**Status:** Open (found 2026-10-28; fails every run, including in isolation; neither the test nor `PreMatchFeedbackController.swift` has uncommitted changes)

**Description:**
`thing-finderTests/Navigation/PreMatchFeedbackControllerTests.swift:175` expects 1 detection haptic after ticks at `now` and `now + 0.3` but gets 0; `:178` then expects 2 at `now + 0.8` but gets 1. Suspected cause: the test ticks exactly on the thresholds. `detectionHapticStabilityGate` is 0.3 s and `detectionHapticCooldown` is 0.5 s (`NavigationProtocol.swift:15,17`), and the `>=` checks (`PreMatchFeedbackController.swift:147,149`) compare `Date` differences. `Date` stores ~8×10⁸ s as a `Double`, so `(now + 0.3).timeIntervalSince(now)` can come out slightly under 0.3 and the gate doesn't open.

**Impact:** Likely test-only. On device, ticks don't land exactly on the threshold, so the haptic fires one frame later at most. Not confirmed on device.

**Potential fix:** Tick just past the thresholds in the test (e.g. `0.31` and `0.81`), and add a test that pins the intended behavior exactly at the boundary if that matters.

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

## Meta Glasses: Phone camera fallback after unpair/repair in same session

**Status:** Open, but dormant. All Meta glasses code has been commented out and the DAT SDK has been removed from the build since 2026-04-04 (`f60d50e`). The bug comes back if glasses are re-enabled, unless one of the fixes below is applied.

**Description:**
When unpairing and repairing Meta glasses within the same app session, the camera falls back to the phone camera instead of using the glasses stream.

**Root Cause:**
`DetectorContainer.captureSource` requires `streamSessionVM.isStreaming || streamSessionVM.hasActiveDevice` to be true before returning `.metaGlasses`. However, when registration completes, these values are not yet populated because:
1. `hasActiveDevice` depends on `AutoDeviceSelector.activeDeviceStream()`, an async stream that doesn't emit immediately
2. `isStreaming` is only true after the stream has started

By the time `captureSource` is evaluated, both values are still `false`, so it returns `.avFoundation` (phone camera).
Also note: the current `DetectorContainer` computes the capture source once in `.onAppear` (`thing-finder/Views/DetectorContainer.swift:56-70,110`). The `onChange` observers that would re-evaluate it are commented out.

**Workaround:**
Close and reopen the app after repairing glasses.

**Potential Fixes (not yet implemented):**
1. Proactively start streaming when registration completes (in `MetaGlassesEnvironment`)
2. Use `wearablesVM.devices.isEmpty` as the guard instead of `hasActiveDevice`
3. Add a delay/retry mechanism when registration completes to wait for device availability

## Python tooling

**Status:** Open (found in the 2026-10-27 doc audit). Details are in `scripts/README.md` and `evals/README.md`.

- `scripts/build_uber_allow.py` writes a flat list of makes, but `datasets/uber_eligible.json` must be a make → models dict for `evals/realworld/build_dataset.py`. Re-running the script would break the real-image eval.
- `scripts/gen_car_eval.py` is missing `import re` and `import glob`.
- `scripts/vehicle_csv_analyzer.py` expects an `expected` column that `results/*.csv` doesn't have, so its confusion matrix is meaningless.
- `evals/requirements.txt` is missing `pillow`, `scipy`, and `requests`.
- The legacy synthetic harness (`evals/run_eval.py` and `analyze_results.py`) is broken: `result_counts` is saved as strings, and the python grader failed all 140 cases in `eval_runs.json`. Unlike the realworld scripts, it has **no** request-count guard (one run is about 2,000+ requests).
- `data/test_cases_metadata.json` is stale until `add_reject_reasons.py` is re-run after regenerating.

## Minor inconsistencies

- `Settings.resetToDefaults()` writes `verification_cooldown = 2.0` and `distance_max = 3.0`, but the `@AppStorage` defaults are `10.0` and `20.0` (`thing-finder/Models/Settings.swift`, around line 327). A fresh install and a post-reset install therefore behave differently.
- `CandidateLifecycleService.swift:22` comment says "default: 5 consecutive misses", but `missThreshold` is 90.
- `DetectionManager.stableDetections()` (IoU 0.8, 4 frames) exists but the coordinator doesn't use it.
- `CameraDependencies` applies `ThresholdProvider(iou: 0.45, confidence: 0.25)`, but `AppContainer.makePipeline` loads `yolo11n` with the default model thresholds. Which thresholds production uses depends on the code path.
- `DistanceMilestoneController` can mix languages in non-English locales (see its comment around line 62).
