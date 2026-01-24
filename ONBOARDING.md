# Thing Finder Onboarding Guide

## Project Overview

Thing Finder is an assistive technology iOS app for blind users that helps identify and navigate to vehicles (rideshare) and objects. It combines YOLO object detection with LLM/API verification and provides audio/haptic navigation feedback.

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Folder-by-Folder Reference](#folder-by-folder-reference)
3. [Core Architecture](#core-architecture)
4. [Data Flow](#data-flow)
5. [Key Concepts](#key-concepts)
6. [Engineering Principles](#engineering-principles)

---

## Getting Started

### Prerequisites
- Xcode 14+
- iOS device with camera (simulator supported via video file playback)
- API keys in `Secrets.xcconfig`: `TRAFFICEYE_API_KEY`, `OPENAI_API`

### Quick Start
1. Clone repo, open `thing-finder.xcodeproj`
2. Add API keys to `thing-finder/Secrets.xcconfig`
3. Build & run on device

---

## Folder-by-Folder Reference

### `thing-finder/App/`
**Entry point and root navigation.**

| File | Purpose |
|------|---------|
| `App.swift` | `@main` entry. Contains `MainTabView` (Find + Settings tabs) and `ExperimentalDisclaimerView` shown on first launch. |

### `thing-finder/AppContainer.swift`
**Dependency injection / composition root.**

- Singleton `AppContainer.shared` wires all services together
- `makePipeline(classes:description:)` builds a fully-configured `FramePipelineCoordinator`
- Parses license plate from description via `DescriptionParser`
- Configures: `DetectionManager`, `TrackingManager`, `DriftRepairService`, `VerifierService`, `FrameNavigationManager`, `CandidateLifecycleService`

---

### `thing-finder/Core/`
**Central domain models and state machine.**

| File | Purpose |
|------|---------|
| `Candidate.swift` | Value type representing a tracked object. Key fields: `id`, `trackingRequest`, `lastBoundingBox`, `embedding`, `matchStatus`, `verificationTracker`, `view` (front/rear/side), `missCount`, `ocrText`. |
| `CandidateStore.swift` | Thread-safe `@Published` dictionary of candidates. All mutations go through `syncOnMain` for SwiftUI safety. Methods: `upsert`, `update`, `remove`, `containsDuplicateOf` (IoU + center distance). |
| `DetectionStateMachine.swift` | Pure reducer: given candidate snapshot → derives `DetectionPhase` (`.searching`, `.verifying`, `.found`). |

**MatchStatus enum values:** `unknown` → `waiting` → `partial`/`full`/`rejected`/`lost`

---

### `thing-finder/Models/`
**Data models and configuration.**

| File | Purpose |
|------|---------|
| `Settings.swift` | `@AppStorage`-backed user preferences. Navigation thresholds, beep intervals, speech rate, detection confidence, developer mode toggle, etc. |
| `SearchMode.swift` | Enum: `.uberFinder` (vehicles) vs `.objectFinder` (80 YOLO classes). |
| `DetectionPhase.swift` | Enum for pipeline state: `searching`, `verifying(candidateIDs:)`, `found(candidateID:)`. |
| `DebugOverlayModel.swift` | Observable model for on-screen debug messages. Subscribes to `DebugPublisher`. |
| `OpenAIModel.swift` | Request/response structs for OpenAI chat completions API (tool calls). |
| `BoundingBoxModel.swift` | Simple struct: `imageRect`, `viewRect`, `label`, `color`. |

---

### `thing-finder/Views/`
**SwiftUI views.**

| File | Purpose |
|------|---------|
| `InputView.swift` | Home screen. Text field for vehicle description, object class picker, "Find My Ride" button → navigates to `ContentView`. |
| `ContentView.swift` | Detection screen wrapper. Contains `DetectorContainer`, Pause/Resume/Rescan buttons. Changing `detectorKey` UUID forces full pipeline reset. |
| `DetectorContainer.swift` | Owns `CameraViewModel` as `@StateObject`. Composes camera preview + bounding box overlay + FPS display + optional debug overlay. |
| `CameraPreviewView.swift` | `UIViewControllerRepresentable` wrapping `FrameProvider`. Coordinator holds the actual capture instance. |
| `BoundingBox.swift` | Renders colored rectangles over detected objects. |
| `DebugOverlayView.swift` | Scrollable list of debug messages (error/warning/info/success). |
| `SettingsView.swift` | User-configurable navigation, beep, and developer settings. |
| `CompassView.swift` | (Commented out) Compass display for directional guidance. |

---

### `thing-finder/ViewModels/`
**View models bridging UI and services.**

| File | Purpose |
|------|---------|
| `CameraViewModel.swift` | Implements `FrameProviderDelegate`. On each frame: caches dimensions, calls `pipeline.process(...)`, subscribes to `pipeline.$presentation` to update `@Published boundingBoxes`. |

---

### `thing-finder/FramePublishers/`
**Camera frame sources conforming to `FrameProvider` protocol.**

| File | Purpose |
|------|---------|
| `FramePublisher.swift` | Protocols: `FrameProvider` (start/stop/previewView) and `FrameProviderDelegate` (processFrame callback with pixel buffer + depth closure). |
| `VideoCapture.swift` | AVFoundation capture. Uses `AVCaptureDataOutputSynchronizer` for synchronized video + depth. Handles device rotation. |
| `ARVideoCapture.swift` | ARKit capture. Uses `ARSession` with scene depth and raycasting for depth lookup. |
| `VideoFileFrameProvider.swift` | Plays local `.MOV` file for simulator testing. Uses `CADisplayLink` to pump frames. |

**CaptureSourceType enum:** `.avFoundation`, `.arKit`, `.videoFile`

---

### `thing-finder/Services/`
**Business logic services.**

#### `Services/Coordinator/`

| File | Purpose |
|------|---------|
| `FramePipelineCoordinator.swift` | **Heart of the app.** Per-frame orchestrator. Calls in order: detector → tracker → driftRepair → lifecycle → verifier → stateMachine → navigation → publishes `FramePresentation`. |

#### `Services/Pipeline/`

| File | Purpose |
|------|---------|
| `PipelineProtocols.swift` | Protocols: `ObjectDetector`, `VisionTracker`, `VerifierServiceProtocol`, `DriftRepairServiceProtocol`, `NavigationSpeaker`, etc. |
| `DetectionManager.swift` | `ObjectDetector` impl. Runs `VNCoreMLRequest` with YOLO model. `stableDetections()` filters by consecutive-frame persistence. |
| `TrackingManager.swift` | `VisionTracker` impl. Executes `VNTrackObjectRequest`s via `VNSequenceRequestHandler`. Updates candidate bounding boxes. |
| `DriftRepairService.swift` | Every N frames (default 15), re-associates candidates with fresh detections using IoU + embedding cosine similarity (threshold 0.90). Prevents tracker drift. |
| `CandidateLifecycleService.swift` | Ingests new detections (if no active match), enforces single-winner invariant, increments `missCount`, removes stale/rejected candidates. |
| `FPSManager.swift` | Calculates and publishes FPS from frame timestamps. |

#### `Services/Pipeline/Navigation/`

| File | Purpose |
|------|---------|
| `NavigationProtocol.swift` | Protocols: `SpeechOutput`, `Beeper`, `NavigationSpeaker`. Config struct for timing thresholds. |
| `NavigationManager.swift` | `FrameNavigationManager` façade. Composes `NavAnnouncer`, `DirectionSpeechController`, `HapticBeepController`. Single `tick()` call per frame. |
| `NavAnnouncer.swift` | Phrase selection engine. Handles status transitions, retry announcements, cooldown suppression. |
| `DirectionSpeechController.swift` | Speaks "left/right/straight ahead" based on target position. |
| `HapticBeepController.swift` | Maps target centering → beep interval. Drives `SmoothBeeper`. |
| `AnnouncementCache.swift` | Shared state for phrase throttling across controllers. |

#### `Services/Pipeline/Verification/`

**Strategy pattern for verification.** Two main engines cycle until match or hard reject:

| File | Purpose |
|------|---------|
| `VerifierService.swift` | Frame-driven orchestrator. Rate-limits verification, crops images, delegates to `VerificationStrategyManager`, handles OCR for license plates. |
| `VerificationStrategy.swift` | Protocol + `VerificationStrategyManager`. Selects best strategy by `shouldUse()` + `priority()`. Resets opposite counter when switching engines. |
| `BaseVerificationStrategy.swift` | Abstract base with timeout handling (5s on main queue), error mapping, retry logic. |
| `TrafficEyeStrategy.swift` | Wraps `TrafficEyeVerifier` in strategy pattern. |
| `TrafficEyeVerifier.swift` | Calls TrafficEye API for fast MMR (make/model recognition). Returns view angle, confidence, plate text. |
| `LLMStrategy.swift` | Wraps `TwoStepVerifier` in strategy pattern. |
| `TwoStepVerifier.swift` | Two-step OpenAI verification: (1) extract make/model/color, (2) match against description. |
| `AdvancedLLMStrategy.swift` | Last-resort LLM with higher token budget. |
| `VerificationConfig.swift` | Config: expected plate, OCR settings, retry limits, MMR interval. |
| `VerificationPolicy.swift` | Escalation logic: TrafficEye fails → LLM, LLM fails → back to TrafficEye. |
| `VerificationStrategyFactory.swift` | Creates strategy manager with configured strategies. |
| `VerifierService+OCR.swift` | OCR extension using Vision framework for license plate reading. |
| `VisionOCREngine.swift` | `OCREngine` impl using `VNRecognizeTextRequest`. |
| `ImageVerifier.swift` | Legacy protocol for verifiers. |

**Verification flow:**
1. TrafficEye (fast, view-aware) attempts first
2. On failure, counter increments → escalates to LLM
3. LLM failures escalate back to TrafficEye
4. Loops until match or hard reject (wrong make/model/plate)

**VerificationOutcome:** `isMatch`, `description`, `vehicleView`, `viewScore`, `rejectReason`, `isPlateMatch`

---

### `thing-finder/Utilities/`
**Shared helpers and utilities.**

| File | Purpose |
|------|---------|
| `ImageUtilities.swift` | Coordinate transforms between Vision normalized rects and pixel/view space. Handles all `CGImagePropertyOrientation` cases. `cvPixelBuffertoCGImage()`, `unscaledBoundingBoxes()`, `blurScore()`. |
| `EmbeddingComputer.swift` | Computes `VNFeaturePrintObservation` for images/crops. Used for drift repair similarity. |
| `CameraDependencies.swift` | Factory struct bundling all `CameraViewModel` dependencies. |
| `Constants.swift` | Color palette for bounding boxes. |
| `DescriptionParser.swift` | Extracts license plate tokens from natural language (5-8 alphanumeric with digit+letter). |
| `MatchStatusSpeech.swift` | Maps `MatchStatus` → spoken phrases. Includes compass-based "car was last seen X degrees to the left/right". |
| `CompassHeading.swift` | Singleton wrapping `CLLocationManager` for magnetic heading. |
| `DebugPublisher.swift` | Global singleton for publishing debug messages. Always prints to console; sends to overlay if enabled. |
| `CGRect+IoU.swift` | Extension for intersection-over-union calculation. |
| `String+Levenshtein.swift` | Edit distance for fuzzy plate matching. |
| `DeviceRotationViewModifier.swift` | SwiftUI modifier for orientation change callbacks. |

#### `Utilities/Audio/`

| File | Purpose |
|------|---------|
| `Speaker.swift` | `SpeechOutput` impl using `AVSpeechSynthesizer`. |
| `SmoothBeeper.swift` | `Beeper` impl. Generates click sounds, smoothly adjusts interval via EMA. Handles background/foreground transitions. |
| `AudioControl.swift` | Notification-based pause mechanism for all audio. |

#### `Utilities/CoreML/`

| File | Purpose |
|------|---------|
| `ThresholdProvider.swift` | Custom `MLFeatureProvider` to override YOLO IoU/confidence thresholds. |
| `FeaturePrint+Similarity.swift` | Extension for cosine similarity between `VNFeaturePrintObservation`s. |

---

### `thing-finder/Docs/`
**Internal documentation (may be outdated).**

- `PipelineOverview.md` – High-level architecture
- `VerificationStrategySystem.md` – Strategy pattern docs
- `LicensePlateVerification.md` – OCR flow
- `NavigationManagerRefactor.md` – Navigation system design
- `CodeReview.md`, `DocumentationStandard.md` – Style guides

---

### `thing-finderTests/`
**Unit tests using XCTest.**

Tests for lifecycle service, verification strategies, pipeline integration, and mock objects.

---

## Core Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         SwiftUI Layer                           │
│  InputView → ContentView → DetectorContainer → BoundingBoxes    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      CameraViewModel                            │
│  - Receives frames from FrameProvider                           │
│  - Delegates to FramePipelineCoordinator                        │
│  - Publishes boundingBoxes for UI                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  FramePipelineCoordinator                       │
│  Per-frame orchestration:                                       │
│  1. DetectionManager.detect()                                   │
│  2. TrackingManager.tick()                                      │
│  3. DriftRepairService.tick()                                   │
│  4. CandidateLifecycleService.tick()                            │
│  5. VerifierService.tick()                                      │
│  6. DetectionStateMachine.update()                              │
│  7. NavigationManager.tick()                                    │
│  8. Publish FramePresentation                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       CandidateStore                            │
│  Thread-safe dictionary of Candidate structs                    │
│  - Mutations sync to main thread                                │
│  - Duplicate detection via IoU + center distance                │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Flow

1. **Frame arrives** from `VideoCapture`/`ARVideoCapture`/`VideoFileFrameProvider`
2. **Detection** – YOLO finds objects, filters by target classes
3. **Tracking** – Vision updates existing candidate bounding boxes
4. **Drift Repair** – Every 15 frames, re-associates via embedding similarity
5. **Lifecycle** – Creates new candidates, removes stale ones (missCount > 15)
6. **Verification** – TrafficEye/LLM determines if candidate matches description
7. **State Machine** – Derives phase: searching → verifying → found
8. **Navigation** – Speaks status, plays beeps based on centering
9. **UI Update** – `FramePresentation` published, SwiftUI renders boxes

---

## Key Concepts

### Candidate Lifecycle
- **Created** when detection doesn't overlap existing candidate (IoU < 0.6)
- **Tracked** via `VNTrackObjectRequest` each frame
- **Verified** by TrafficEye → LLM escalation loop
- **Removed** when `missCount` exceeds threshold or hard rejected

### Match Status Flow
```
unknown → waiting → partial (vehicle matched, plate pending)
                  → full (complete match)
                  → rejected (wrong vehicle/plate)
                  → lost (was full, now out of frame)
```

### Verification Escalation
- TrafficEye attempts: 1 fail → try side view, 3 fails → escalate to LLM
- LLM attempts: 2 fails → back to TrafficEye
- Counters reset when switching engines

### Navigation Feedback
- **Speech**: Status announcements, directional cues, retry explanations
- **Beeps**: Interval varies with target centering (faster = more centered)
- **Compass**: Lost targets announced with compass direction

---

## Engineering Principles

1. **Safe from Bugs** – Thread-safe stores, timeout handling, graceful error recovery
2. **Easy to Understand** – Protocol-based services, clear data flow, value types where possible
3. **Ready for Change** – Dependency injection via `AppContainer`, strategy pattern for verification

---

## Contact

For questions: mitassistivetechnologyclub@gmail.com
