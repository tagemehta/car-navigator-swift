# Thing Finder Testing Plan

What test coverage exists in `thing-finderTests/`, how to run it, and what is still planned. Priorities: testability, isolation, determinism.
Last verified against code: 2026-10-27

---

## 1. How to Run

Follow `.agents/skills/ios-build-test/SKILL.md`. Summary:

| Item | Value |
| ---- | ----- |
| Project | `thing-finder.xcodeproj` (run from repo root) |
| Schemes | `thing-finder` (dev, use for tests), `thing-finder-prod` |
| Test target | `thing-finderTests` (unit tests only; no UI test target) |
| Test plan | `thing-finderTests/thing-finder.xctestplan`: random execution order, target parallelizable, code coverage on the `thing-finder` target |

```bash
SIM="iPhone 16 Pro"   # first from: xcrun simctl list devices available | rg iPhone
# Whole suite
xcodebuild test -project thing-finder.xcodeproj -scheme thing-finder \
  -destination "platform=iOS Simulator,name=$SIM" -quiet 2>&1 | tail -60
# One class (preferred while iterating)
xcodebuild test -project thing-finder.xcodeproj -scheme thing-finder \
  -destination "platform=iOS Simulator,name=$SIM" \
  -only-testing:thing-finderTests/NavAnnouncerTests -quiet 2>&1 | tail -60
```

Notes:
- `thing-finder/Secrets.xcconfig` and `CVModels/` (YOLO model) are gitignored. A build failing on a missing model or keys is an environment problem; don't create or commit secrets.
- "No such module" errors in VS Code are an indexing artifact; trust `xcodebuild`.
- Tests use `@testable import thing_finder`.

---

## 2. Current Test Inventory

28 `XCTestCase` classes, 358 test methods (`grep -c "func test"`, 2026-10-27). One class per file, named after the file.

| Folder | Class | Tests | Covers |
| ------ | ----- | ----- | ------ |
| `Core/` | `CandidateTests` | 11 | Defaults, `isMatched`, verification tracker |
| | `CandidateStoreTests` | 19 | Upsert/update/remove, duplicates, `pruneToSingleMatched`, snapshot, concurrent updates |
| | `DetectionStateMachineTests` | 12 | `.searching` / `.verifying` / `.found` reduction |
| `Models/` | `SearchHistoryItemTests` | 7 | Search history model |
| `Services/` | `CandidateLifecycleServiceTests` | 16 | Ingest, miss count, lost, reject cooldown, candidate cap |
| | `DetectionManagerTests` | 8 | `Detection` value type and `MockObjectDetector` (no real CoreML) |
| | `DriftRepairServiceTests` | 17 | Stride, similarity re-association |
| | `TrackingManagerTests` | 9 | Vision tracker updates via mock requests |
| | `FramePipelineCoordinatorTests` | 4 | Depth sample coordinate conversion (ARKit view points vs AVFoundation normalized) |
| `Verification/` | `VerifierSelectorTests` | 21 | Strategy selection, escalation, counter reset, error mapping |
| | `VerifierServiceTests` | 12 | Gating, rate limits, status updates |
| | `TrafficEyeVerifierTests` | 13 | Response parsing via `MockURLSession` + `TestAPIResponses` |
| | `TwoStepVerifierTests` | 7 | Init and error enum only (no LLM response parsing yet) |
| | `OCREngineTests` | 16 | Plate OCR and Levenshtein matching |
| | `NetworkErrorClassifierTests` | 9 | Connectivity vs API error classification |
| `Navigation/` | `NavAnnouncerTests` | 28 | Transition phrases, repeat suppression, lost compass, view announcements, haptics |
| | `PreMatchFeedbackControllerTests` | 25 | Session start, detection haptics, heartbeat, rejections, grouping |
| | `DistanceMilestoneControllerTests` | 17 | Thresholds, skip-to-closest, hysteresis, cooldown |
| | `NetworkFeedbackControllerTests` | 16 | Offline / restored / weak signal, deferral |
| | `HapticBeepControllerTests` | 15 | Beep start/stop/interval, haptic distance pulses, toggles |
| | `MatchStatusSpeechTests` | 13 | Phrase table, transition phrases |
| | `DirectionSpeechControllerTests` | 11 | Change gating, debounce, reset |
| | `FrameNavigationManagerTests` | 2 | Cold-start ordering (connectivity warning vs session start) |
| `Utilities/` | `DescriptionParserTests` | 17 | Plate extraction |
| | `ImageUtilitiesTests` | 15 | Orientation, rect conversion |
| | `CGRectIoUTests` | 10 | IoU math |
| | `APIHealthMonitorTests` | 6 | Degradation tracking |
| | `NetworkMonitorTests` | 2 | Async connectivity resolution (uses the real `NetworkMonitor.shared`) |

