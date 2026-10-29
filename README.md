# CurbToCar

## Overview

**CurbToCar** is an assistive technology iOS application designed to help blind and visually impaired users identify and navigate to rideshare vehicles (Uber, Lyft) and paratransit services using real-time computer vision, AI verification, and audio-haptic feedback.

The app uses a sophisticated multi-stage pipeline combining YOLO object detection, Vision framework tracking, LLM-based verification (including TrafficEye API and OpenAI), OCR for license plate matching, and spatial audio navigation to guide users from curb to car.

## Mission

Enable blind users to independently locate their rideshare or paratransit vehicle in crowded pickup areas by:
- Detecting vehicles in real time using the phone camera (Meta Ray-Ban glasses support is implemented but currently disabled)
- Verifying vehicle details (make, model, color, license plate) against ride information
- Providing continuous audio-haptic directional guidance to the correct vehicle
- Supporting multiple capture modes: iPhone camera (with LiDAR depth when available), ARKit depth, and simulator video playback

New contributors and coding agents: start with `ONBOARDING.md` (architecture) and `AGENTS.md` (agent setup for Devin, Claude Code, and Codex).

## Key Features

### 🎯 Multi-Stage Detection Pipeline
1. **Object Detection**: YOLO11n CoreML model detects vehicles in real time
2. **Vision Tracking**: Apple Vision framework tracks candidates across frames
3. **AI Verification**: Hybrid verification strategy using:
   - **TrafficEye API**: Make/model/color recognition, compared with the rider's description by an OpenAI model
   - **LLM Verification**: OpenAI vision model (`gpt-6-luna`; migration from `gpt-4.1-mini` in progress)
   - **OCR**: Vision framework text recognition for license plate matching
4. **Drift Repair**: Embedding-based re-association when tracking fails
5. **Navigation**: Directional and distance speech, centering beeps, and distance haptics

### 📱 Multiple Capture Sources
- **AVFoundation**: Standard iPhone camera (uses the LiDAR depth camera when available)
- **ARKit**: Scene depth / raycast distance measurement
- **Meta Ray-Ban Glasses**: First-person POV via Meta Wearables DAT SDK (implemented, currently disabled)
- **Video File Playback**: Used automatically on the simulator

### 🔍 Intelligent Verification Strategies
- **Hybrid Mode** (car search): TrafficEye first; any non-match escalates to the two-step LLM verifier
- **Paratransit Mode**: AdvancedLLMVerifier (single image call that reads route numbers and logos)
- **LLM-Only / TrafficEye-Only**: available in `VerificationConfig`, not currently used by the app
- **License plates**: exact TrafficEye plate match, or on-device OCR with fuzzy (Levenshtein) matching

### 🎧 Accessibility-First Navigation
- **Audio Beeps**: Beeps that increase frequency as user centers on target
- **Haptic Feedback**: Pulses that speed up with distance, a tap when a car is first detected, and success/connectivity haptics
- **Speech Announcements**: Status updates, direction changes, distance milestones (locale units), and network warnings
- **Siri Shortcuts**: "Find my car with CurbToCar" and "Find my paratransit with CurbToCar"
- **VoiceOver Compatible**: Full screen reader support, Magic Tap to pause
- **Languages**: English and Spanish

### 🧪 Robust Testing Infrastructure
- **Unit Tests**: 28 XCTest classes covering core state, pipeline services, verification, navigation, and utilities (see `thing-finder/Docs/TestingPlan.md`)
- **Mocks**: A fake for every pipeline protocol in `thing-finderTests/Mocks/`
- **Verifier evals**: Real-image Python evals in `evals/realworld/`

## Architecture

### Core Components

#### `FramePipelineCoordinator`
Central orchestrator that processes each video frame through the detection pipeline:
```
Frame → Detection → Tracking → Drift Repair → Verification → Navigation → UI
```

#### `CandidateStore`
Thread-safe observable store managing all detected vehicle candidates with their verification status:
- `unknown` → `waiting` → `partial` → `full` (verified)
- `rejected` (wrong vehicle) or `lost` (tracking failed)

#### `VerifierSelector`
Verifier selection with automatic escalation:
- Hybrid: TrafficEye first, escalating to the two-step LLM verifier after a failure
- Paratransit: always the advanced LLM verifier
- 10 s timeout per request; errors become retryable outcomes

#### `MetaGlassesManager` (disabled)
Meta Ray-Ban glasses SDK lifecycle (registration, streaming, mock devices). The code is commented out and the SDK is removed from the build. See `ONBOARDING.md` for the re-enable checklist.

