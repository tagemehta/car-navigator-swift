# Thing Finder – Architecture Guide

_Last updated: 2025-07-13_

This document is a high-level technical overview of the Thing Finder iOS app so another engineer can pick up the codebase quickly. It focuses on the **object-detection / navigation pipeline**; peripheral UI and settings screens are only covered briefly.

---

## 1 High-Level Data Flow

```
+----------------+      ARFrame              +--------------------+
| ARVideoCapture |  ───────────────▶  | CameraViewModel |
|  (ARSession)   |                     |  @StateObject   |
+----------------+                     +---------┬--------+
                                               FramePresentation
                                                   │  @Published
                                                   ▼
                                          +-------------------------+
                                          | SwiftUI UI (overlays)   |
                                          +-------------------------+
```

```
CameraViewModel delegates every frame to
FramePipelineCoordinator, which orchestrates:
   1. DetectionManager        – CoreML inference (YOLO-v8n)
   2. VisionTracker           – VNTrackObjectRequest updates
   3. AnchorPromoter          – Ray-cast + anchor registration
   4. VerifierService         – LLM verification (async HTTP)
   5. DetectionStateMachine   – Phase computation
   6. AnchorTrackingManager   – Anchor ⟷ screen projection
   7. NavigationManager       – Audio / haptic guidance

All shared mutable state lives in **CandidateStore**, a
`@Published` dictionary that the above services mutate.
```

---

## 2 Key Modules & Responsibilities

| Layer        | Module / Type                        | Responsibility                                                                                                                                                                                  |
| ------------ | ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Capture      | `ARVideoCapture`                     | Owns `ARSession`. Produces `ARFrame`s via `ARSessionDelegate` with an `autoreleasepool` to avoid retaining frames. Exposes `previewView` (`ARView`) for UI.                                     |
| View-Model   | `CameraViewModel`                    | `@StateObject` bound to SwiftUI. Implements `FrameProviderDelegate` and forwards frames to the pipeline. Publishes `boundingBoxes` & `currentFPS` for overlays.                                 |
| Coordination | `FramePipelineCoordinator`           | Pure-Swift orchestrator. One entry-point `process(frame:session:arView:...)` called each AR frame. Holds service instances and `DetectionStateMachine`. Emits a value-type `FramePresentation`. |
| Services     | `DetectionManager`                   | YOLO CoreML inference. Stateless.                                                                                                                                                               |
|              | `DefaultVisionTracker`               | Background queue Vision tracking. Updates candidate bounding boxes, prunes lost tracks.                                                                                                         |
|              | `DefaultAnchorPromoter`              | Ray-casts centre of each matched candidate to promote to `ARAnchor`.                                                                                                                            |
|              | `AnchorTrackingManager`              | Converts anchor positions to screen-space rect & distance, used for guidance.                                                                                                                   |
|              | `DefaultVerifierService`             | Sends cropped candidate images to an LLM backend; updates `matchStatus`.                                                                                                                        |
| Store        | `CandidateStore`                     | Single source of truth for candidates (`id → Candidate`). Thread-safe via `@Published` & main-thread writes.                                                                                    |
| Models       | `Candidate`                          | Contains tracking request, last bbox, optional anchor UUID, match status timestamps.                                                                                                            |
|              | `DetectionStateMachine`              | Stateless phase computer → `.searching`/`.verifying`/`.found`.                                                                                                                                  |
| Navigation   | `NavigationManager`                  | Emits audio / haptic cues guiding the user to the anchor returned by `AnchorTrackingManager`.                                                                                                   |
| Utilities    | `ImageUtilities`, `FPSManager`, etc. | Helper conversions & performance metrics.                                                                                                                                                       |

---

## 3 Per-Frame Pipeline (inside `FramePipelineCoordinator.process`)

