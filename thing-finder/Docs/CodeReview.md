# Thing Finder Code Review – 2025-02-15

## Project Snapshot
- **Stack**: SwiftUI iOS client with YOLO11 CoreML detector, Vision trackers, Combine-driven pipeline, TrafficEye + OpenAI verification, ARKit/AVFoundation capture.
- **Composition root**: `AppContainer.makePipeline` builds detector → tracker → drift repair → lifecycle → verifier → navigation → `FramePipelineCoordinator`.
- **Threading model**: Capture queue drives `FramePipelineCoordinator.process`; `CandidateStore` relies on hopping to the main queue for mutations. Any background reads must go through the synchronised helpers.

## Testing & Tooling Notes
- `thing-finderTests` exercise lifecycle, drift repair, verifier policy, and tracker behaviour, but there is no coverage for the lost-candidate branch or Info.plist configuration guards.
- Pipelines are heavily asynchronous; new tests should stress capture-queue access patterns to ensure `CandidateStore` stays thread-safe.

## Findings
| # | Severity | Location | Issue | Recommendation |
|---|----------|----------|-------|----------------|
| 1 | High | `thing-finder/Core/CandidateStore.swift:95`, `:106`, `:130`, `:143` | Several read helpers (`pruneToSingleMatched`, `containsDuplicateOf`, subscript getter, `hasActiveMatch`) touch `candidates` directly. Because `FramePipelineCoordinator` invokes them on the capture queue, this bypasses the `syncOnMain` guard and will surface as “Publishing changes from background threads” crashes once multiple frames race. | Wrap every read in `syncOnMain` (e.g. reuse `snapshot()` or add dedicated boolean/lookup accessors) and update callers (`CandidateLifecycleService`, `FramePipelineCoordinator`) to consume the synchronised results instead of the raw dictionary. |
| 2 | High | `thing-finder/Services/Pipeline/CandidateLifecycleService.swift:124-132` | When a fully matched car drops out of frame, `tick` flips it to `.lost` but never removes it because the subsequent branch skips `.lost` candidates. The store keeps a dead candidate forever, so `DetectionStateMachine` is stuck in `.verifying` and navigation speech never returns to “searching”. | After marking a full match as lost, either remove it once `missCount` exceeds the threshold or keep a timestamp and purge after a short timeout. Add a unit test that asserts `phase` goes back to `.searching` after the cooldown. |
| 3 | High | `thing-finder/Services/Pipeline/DriftRepairService.swift:97-103` | Drift repair restores `.lost` candidates straight to `.full` when a detection overlaps, bypassing the verifier. A stale track can therefore oscillate between lost/full without any new LLM/OCR check. | Rehydrate lost candidates to `.unknown` (or queue a re-verification) and let `VerifierService` confirm the match before returning to `.full`. |
| 4 | Medium | `thing-finder/Services/Pipeline/DriftRepairService.swift:86` | If no detection passes similarity, the service zeros the bounding box. Downstream area checks (`VerifierService`, overlays) treat it as too small and skip verification/UI even though the candidate is still “active”. | Leave the last known bounding box untouched (or flag separately) so navigation/verifier logic can make an informed decision until the lifecycle drops the candidate. |
| 5 | Medium | `thing-finder/Services/Pipeline/Verification/TrafficEyeVerifier.swift:63-64` | API secrets are force-unwrapped from `Bundle.main`. Preview builds, unit tests, or misconfigured Info.plist entries crash before the UI appears. | Replace with guarded lookups that publish an `.apiError` outcome (and add a configuration test) so missing keys surface as actionable errors instead of crashes. |
| 6 | Low | `thing-finder/Services/Pipeline/CandidateLifecycleService.swift:94` | `tick` falls back to the global `ImageUtilities.shared` instead of the injected instance, breaking dependency injection in tests/mocks. | Use the `imgUtils` instance that is already stored on the service so tests can supply lightweight stubs. |
| 7 | Low | `thing-finder/Services/Pipeline/Verification/TrafficEyeVerifier.swift:86-88` | The blur gate recomputes `blurScore` and force unwraps the second call, logging two Core Image passes. | Cache the optional (`guard let blur = blurScore, blur < 0.1 else`) to avoid duplicate work and nil crashes if CI fails. |