### Mocks (`thing-finderTests/Mocks/`)

| File | Type(s) | Replaces |
| ---- | ------- | -------- |
| `MockObjectDetector.swift` | `MockObjectDetector` | `ObjectDetector` |
| `MockVisionTracker.swift` | `MockVisionTracker` | `VisionTracker` |
| `MockTrackingRequest.swift` | `TestTrackingRequest` (factory) | `TrackingRequest` |
| `MockDriftRepairService.swift` | `MockDriftRepairService` | `DriftRepairServiceProtocol` |
| `MockCandidateLifecycleService.swift` | `MockCandidateLifecycleService` | `CandidateLifecycleServiceProtocol` |
| `MockVerifierService.swift` | `MockVerifierService` | `VerifierServiceProtocol` |
| `MockNavigationSpeaker.swift` | `MockNavigationSpeaker` | `NavigationSpeaker` |
| `MockSpeechOutput.swift` | `MockSpeechOutput` | `SpeechOutput` |
| `MockBeeper.swift` | `MockBeeper`, `MockSmoothBeeper` | `Beeper`, `SmoothBeeperProtocol` |
| `MockHapticManager.swift` | `MockHapticManager` | `HapticManagerProtocol` |
| `MockCompassProvider.swift` | `MockCompassProvider` | `CompassProvider` |
| `MockNetworkMonitor.swift` | `MockNetworkMonitor` | `NetworkMonitorProtocol` |
| `MockAPIHealthMonitor.swift` | `MockAPIHealthMonitor` | `APIHealthMonitorProtocol` |
| `MockURLSession.swift` | `MockURLSession` | `URLSessionProtocol` |
| `MockEmbedding.swift`, `MockEmbeddingProvider.swift` | `MockEmbedding`, `MockEmbeddingProvider` | `EmbeddingProtocol`, `EmbeddingProvider` |
| `MockImageUtilities.swift` | `MockImageUtilities` (subclass) | `ImageUtilities` |
| `MockSettings.swift` | `TestSettings` (factory) | Configured `Settings` instances |

### Fixtures and assets

| Path | Contents | Used by |
| ---- | -------- | ------- |
| `Fixtures/TestCandidates.swift` | `TestCandidates` factory for `Candidate`s in each status | Core, Services, Navigation, Verification tests |
| `Fixtures/TestAPIResponses.swift` | `TestAPIResponses` canned TrafficEye/OpenAI JSON | `TrafficEyeVerifierTests` |
| `Assets/Car1_Base.JPG`, `Car1_Base_shift.JPG`, `Car1_Back.JPG`, `Car2_side.jpg` | Real car photos for embedding/integration tests | Not referenced by any test yet |

---

## 3. Conventions

- Put new tests in the folder for their layer; reuse `Mocks/` and `Fixtures/`.
- Name tests `test_<subject>_<scenario>_<expectedResult>`, e.g. `test_tick_missCountExceedsThreshold_removesCandidate`.
- Inject time: navigation controllers take a `timestamp`, so cooldown tests pass explicit `Date`s instead of sleeping.
- Inject everything through constructors (see `AppContainer` / `DesignDecisions.md`). Avoid `.shared` singletons in tests (`NetworkMonitor.shared`, `APIHealthMonitor.shared`, `CompassHeading.shared`); pass mocks. `FrameNavigationManager` and `NavAnnouncer` fall back to those singletons when a dependency is omitted. `NetworkMonitorTests` is the deliberate exception.
- The test plan randomizes order, so tests must not depend on each other or on `UserDefaults` left behind by `@AppStorage` settings.

---

## 4. Gaps and Planned Work

### Missing unit coverage