1. **Detection** – `DetectionManager.detect` runs YOLO on the `CVPixelBuffer` (30 FPS). New detections spawn a `VNTrackObjectRequest` and a `Candidate` (deduped by IoU > 0.5).
2. **Vision Tracking** – `VisionTracker.tick` asynchronously updates all active `VNTrackObjectRequest`s and removes candidates whose trackers lost their object.
3. **Anchor Promotion** – For candidates whose `matchStatus == .matched` and `anchorId == nil`:
   - Convert Vision bbox → `viewRect` via `ImageUtilities`.
   - Call `arView.makeRaycastQuery` @ centre → first result → create `ARAnchor`.
   - Register with `AnchorTrackingManager`; write `anchorId` back into store.
4. **Verification** – `VerifierService.tick` crops each `CVPixelBuffer` once per frame, JPEG encodes, POSTs to LLM API, sets `.matched` / `.rejected`.
5. **State Machine Update** – Runs `DetectionStateMachine.update(snapshot:)` to derive global `DetectionPhase`.
6. **Presentation Assembly** – Converts each candidate to a coloured `BoundingBox` (colour legend below) and publishes `FramePresentation`.
7. **Navigation** – If phase is `.found`, `AnchorTrackingManager.navigateToAnchor` returns depth + rect → `NavigationManager.handle(.found, …)` which plays cues.

Colour legend: `yellow = new/unknown`, `blue = waiting LLM`, `purple = matched (no anchor)`, `green = matched + anchor`, `red = rejected`.

---

## 4 Threading & Memory Safety

- Only **ARVideoCapture** touches `ARSession` and creates `ARFrame`s.
- Heavy Vision / CoreML work happens on private serial queues; UI only sees published snapshots.
- `autoreleasepool` in `session(_:didUpdate:)` ensures captured frames are released promptly.
- `CandidateStore` mutations occur on main queue via `DispatchQueue.main.async {}` wrappers in each service.
- All structs (`Candidate`, `BoundingBox`, `FramePresentation`) are value types → no shared mutable state across threads.

---

## 5 Dependency Injection & Testability

- Each service conforms to a small protocol (`VisionTracker`, `AnchorPromoter`, `VerifierService`) and is injected via the `FramePipelineCoordinator` initializer.
- Non-AR unit tests can swap in mock implementations (e.g. `MockAnchorPromoter`) because core logic is ARKit-free.
- Pure-Swift files (`Candidate`, `DetectionStateMachine`, etc.) compile on macOS for CICD.

---

## 6 Extensibility Points

1. **Detector** – Swap in another CoreML model by implementing `ObjectDetector` protocol.
2. **Verifier** – Replace REST LLM API with on-device model; only `VerifierService` needs changes.
3. **Navigation** – `NavigationManager` centralises feedback; new haptics or UI prompts plug in here.
4. **Multi-object support** – `DetectionStateMachine` already supports multiple verifying candidates; navigation logic would need updates to choose a target.

---

## 7 Package / Framework Dependencies

- **ARKit** & **RealityKit** – capture & rendering.
- **Vision** – tracking.
- **CoreML** – YOLO detection.
- **Combine** – reactive state propagation.
- **SwiftUI** – UI layer.
- **UIKit** (minimal) – keyboard dismissal helper.

---

## 8 Build Targets & Schemes

| Target                | Description                        |
| --------------------- | ---------------------------------- |
| `thing-finder`        | Main iOS app (min iOS 17).         |
| `thing-finderTests`   | Unit tests for pure-Swift modules. |
| `thing-finderUITests` | UI launch & screenshot tests.      |

---

## 9 Known Issues / TODOs

- **Bounding box leak** – occasional stale boxes; likely candidate cleanup bug.
- **Anchor removal** – `FramePipelineCoordinator.clear()` should also remove anchors from session.
- **Ray-cast failures** – still investigating edge cases with `ARView.makeRaycastQuery` returning nil.

---

## 10 Getting Started

1. `pod install` (no pods yet) or open `thing-finder.xcodeproj` directly.
2. Set signing team in _Targets ▸ Signing & Capabilities_.
3. Run on a real device (ARKit required). First launch asks for camera permission.
4. On UI home, choose **Find** tab, enter object, tap **Start**.