#### `FrameNavigationManager`
Frame-driven navigation with coordinated controllers:
- **NetworkFeedbackController**: Offline / weak-signal warnings
- **PreMatchFeedbackController**: "Searching", detection haptic, heartbeat, rejections
- **NavAnnouncer**: Match / lost transitions
- **DirectionSpeechController**: Left/right/ahead on change
- **DistanceMilestoneController**: 10/5/2/1 m milestones
- **HapticBeepController**: Centering beeps and distance haptics

### Data Flow

```
Camera/Glasses Frame
    ↓
ObjectDetector (YOLO11)
    ↓
VisionTracker (VNSequenceRequestHandler)
    ↓
DriftRepairService (embedding-based re-association)
    ↓
VerifierService (TrafficEye/LLM/OCR)
    ↓
DetectionStateMachine (phase transitions)
    ↓
NavigationManager (audio/haptic feedback)
    ↓
SwiftUI (bounding boxes, FPS, debug overlay)
```

## Installation Instructions

### Prerequisites
- Xcode 15.0+
- iOS 16.0+ deployment target
- Swift Package Manager
- Python 3.8+ (for YOLO model export)

### 1. Install YOLO Models

Export YOLO11 models to CoreML format:

```python
from ultralytics import YOLO
from ultralytics.utils.downloads import zip_directory

def export_and_zip_yolo_models(
    model_types=("", "-seg", "-cls", "-pose", "-obb"),
    model_sizes=("n", "s", "m", "l", "x"),
):
    """Exports YOLO11 models to CoreML format and optionally zips the output packages."""
    for model_type in model_types:
        imgsz = [224, 224] if "cls" in model_type else [640, 384]
        nms = True if model_type == "" else False
        for size in model_sizes:
            model_name = f"yolo11{size}{model_type}"
            model = YOLO(f"{model_name}.pt")
            model.export(format="coreml", int8=True, imgsz=imgsz, nms=nms)
            zip_directory(f"{model_name}.mlpackage").rename(f"{model_name}.mlpackage.zip")

export_and_zip_yolo_models()
```

Place the exported `yolo11n.mlpackage` in `thing-finder/CVModels/` (gitignored).

### 2. API Keys

The app does not ship provider keys. Verifier calls go through the Cloudflare Worker in `proxy/`, which holds the OpenAI and TrafficEye keys as Worker secrets (`OPENAI_KEY`, `TRAFFICEYE_KEY`, `APP_TOKEN`).

Create `thing-finder/Secrets.xcconfig` (gitignored) defining:
- `PROXY_BASE_URL`: the Worker URL. Write `//` as `/$()/` because xcconfig treats `//` as a comment, e.g. `https:/$()/curbtocar-proxy.curbtocar.workers.dev`
- `PROXY_APP_TOKEN`: must match the Worker's `APP_TOKEN` secret

`Info.plist` expands these build settings, and `APIProxy` reads them at runtime. Never commit this file. The local scripts and evals can still read `OPENAI_API` / `TRAFFICEYE_API_KEY` from this file, but the app no longer uses them.

### 3. Meta Glasses (currently disabled)

Glasses support is commented out and the DAT SDK is not in the build. To re-enable it, follow the checklist in `ONBOARDING.md` ("Meta glasses (disabled)"). SDK setup details are in `.agents/skills/meta-wearables-dat/`.

## Usage

1. **Launch App**: Accept the experimental disclaimer; grant camera and location permissions
2. **Enter Ride Details**: Vehicle description and license plate (or toggle Paratransit), or use Siri
3. **Start Detection**: Point camera at pickup area (requires a network connection when a description is given)
4. **Follow Audio Cues**: Listen for directional guidance
5. **Verify Match**: App announces when correct vehicle is found

### Settings
- **Language**: System, English, or Spanish
- **Navigation**: Beeps, speech, haptics, partial navigation, rejection/waiting announcements, speech rate
- **Display**: Show favorites and recent searches
- **Advanced**: Direction repeat interval, beep tuning, debug overlay

## Testing

Run unit tests (pick any available iPhone simulator):
```bash
xcodebuild test -project thing-finder.xcodeproj -scheme thing-finder -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

See `.agents/skills/ios-build-test/SKILL.md` for focused test runs and `thing-finder/Docs/TestingPlan.md` for coverage.

## Technical Highlights

- **Thread-Safe Architecture**: Main-queue synchronized CandidateStore with value-type snapshots
- **Combine Publishers**: Reactive pipeline with proper timeout error handling
- **Dependency Injection**: AppContainer composition root for testability
- **Race Condition Fixes**: Careful scheduler management in verification pipeline
- **Memory Efficient**: Frame processing on background queues, UI updates on main thread
- **Accessibility**: VoiceOver, Dynamic Type, Magic Tap gesture support

## Contact

Email us at assistivetech@mit.edu

## License

See LICENSE file for details
