# CurbToCar

## Overview

**CurbToCar** is an assistive technology iOS application designed to help blind and visually impaired users identify and navigate to rideshare vehicles (Uber, Lyft) and paratransit services using real-time computer vision, AI verification, and audio-haptic feedback.

The app uses a sophisticated multi-stage pipeline combining YOLO object detection, Vision framework tracking, LLM-based verification (including TrafficEye API and OpenAI), OCR for license plate matching, and spatial audio navigation to guide users from curb to car.

## Mission

Enable blind users to independently locate their rideshare or paratransit vehicle in crowded pickup areas by:
- Detecting vehicles in real-time using the phone camera or Meta Ray-Ban smart glasses
- Verifying vehicle details (make, model, color, license plate) against ride information
- Providing continuous audio-haptic directional guidance to the correct vehicle
- Supporting multiple capture modes: iPhone camera, ARKit depth, and Meta glasses integration

## Key Features

### 🎯 Multi-Stage Detection Pipeline
1. **Object Detection**: YOLO11 CoreML models detect vehicles in real-time
2. **Vision Tracking**: Apple Vision framework tracks candidates across frames
3. **AI Verification**: Hybrid verification strategy using:
   - **TrafficEye API**: Fast multi-modal reasoning for vehicle attributes
   - **LLM Verification**: OpenAI GPT-4 Vision for detailed analysis
   - **OCR**: Vision framework text recognition for license plate matching
4. **Drift Repair**: Embedding-based re-association when tracking fails
5. **Navigation**: Spatial audio cues, haptic feedback, and directional speech

### 📱 Multiple Capture Sources
- **AVFoundation**: Standard iPhone camera
- **ARKit**: LiDAR depth sensing for accurate distance measurement
- **Meta Ray-Ban Glasses**: First-person POV via Meta Wearables DAT SDK
- **Video File Playback**: Testing and development mode

### 🔍 Intelligent Verification Strategies
- **Hybrid Mode** (default): TrafficEye → TwoStepVerifier escalation for cars
- **Paratransit Mode**: TrafficEye → AdvancedLLMVerifier for buses/vans with route numbers
- **LLM-Only Mode**: Direct OpenAI verification for custom use cases
- **TrafficEye-Only Mode**: Fast MMR-only verification without LLM fallback

### 🎧 Accessibility-First Navigation
- **Audio Beeps**: Beeps that increase frequency as user centers on target
- **Haptic Feedback**: Vibration patterns for distance and direction
- **Speech Announcements**: Status updates, vehicle descriptions, and turn-by-turn guidance
- **VoiceOver Compatible**: Full screen reader support

### 🧪 Robust Testing Infrastructure
- **MockDeviceKit**: Simulated Meta glasses for development without hardware
- **Unit Tests**: Comprehensive coverage of verification pipeline, tracking, and state management
- **Integration Tests**: End-to-end pipeline validation

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
Intelligent verifier selection with automatic escalation:
- Tries fast TrafficEye API first (3 attempts)
- Escalates to LLM verification after failures
- Cycles between verifiers based on strategy

#### `MetaGlassesManager`
Singleton managing Meta Ray-Ban glasses SDK lifecycle:
- Device registration and connection state
- Stream session management
- Mock device support for testing

#### `NavigationManager`
Frame-driven navigation with three coordinated controllers:
- **NavAnnouncer**: Status phrases and vehicle descriptions
- **DirectionSpeechController**: Left/right/straight guidance
- **HapticBeepController**: Distance-based beeps and haptics

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

### 2. Configure Meta Glasses (Optional)

For Meta Ray-Ban integration, add to `Info.plist`:
- URL scheme for Meta AI callbacks
- External accessory protocols
- Bluetooth permissions
- Background modes

See `AGENTS.md` for detailed Meta Wearables DAT SDK setup.

### 3. API Keys

Set environment variables or configure in Settings:
- `OPENAI_API_KEY`: For LLM verification
- TrafficEye API credentials (if using)

## Usage

1. **Launch App**: Grant camera and location permissions
2. **Enter Ride Details**: Vehicle description and license plate
3. **Start Detection**: Point camera at pickup area
4. **Follow Audio Cues**: Listen for directional guidance
5. **Verify Match**: App announces when correct vehicle is found

### Settings
- **Meta Glasses Mode**: Use Ray-Ban glasses instead of phone camera
- **ARKit Mode**: Enable depth sensing with LiDAR
- **Partial Navigation**: Allow navigation to partially verified vehicles
- **Speech Intervals**: Customize announcement frequency
- **Debug Overlay**: Show verification errors and pipeline state

## Testing

Run unit tests:
```bash
xcodebuild test -scheme thing-finder -destination 'platform=iOS Simulator,name=iPhone 15'
```

Use MockDeviceKit for Meta glasses testing without hardware.

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
