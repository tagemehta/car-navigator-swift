# CurbToCar (thing-finder) Onboarding Guide

Last verified against code: 2026-10-27 (working tree, including uncommitted verifier-model migration).

## Project Overview

CurbToCar is an assistive iOS app for blind and low-vision users. It helps them identify and walk to their rideshare car or paratransit vehicle, and to general objects. The repo, Xcode project, and Swift module are called `thing-finder`. The user-facing name is **CurbToCar**.

It combines on-device YOLO detection with TrafficEye/OpenAI verification and on-device license-plate OCR. Guidance is delivered through speech, beeps, and haptics. A Meta Ray-Ban glasses capture path is implemented: enabled on branch `meta-s26`, commented out on `main` (see [Meta glasses](#meta-glasses-enabled-on-meta-s26-disabled-on-main)).

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [User Flow](#user-flow)
3. [Folder-by-Folder Reference](#folder-by-folder-reference)
4. [Core Architecture](#core-architecture)
5. [Key Concepts](#key-concepts)
6. [Python Tooling](#python-tooling)
7. [Engineering Principles](#engineering-principles)
8. [Further Reading](#further-reading)

---

## Getting Started

### Prerequisites
- Xcode 15+, iOS 16+ deployment target. No third-party SPM dependencies are active.
- A device with a camera. A LiDAR device gives the best distance cues. The simulator plays a bundled video (`IMG_7211.MOV`) instead of the camera.
- `thing-finder/Secrets.xcconfig` (gitignored) defines `PROXY_BASE_URL` and `PROXY_APP_TOKEN`. `Info.plist` expands them, and `APIProxy` reads them via `Bundle.main.infoDictionary`. Provider keys live only in the Cloudflare Worker (`proxy/`).
- `thing-finder/CVModels/` (gitignored) must contain `yolo11n.mlpackage`. `Image2Image.mlmodel` is only referenced by commented-out code.

### Build & test
- Schemes: `thing-finder` (dev) and `thing-finder-prod`. Test target: `thing-finderTests`, test plan `thing-finderTests/thing-finder.xctestplan`.
- Exact `xcodebuild` commands: `.agents/skills/ios-build-test/SKILL.md`.

---

## User Flow

1. **Launch.** `ThingFinderApp` shows `ExperimentalDisclaimerView` once (`hasAcceptedExperimentalDisclaimer`), then `MainTabView` with the **Find** (`InputView`) and **Settings** (`SettingsView`) tabs.
2. **Input** (`InputView`). The user types or pastes a vehicle description and can toggle **Paratransit**. Search classes are fixed to `car`, `truck`, `bus`. The 80-class object picker exists in code but never renders. Favorites and recents (max 5) appear only when `show_favorites_and_recents` is on (default **off**).
3. **Offline gate.** A search with a description first awaits `NetworkMonitor.currentConnectivity()` and is blocked if offline. Description-less object searches run fully on-device.
4. **Detection screen** (`ContentView`). It hosts `DetectorContainer` with Pause/Resume and **Double Check**. Double Check changes `detectorKey`, which rebuilds the whole pipeline. **Magic Tap** pauses or resumes all audio.
5. **Siri / Shortcuts** (`AppShortcuts.swift`). `FindCarIntent` and `FindParatransitIntent` ("find my car with CurbToCar") open the app. They pass the description through `ShortcutNavigationState`, which `InputView` consumes.
6. **Settings.** Language (system/English/Spanish; needs a restart), navigation toggles (beeps, speech, haptics, partial nav, announcements), speech rate, display options. An Advanced toggle reveals direction/beep tuning and the debug overlay. There is also a help sheet and a feedback email (`assistivetech@mit.edu`).

---

## Folder-by-Folder Reference

### `thing-finder/App/`
| File | Purpose |
|------|---------|
| `App.swift` | `@main ThingFinderApp`. Injects `Settings` and the locale. `MainTabView`, `ExperimentalDisclaimerView`. Meta glasses setup (configure, `onOpenURL`) is live on `meta-s26`, commented out on `main`. |
| `AppShortcuts.swift` | App Intents (`FindCarIntent`, `FindParatransitIntent`), Siri phrases, and the `ShortcutNavigationState` hand-off singleton. |

### Root of `thing-finder/`
| File | Purpose |
|------|---------|
| `AppContainer.swift` | Composition root. `makePipeline(classes:description:isParatransitMode:settings:)` builds a `FramePipelineCoordinator` with the YOLO model, tracker, drift repair, lifecycle, `VerifierService` (strategy `.hybrid` or `.paratransit`), and `FrameNavigationManager`. It also parses license plates via `DescriptionParser`. |
| `Info.plist` | Only `PROXY_BASE_URL` and `PROXY_APP_TOKEN`, expanded from `Secrets.xcconfig`. |
| `Localizable.xcstrings`, `InfoPlist.xcstrings` | English source with Spanish translations. |
| `Debugging.swift` | Dead file; entirely commented out. |

### `thing-finder/Core/`
| File | Purpose |
|------|---------|
| `Candidate.swift` | Value type for a tracked object. Fields include `trackingRequest`, `lastBoundingBox`, `embedding`, `matchStatus`, `verificationTracker`, `rejectReason`, `ocrText`, `view` (`VehicleView`), `degrees`, and `missCount`. **`isBoundingBoxFresh` (`missCount == 0`) must be checked before using a box for direction or depth.** Also defines `MatchStatus` and `RejectReason` (with `isRetryable`). |
| `CandidateStore.swift` | `ObservableObject` dictionary. Every mutation goes through `syncOnMain` (`DispatchQueue.main.sync` when off-main). `containsDuplicateOf`: IoU > 0.6 or center distance < 0.15. `pruneToSingleMatched` keeps the newest `.full`. |
| `DetectionStateMachine.swift` | Pure reducer: no candidates → `.searching`, any `.full` → `.found(id)`, otherwise `.verifying(allIDs)`. |
| `FeatureFlags.swift` | `metaGlassesEnabled` (true in DEBUG, false in release). It has no effect while the glasses code is commented out. |
| `TrackingRequest.swift`, `VisionAbstractions.swift` | Testable wrappers: `TrackingRequest`, `Detection`, `EmbeddingProtocol`/`Embedding`. |

### `thing-finder/Models/`
| File | Purpose |
|------|---------|
| `Settings.swift` | `@AppStorage` preferences. Navigation-relevant defaults: `enable_beeps`/`enable_speech` true, `enable_haptics` **false**, `allow_partial_nav` true, `speech_rate` 0.5, beep interval 0.1–1.0 s, direction thresholds 0.33/0.66, `use_ar_mode` false. Also `SupportedLanguage`, `Direction`, and `hasLiDAR`. |
| `SearchMode.swift` | `.uberFinder` / `.objectFinder`. |
| `SearchHistoryItem.swift` | Codable favorite/recent entry (description, mode, paratransit, favorite). |
| `DetectionPhase.swift` | `searching`, `verifying(candidateIDs:)`, `found(candidateID:)`. |
| `OpenAIModel.swift` | Chat Completions request/response structs. `ChatCompletionRequest.verifierModel` is shared by every verifier. |
| `BoundingBoxModel.swift`, `DebugOverlayModel.swift` | UI models. |

### `thing-finder/Views/`
| File | Purpose |
|------|---------|
| `InputView.swift` | Home screen (described above). Navigates to `ContentView` via `navigationDestination(item:)`. |
| `ContentView.swift` | Detection screen: Pause/Resume, Double Check (`detectorKey` reset), Magic Tap. |
| `DetectorContainer.swift` | Owns `CameraViewModel`. `computeCaptureSource()` returns `.arKit` if `use_ar_mode`, else `.avFoundation`. It is computed **once** in `onAppear`. Composes the preview, box overlay, FPS readout, and debug overlay. |
| `CameraPreviewView.swift` | `CameraPreviewWrapper` (forces `.videoFile` on simulator DEBUG builds) plus the representable and coordinator that create and hot-swap the `FrameProvider`. |
| `SettingsView.swift`, `HelpModalView.swift`, `FeedbackSection.swift` | Settings, help guide, and the feedback mail composer. |
| `BoundingBox.swift`, `DebugOverlayView.swift` | Overlays. |
| `MetaGlasses*View.swift`, `CompassView.swift` | Live on `meta-s26`; commented out on `main`. |

### `thing-finder/ViewModels/`
| File | Purpose |
|------|---------|
| `CameraViewModel.swift` | `FrameProviderDelegate`. Builds the pipeline via `AppContainer` and computes orientation (`.up` for glasses). Calls `pipeline.process(...)` with the `depthAt` closure. Republishes boxes on the main thread. |

### `thing-finder/FramePublishers/`
| File | Purpose |
|------|---------|
| `FramePublisher.swift` | `FrameProvider` and `FrameProviderDelegate.processFrame(buffer:depthAt:)`. `depthAt` takes **a batch of normalized points** and returns `[Float?]` metres. |
| `VideoCapture.swift` | AVFoundation. Prefers the LiDAR depth camera. Uses `AVCaptureDataOutputSynchronizer` for video plus depth. Frames are processed on `camera-queue`. |
| `ARVideoCapture.swift` | ARKit. Uses the scene-depth map, falling back to raycasts. Raycasts need **view** coordinates, converted via `ImageUtilities`. |
| `VideoFileFrameProvider.swift` | Loops the bundled `IMG_7211.MOV` for the simulator. No depth. |
| `MetaGlassesFrameProvider.swift` | Glasses path (live on `meta-s26`, commented out on `main`). |

`CaptureSourceType` (in `PipelineProtocols.swift`): `.avFoundation`, `.arKit`, `.videoFile`, `.metaGlasses`.

### `thing-finder/Services/`

#### `Services/Coordinator/FramePipelineCoordinator.swift`
The heart of the app. It runs each frame synchronously on the caller's queue. The order is listed under [Core Architecture](#core-architecture). Distance is the **median of 5 depth samples** (the center plus 4 quarter points) inside the target box. The target box is used only when it is fresh. A `.partial` candidate is targeted only when `allow_partial_nav` is on.

#### `Services/Pipeline/`
| File | Purpose |
|------|---------|
| `PipelineProtocols.swift` | `ObjectDetector`, `VisionTracker`, `VerifierServiceProtocol`, `DriftRepairServiceProtocol`, `CaptureSourceType`, … |
| `DetectionManager.swift` | YOLO via `VNCoreMLRequest`, filtered to the target classes. `stableDetections()` exists but is unused. |
| `TrackingManager.swift` | `VNSequenceRequestHandler` tracker. **See `KNOWN_BUGS.md`:** nothing calls `addTracking`, so per-frame tracking is currently a no-op. |
| `DriftRepairService.swift` | Runs every **15** frames. Re-associates candidates with detections by embedding similarity ≥ **0.90**. It can recover `.lost` → `.full`. When there is no match, it zeroes the box on purpose to speed up eviction. |
| `CandidateLifecycleService.swift` | Ingests detections that don't overlap an existing candidate (skipped once a `.full` exists). Resets `missCount` when a detection overlaps with IoU > 0.1. `missThreshold` is **90** frames: `.full` → `.lost`, everything else is removed. `rejectCooldown` is 10 s. Caps candidates at **10** by evicting the highest `missCount`; `.partial`/`.full` are never evicted. |
| `VisionEmbeddingProvider.swift` | Feature-print embeddings for crops. |

#### `Services/Pipeline/Verification/`
Full details are in its `README.md`. In summary:
- `VerifierService.tick` checks `.unknown` candidates at most once per second. It skips boxes under 1% of the frame or with an aspect ratio over 3:1, enforces 0.8 s per-candidate spacing, and pauses while offline.
- `VerifierSelector` picks an engine from `VerificationConfig.strategy`, applies a 10 s timeout, maps errors to retryable outcomes, and reports to `APIHealthMonitor`.
- **Hybrid** (car search): `TrafficEyeVerifier` (TrafficEye make/model/color, then a `gpt-6-luna` text comparison; reads with infoQ < 0.85 are retried without the LLM). Any TrafficEye non-match escalates to `TwoStepVerifier` (LLM extract, then compare). Only TwoStep's mismatch is a hard reject.
- **Paratransit:** always `AdvancedLLMVerifier` (one image call; match / unclear / reject). `.llmOnly` and `.trafficEyeOnly` exist but are unused.
- **Plates** (when one is parsed from the description): an exact TrafficEye plate match gives `.full`. Otherwise `.partial`, and Vision OCR decides by Levenshtein distance: ≤ 1 → `.full`, 2 → keep trying, more → `.rejected`.
- `NetworkErrorClassifier` separates connectivity failures from other errors so network-health tracking stays accurate.
- **In progress (uncommitted):** migrating from `gpt-4.1-mini` (removed from the API on 2027-01-14) to `gpt-6-luna` with `max_completion_tokens: 300` and `reasoning_effort: "none"`.

#### `Services/Pipeline/Navigation/`
`FrameNavigationManager.tick()` runs its controllers in this order. They share `AnnouncementCache`, because `Speaker.speak` interrupts whatever is currently playing.

| Controller | Responsibility |
|---|---|
| `NetworkFeedbackController` | Offline, connection lost/restored, and weak-signal/improved announcements and haptics. Claims priority for the frame. |
| `PreMatchFeedbackController` | Owns all speech before a match: "Searching for …", a stable-candidate **detection haptic** (0.3 s gate, 0.5 s cooldown), a "Still looking" heartbeat every 20 s, and rejections. Three or more rejections in 30 s collapse to "Several cars nearby". |
| `NavAnnouncer` | Speaks only on transitions to `.partial`/`.full`/`.lost`, plus vehicle-view phrases. Plays the success haptic on a match. |
| `DirectionSpeechController` | Left/ahead/right, spoken only when the category changes (debounced to 4 s). |
| `DistanceMilestoneController` | 10/5/2/1 m ("almost there"), using locale units, 1.5 m hysteresis, and only the closest milestone when several are crossed at once. Silent without depth. |
| `HapticBeepController` | Beep rate follows **centering**. Haptic pulse rate follows **distance** (a steady pulse when there's no depth). |

`NavigationProtocol.swift` holds `NavigationFeedbackConfig` (timing constants) and the `SpeechOutput`/`Beeper`/`NavigationSpeaker` protocols.

#### `Services/MetaGlasses/` (live on `meta-s26`)
`MetaGlassesViewModel`: one consolidated DAT 1.0 view model (registration, permission, `DeviceSession` + `Stream`, raw/720p/30fps, `displayPhase` for the error overlay). It replaced MetaGlassesManager / MetaGlassesEnvironment / WearablesViewModel / StreamSessionViewModel.

#### `Services/FPSManager.swift`
Rolling one-second FPS, capped at 60.

### `thing-finder/Utilities/`
| File | Purpose |
|------|---------|
| `ImageUtilities.swift` | Vision ↔ pixel ↔ view rect transforms for every orientation, `cvPixelBuffertoCGImage`, `unscaledBoundingBoxes`. |
| `EmbeddingComputer.swift`, `CoreML/FeaturePrint+Similarity.swift` | Feature prints and cosine similarity remapped to 0–1. |
| `CoreML/ThresholdProvider.swift` | YOLO IoU/confidence override (0.45 / 0.25). Only `CameraDependencies` applies it. |
| `CameraDependencies.swift` | Dependency bundle for `CameraViewModel`. |
| `DescriptionParser.swift`, `String+Levenshtein.swift`, `CGRect+IoU.swift` | Plate token extraction (5–8 characters with at least one digit and one letter), fuzzy plate matching, and IoU. |
| `MatchStatusSpeech.swift`, `CompassHeading.swift` | Status phrases. A `.lost` target gets a compass hint when the heading has changed by more than 60°. Retry phrases are no longer spoken. |
| `LanguageManager.swift` | Overrides `AppleLanguages` with en/es/system. |
| `DebugPublisher.swift`, `DeviceRotationViewModifier.swift`, `Constants.swift` | Debug messages, rotation callbacks, and the box palette. |
| `Audio/` | `Speaker` (AVSpeechSynthesizer; each `speak` interrupts the current one), `SmoothBeeper` (EMA interval), `HapticManager` (pulses plus success/failure/detection), `AudioControl` (pause/resume all). |
| `Networking/` | `NetworkMonitor` (an NWPathMonitor singleton; `currentConnectivity()` waits up to 0.3 s for the first callback on cold start), `APIHealthMonitor` (degraded after 3 consecutive connectivity failures), and `URLSessionProtocol` (a dependency-injection shim). |

### `thing-finderTests/`
XCTest, grouped by layer: `Core/`, `Models/`, `Services/`, `Navigation/`, `Verification/`, `Utilities/`. Shared fakes for every protocol are in `Mocks/`, canned API JSON and candidates in `Fixtures/`, and test photos in `Assets/`. See `thing-finder/Docs/TestingPlan.md` for coverage and gaps.

---

## Core Architecture

```
SwiftUI:  InputView → ContentView → DetectorContainer → BoundingBox overlay
                                          │
FrameProvider (VideoCapture | ARVideoCapture | VideoFileFrameProvider)
                                          │ processFrame(buffer, depthAt)
CameraViewModel ─────────────────────────▶ FramePipelineCoordinator.process()
  1. DetectionManager.detect            (YOLO, class filter)
  2. TrackingManager.tick               (Vision tracking; see KNOWN_BUGS)
  3. DriftRepairService.tick            (every 15 frames, embeddings)
  4. CandidateLifecycleService.tick     (ingest, missCount, cap, lost)
  5. VerifierService.tick               (async TrafficEye/LLM/OCR)
  6. DetectionStateMachine.update       (searching/verifying/found)
  7. target box + 5-point median depth
  8. FrameNavigationManager.tick        (network → pre-match → announcer → direction → milestones → beeps/haptics)
  9. publish FramePresentation {phase, candidates}
                                          │
CandidateStore (main-thread-synchronized dictionary of Candidate values)
```

The pipeline runs synchronously on the capture queue (`camera-queue` for AVFoundation). Store writes are synchronized onto the main thread. Verification network calls are asynchronous (Combine) and write results back through the store.

---

## Key Concepts

### Match Status
```
unknown → waiting → partial (vehicle matched, plate pending)
                  → full    (complete match)  → lost (missed 90 frames; drift repair can restore it)
                  → rejected (hard reject; removed after 10 s)
```
Retryable reject reasons (`unclearImage`, `lowConfidence`, `insufficientInfo`, `apiError`, `ambiguous`, `licensePlateNotVisible`, `networkError`) keep the candidate eligible for another attempt. Hard ones (`wrongModelOrColor`, `licensePlateMismatch`, `wrongObjectClass`) reject it.

### Single-winner invariant
Once any candidate is `.full`, lifecycle stops ingesting new detections and `pruneToSingleMatched` keeps only the newest match.

### Speech ownership
Before a match, `PreMatchFeedbackController` does all the talking. After a match, speech is driven by transitions and milestones. Record an announcement only after speech actually fires, and respect the same-tick `AnnouncementCache` checks.

### Network health
`NetworkMonitor` detects outages and `APIHealthMonitor` detects weak signal. TrafficEye reports network failures as an outcome (`RejectReason.networkError`) rather than as a publisher error. `VerificationOutcome.didCompleteNetworkRequest` keeps local failures from clearing the degraded state.

### Meta glasses (enabled on `meta-s26`, disabled on `main`)
On `meta-s26` the code is live on DAT SDK 1.0.0; required Info.plist keys, build-setting usage strings, and Wi-Fi/Hotspot entitlements are listed in the `meta-wearables-dat` skill. On `main`, since 2026-04-04 the glasses code has been commented out ("COMMENTED OUT FOR APP STORE SUBMISSION") and the DAT SDK has been removed from `Package.swift`. To re-enable it, restore all of the following:
- **Code:** the Package dependency; in `App.swift`, the configure call, environment objects, and `onOpenURL`; in `DetectorContainer`, the environment objects, the capture-source branch, and the `onChange` observers; the `CameraPreviewView` provider case; the Settings and Help sections.
- **`Info.plist` keys:** MWDAT, URL scheme, Bluetooth, and background modes.

Also fix the `KNOWN_BUGS.md` re-pair issue. SDK guidance is in `.agents/skills/meta-wearables-dat/`.

---

## Python Tooling

The Python tooling is not part of the app build. See `scripts/README.md`, `evals/README.md`, and `evals/realworld/README.md`.
- `evals/realworld/`: real-image, end-to-end evaluation of the Swift verifier pipelines (TrafficEye, TwoStep, single-call, Carmen). Used to choose `gpt-6-luna` and the new thresholds.
- `evals/*.py`: an older harness that grades only the text-comparison step, using synthetic TrafficEye outputs.
- `scripts/`: dataset generation (`gen_car_eval*.py`, `build_uber_allow.py`), CSV analysis, and an API health check.
- **Cost guardrail:** eval scripts refuse runs of more than 60 API requests without `--yes`. Runs of about 1k requests or more need the maintainer's approval.
- `datasets/`, `evals/cache/`, and `results/` are gitignored.

---

## Engineering Principles

1. **Safe from bugs.** Thread-safe store, timeouts on every network call, and graceful degradation when offline. A wrong announcement can physically mislead a blind user.
2. **Easy to understand.** Protocol-based services, one per-frame data flow, and value types where possible.
3. **Ready for change.** Dependency injection via `AppContainer`, a strategy-based verifier selection, and a mock for every protocol in `thing-finderTests/Mocks/`.

---

## Further Reading

| Topic | Doc |
|---|---|
| Verification internals | `thing-finder/Services/Pipeline/Verification/README.md` |
| Navigation and audio behavior | `thing-finder/Docs/NavigationBehavior.md` |
| Design decisions | `thing-finder/Docs/DesignDecisions.md` |
| Test coverage and plan | `thing-finder/Docs/TestingPlan.md` |
| Open bugs | `KNOWN_BUGS.md` |
| Agent setup (Devin / Claude Code / Codex) | `AGENTS.md` |

## Contact

For questions: assistivetech@mit.edu