## Suggested Next Steps
- Harden `CandidateStore` read APIs and adapt callers; add a regression test that drives `process` from a background queue to guard against future threading slips.
- Fix lifecycle handling for lost matches and ensure the state machine returns to `.searching`; include a UI regression test that asserts overlays clear once the car is gone.
- Adjust drift-repair recovery to require re-verification before announcing a found car again.
- Add configuration validation for the TrafficEye/OpenAI secrets so CI/previews fail fast with context.

---

# Thing Finder Code Review – 2025-08-06

## Project Snapshot
- **Platform & stack**: SwiftUI iOS app with a CoreML (YOLO11) detector, Vision trackers, Combine pipelines, and LLM-based verifiers (TrafficEye + OpenAI).
- **Composition root**: `AppContainer.makePipeline` wires detector, tracker, drift repair, lifecycle, verifier, and navigation feedback into `FramePipelineCoordinator`.
- **Frame flow recap**: Camera providers push frames on a background capture queue → coordinator runs detection/tracking/drift repair/lifecycle → verifier schedules async work → navigation + SwiftUI consume published `FramePresentation`.
- **Shared state**: `CandidateStore` is the authoritative candidate map; services mutate it through helper APIs that hop to the main thread.
- **Docs updated**: `Docs/PipelineOverview.md` now has a "Threading Model Cheatsheet" summarizing the observed scheduling rules.

## Testing Landscape
- `thing-finderTests` contains unit-style coverage for lifecycle, drift repair, tracker, and verifier services.
- Tests currently focus on logic correctness; they do not exercise cross-thread access patterns or Info.plist configuration.

## Review Findings

| # | Severity | Location | Issue |
|---|----------|----------|-------|
| 1 | High | `Core/CandidateStore.swift:105`, `:130`, `:143` | Several read paths (`containsDuplicateOf`, subscript getter, `hasActiveMatch`) touch `candidates` directly without going through `syncOnMain`. Because `FramePipelineCoordinator` and `CandidateLifecycleService` call these from the camera queue, this will trigger SwiftUI/Combine "Publishing changes from background threads" crashes under load. Wrap every read in `syncOnMain` (e.g. reuse `snapshot()` or add a helper for booleans/lookups). |
| 2 | High | `Services/Pipeline/CandidateLifecycleService.swift:90-133` | `tick` reads `store.hasActiveMatch` and later `store[id]` on the capture queue. Both rely on the unsafe getters above, so lifecycle logic races with UI observers. Once `CandidateStore` exposes thread-safe reads, ensure lifecycle code uses them exclusively (cached snapshot + dictionary lookups) instead of the direct helpers. |
| 3 | High | `Services/Pipeline/DriftRepairService.swift:97-103` | When drift repair finds a detection for a candidate already marked `.lost`, it unconditionally restores `matchStatus` to `.full`. That bypasses verification, so a stale track that briefly regains overlap will be announced as a confirmed match without rerunning the LLM/OCR checks. Only rehydrate to `.unknown` (or enqueue re-verification) and let `VerifierService` confirm the object again. |
| 4 | Medium | `Services/Pipeline/Verification/TrafficEyeVerifier.swift:63-64` | API keys are force-unwrapped from `Bundle.main.infoDictionary`. Any missing/renamed key (unit tests, previews, enterprise builds) will crash at startup. Replace with guarded lookups that emit a descriptive error publisher so the app can fail gracefully and surface configuration problems. |
| 5 | Medium | `Services/Pipeline/CandidateLifecycleService.swift:93-101` | `ImageUtilities.shared` is used instead of the injected `imgUtils` instance when creating the initial `CGImage`. This breaks dependency injection in tests/mocks and makes the service harder to reason about on macOS. Use the injected helper consistently. |
| 6 | Low | `Services/Pipeline/Verification/TrafficEyeVerifier.swift:86-88` | The blur gate recomputes `blurScore` twice and fails closed if the helper returns `nil`. Cache the optional and log/skip when Core Image cannot score rather than force-unwrapping a recomputed value. |

## Suggested Next Steps
1. Harden `CandidateStore` read APIs and adjust callers to use the synchronized versions; add a regression unit test that exercises concurrent access on a background queue.
2. Clarify the drift repair ↔︎ verification contract so that recovering tracks cannot promote themselves to `.full` without the verifier signing off.
3. Introduce configuration validation (unit test + runtime guard) for required Info.plist secrets to avoid shipping builds that crash on launch.
4. Consider extending the test suite with a capture-queue simulation that hits lifecycle + drift repair simultaneously to cover the threading expectations documented in the new cheatsheet.
