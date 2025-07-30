# Object-Detection Pipeline Overview

This document describes the _per-frame_ flow of data through the refactored
thing-finder pipeline, the responsibilities of each service, and how everything
is composed in `AppContainer`.

---

## High-Level Diagram

```text
   +-------------------------+       +------------------+
   |     Camera (AV/AR)      |       | SwiftUI Overlay  |
   +-----------+-------------+       +------------------+
               |                                   ^
               v                                   |
   +-------------------------+   phase/candidates   |
   | FramePipelineCoordinator|----------------------+
   +-------------------------+
        |        |       |  | lost/found/searching
        |        |       |  +------------------+
        |        |       |                     |
        v        v       v                     |
  detector  tracker  driftRepair         NavigationManager
        |        |       |
        +----+   |       |
             |   |       |
             v   |       |
      CandidateLifecycleService <---- verifier
             |
             v
       CandidateStore
```

---

## Per-Frame Flow (`FramePipelineCoordinator.process`)

1. **Detection** – `ObjectDetector.detect` produces `VNRecognizedObjectObservation`
   filtered to target classes.
2. **Tracking update** – `VisionTracker.tick` updates each `VNTrackObjectRequest`
   already stored in `CandidateStore`.
3. **Drift repair** – `DriftRepairService.tick` (every _N_ frames) tries to
   re-associate drifting boxes with fresh detections using IoU + embedding
   similarity.
4. **Lifecycle ingest & maintenance** – `CandidateLifecycleService.tick`:
   • Inserts non-duplicate detections (creates tracking request, initial
   embedding).
   • Enforces _single-winner_ rule (`store.pruneToSingleMatched()`).
   • Maintains `missCount`, removes stale candidates. Returns `isLost`.
5. **Verification** – `VerifierService.tick` asynchronously calls the LLM/
   classifier and updates `Candidate.matchStatus`.
6. **Phase update** – `DetectionStateMachine` produces overall phase which is
   published (plus candidate snapshots) to SwiftUI.
7. **Navigation cues** – `NavigationManager` receives high-level nav events
   (`.found`, `.searching`, `.lost`).
8. **UI publish** – SwiftUI overlay renders bounding boxes & status.

---

## Key Services

| Service                       | Responsibility                                                                    |
| ----------------------------- | --------------------------------------------------------------------------------- |
| **ObjectDetector**            | Synchronous ML inference via CoreML/Vision.                                       |
| **VisionTracker**             | Maintains per-candidate `VNTrackObjectRequest`.                                   |
| **DriftRepairService**        | Periodically fixes tracker drift by matching detections back to candidates.       |
| **CandidateLifecycleService** | Ingests new detections, computes embeddings, enforces single-winner, drops stale. |
| **VerifierService**           | Asynchronously validates a candidate using LLM / feature-print.                   |
| **NavigationManager**         | Emits coarse nav events for downstream UX (haptics, audio, etc.).                 |
| **CandidateStore**            | Thread-safe `@Published` map of `Candidate` models.                               |
| **DetectionStateMachine**     | Derives high-level phase (`searching`, `verifying`, `found`).                     |

All heavy Vision / ML work happens off the main thread; UI only receives immutable
snapshots (`FramePresentation`).

---

## Dependency Injection (`AppContainer`)

`AppContainer.shared.makePipeline(...)` creates concrete instances and wires
services:

```swift
let lifecycle = CandidateLifecycleService()
let coordinator = FramePipelineCoordinator(
    detector: detector,
    tracker: tracker,
    driftRepair: drift,
    verifier: verifier,
    nav: nav,
    lifecycle: lifecycle)
```

Tests can inject mocks for any protocol-typed dependency.

---

## Candidate Model Cheatsheet

| Property          | Purpose                                          |
| ----------------- | ------------------------------------------------ |
| `trackingRequest` | Vision request updating `lastBoundingBox`.       |
| `embedding`       | 768-D feature-print for drift repair + verifier. |
| `matchStatus`     | `.unknown`, `.waiting`, `.matched`, `.rejected`. |
| `missCount`       | Frames since candidate overlapped a detection.   |

---

## Extending the Pipeline

- **Different detector model** – Implement `ObjectDetector` protocol.
- **Alternative verifier** – Swap `VerifierServiceProtocol`.
- **Custom nav behavior** – Implement `NavigationManager`.
- **AR-only mode** – Provide a tracker that backs onto `ARAnchor`s.

---

_Last updated: 2025-07-15_