| Area | Gap | Suggested approach |
| ---- | --- | ------------------ |
| `TwoStepVerifier` / `AdvancedLLMVerifier` | No response parsing or match logic tests; `AdvancedLLMVerifier` (paratransit) has none | `MockURLSession` + recorded OpenAI tool-call JSON in `TestAPIResponses` |
| `DetectionManager` | Real filtering/stability not exercised (CoreML not loaded) | Inject a stub `VNCoreMLModel` or test the filter/stability logic separately |
| `FramePipelineCoordinator` | Only depth-coordinate tests; no per-frame orchestration tests (target box selection, `requireLicensePlate`, median depth) | Build with mocks (`MockObjectDetector`, `MockVisionTracker`, `MockVerifierService`, `MockNavigationSpeaker`) and assert `tickCallCount` / `lastTargetBox` / `lastDistance` |
| `FrameNavigationManager` | 2 tests; controller ordering and `hasActiveMatch` gating mostly untested | Inject mocks and assert speech order |
| `Speaker`, `SmoothBeeper`, `HapticManager`, `AudioControl` | Untested (AVFoundation/UIKit side effects) | Test pause/resume notification handling; keep audio output behind protocols |
| `EmbeddingComputer` / `VisionEmbeddingProvider` | No tests | Use `Assets/` images (see below) |
| `CompassHeading`, `LanguageManager` | No dedicated tests (Levenshtein is covered via `OCREngineTests`) | Small pure-function tests |
| `CandidateStore` concurrency | Only `test_threadSafety_concurrentUpdates`; unsynchronized reads (`containsDuplicateOf`, `hasActiveMatch`) not covered | Concurrent reads + writes from background queues with `XCTestExpectation` |
| Frame providers (`VideoCapture`, `ARVideoCapture`, `VideoFileFrameProvider`) | Untested | `VideoFileFrameProvider` with a short bundled clip |

### Planned integration tests (not yet created)

| File (planned) | Purpose |
| -------------- | ------- |
| `Integration/EmbeddingIntegrationTests.swift` | Using `Assets/`: `Car1_Base` vs `Car1_Base_shift` should be highly similar (> 0.90, the drift-repair threshold); `Car1_Base` vs `Car1_Back` / `Car2_side` lower. Calibrates `DriftRepairService.simThreshold`. |
| `Integration/AppContainerIntegrationTests.swift` | `makePipeline` wires all services, shares one `Settings`, picks `.paratransit` vs `.hybrid`, enables OCR only for vehicle classes with a parsed plate. Needs the YOLO model in the test bundle. |
| `Integration/FramePipelineCoordinatorIntegrationTests.swift` | Pump frames from `VideoFileFrameProvider` through real detector/tracker/drift repair with `MockVerifierService` and `MockNavigationSpeaker`: detect, track, exit to `.lost`, presentation published, non-target classes ignored. |

Assets still needed for pipeline integration: short (5–10 s, 720p/1080p, 30 fps) clips of a single car entering/exiting, a partially occluded car, and 2–3 cars. Add them under `thing-finderTests/Assets/` with `thing-finderTests` target membership.

### Future

| Type | Scope |
| ---- | ----- |
| Snapshot | `CameraOverlayView`, `BoundingBoxView` (status colors), `SettingsView` (`swift-snapshot-testing` or XCTest attachments) |
| Performance | Detection under 50 ms/frame, embedding under 100 ms/crop, pipeline above 25 fps, tracking under 20 ms with 10 candidates (`measure {}` on device) |
| CI | No CI workflow runs tests yet. Target: unit tests on every push, under 2 min |

### Manual end-to-end checklist (device, release)

| Scenario | Expected |
| -------- | -------- |
| Start search | "Searching for {description}" |
| Point at matching car | "Possible match — plate not visible" or "Found it[ — plate X]"; success haptic if haptics are on; then direction, beeps, distance milestones |
| Point at wrong car | "Not yours — {desc}"; dense lots collapse to "Several cars nearby, still looking" |
| Car leaves view, user turns > 60° | "car was last seen N degrees to the left/right" |
| Car occluded under 3 s | Stays matched; guidance resumes |
| Airplane mode mid-search | "Connection lost — search paused", then "Connection restored — search resumed" |
| VoiceOver magic tap | Pauses/resumes speech, beeps, haptics and camera |
| Spanish language | Phrases and TTS voice in Spanish |
| Low light | Graceful degradation, no crash |
