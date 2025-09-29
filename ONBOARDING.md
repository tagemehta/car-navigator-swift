# Thing Finder Onboarding Guide

## Project Overview

Thing Finder is a cutting-edge assistive technology application designed specifically for blind users. It empowers individuals by helping them identify and navigate to car services and newly introduced household objects. By integrating basic object detection with advanced large language models (LLMs), Thing Finder offers a new approach to personalized object discovery. The app leverages Apple's CoreML vision tools, SwiftUI, Lidar, and ARKit to deliver an enhanced user experience.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Repository Structure](#repository-structure)
3. [Core Architecture](#core-architecture)
4. [Key Components](#key-components)
5. [Object Detection Pipeline](#object-detection-pipeline)
6. [Verification System](#verification-system)
7. [Navigation System](#navigation-system)
8. [Testing Approach](#testing-approach)
9. [Documentation Standards](#documentation-standards)
10. [Future Development](#future-development)

## Getting Started

### Prerequisites

- Xcode 14+ (for Swift and iOS development)
- Python 3.8+ (for model installation scripts)
- Basic knowledge of SwiftUI and Vision frameworks

### Installation Steps

1. Clone the repository
2. Install required YOLO models using the provided Python script:

```python
from ultralytics import YOLO
from ultralytics.utils.downloads import zip_directory

def export_and_zip_yolo_models(
    model_types=("", "-seg", "-cls", "-pose", "-obb"),
    model_sizes=("n", "s", "m", "l", "x"),
):
    """Exports YOLO11 models to CoreML format and optionally zips the output packages."""
    for model_type in model_types:
        imgsz = [224, 224] if "cls" in model_type else [640, 384]  # default input image sizes
        nms = True if model_type == "" else False  # only apply NMS to Detect models
        for size in model_sizes:
            model_name = f"yolo11{size}{model_type}"
            model = YOLO(f"{model_name}.pt")
            model.export(format="coreml", int8=True, imgsz=imgsz, nms=nms)
            zip_directory(f"{model_name}.mlpackage").rename(f"{model_name}.mlpackage.zip")

# Execute with default parameters
export_and_zip_yolo_models()
```

3. Open the `thing-finder.xcodeproj` file in Xcode
4. Build and run the application on a compatible iOS device

## Repository Structure

```
thing-finder/
├── .build/              # Build artifacts
├── datasets/            # Training datasets
├── results/             # Evaluation results
├── scripts/             # Python scripts for model generation and evaluation
├── thing-finder/
│   ├── App/             # Main application entry point
│   ├── Assets.xcassets/ # Images and resources
│   ├── Core/            # Core data models and state machines
│   └── Docs/            # Project documentation
├── thing-finder.xcodeproj/ # Xcode project files
└── thing-finderTests/   # Unit tests
```

## Core Architecture

Thing Finder follows a frame-based pipeline architecture where camera frames are processed through a series of specialized services:

```
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

The system uses dependency injection through an `AppContainer` to wire up concrete implementations of service protocols, making it both testable and flexible.

## Key Components

### 1. Candidate Model

The `Candidate` struct is the central model representing an object being tracked. Key properties include:

- `id`: Unique identifier
- `trackingRequest`: Vision request that updates bounding box
- `embedding`: Feature print for object recognition
- `matchStatus`: Current verification state (.unknown, .waiting, .partial, .full, .rejected)
- `lastBoundingBox`: Position in image coordinates

### 2. CandidateStore

Thread-safe observable collection that maintains all active candidates. Provides synchronized mutation methods that can be safely called from any thread.

### 3. FramePipelineCoordinator

Orchestrates the per-frame processing flow:
1. Detection of objects
2. Tracking updates
3. Drift repair
4. Lifecycle maintenance
5. Verification
6. Phase updates
7. Navigation cues


## Object Detection Pipeline

The per-frame flow through the pipeline follows these steps:

1. **Detection** – Objects are detected in camera frames using CoreML/Vision
2. **Tracking** – Each candidate is tracked frame-to-frame
3. **Drift repair** – Drifting bounding boxes are re-associated with fresh detections
4. **Lifecycle maintenance** – New candidates are created, stale ones removed
5. **Verification** – Candidates are validated using LLMs or classifiers
6. **Phase update** – Overall app state is derived from candidates
7. **Navigation cues** – User receives appropriate feedback
8. **UI update** – SwiftUI overlay renders the current state

## Verification System

Thing Finder implements a modular verification strategy pattern with three main approaches:

1. **TrafficEye** – Fast primary verification
2. **LLM** – More accurate but slower verification
3. **Advanced LLM** – Last-resort verification for difficult cases

The system dynamically selects verification strategies based on:
- Candidate view angle (front, side, rear)
- Previous verification attempts
- Priority calculation

### License Plate Verification

For rideshare applications, the system combines object detection with OCR-based license plate verification:

1. LLM verification confirms vehicle make/model/color
2. OCR attempts to read license plates within the bounding box
3. Matches are classified as:
   - **Full match**: Vehicle and license plate confirmed
   - **Partial match**: Vehicle confirmed but plate not visible
   - **Rejected**: Wrong vehicle or plate

## Navigation System

The navigation system provides directional feedback to users through:

1. **NavAnnouncer** – Decides what phrases to speak
2. **DirectionSpeechController** – Manages directional guidance
3. **HapticBeepController** – Controls haptic and audio feedback

The system follows a tick-based update model that processes candidate state changes and emits appropriate navigation cues.

## Testing Approach

Thing Finder uses XCTest for unit testing key components:

1. **Service Tests** – Validate individual services like CandidateLifecycleService
2. **Strategy Tests** – Verify verification strategy selection and execution
3. **Pipeline Tests** – Test the full frame processing pipeline
4. **Mock Objects** – Used to isolate components for testing

Test files are located in the `thing-finderTests` directory.

## Documentation Standards

The project follows a strict documentation standard using DocC-compatible markdown:

### Function Documentation Template

```swift
/// A brief description of what the function does.
///
/// A more detailed discussion about the function's behavior,
/// implementation details, or usage notes if needed.
///
/// - Parameters:
///   - paramName: Description of the parameter
///   - anotherParam: Description of another parameter
/// - Returns: Description of what is returned
/// - Throws: Description of errors that can be thrown
/// - Note: Any additional information
/// - Warning: Critical information about potential issues
func functionName(paramName: ParamType, anotherParam: AnotherType) throws -> ReturnType {
    // Implementation
}
```

### Class Documentation Template

```swift
/// A brief description of the type.
///
/// A more detailed discussion about the type's purpose,
/// behavior, or implementation details if needed.
///
/// ## Topics
///
/// ### Essentials
/// - ``someProperty``
/// - ``someMethod()``
///
/// ### Advanced Usage
/// - ``anotherMethod()``
///
/// - Note: Any additional information
public class ClassName {
    // Implementation
}
```

## Future Development

Several enhancements are planned or in progress:

1. **Navigation Manager Refactoring** – Splitting the monolithic navigation manager into focused components
2. **Verification Strategy Improvements** – Adding more verification methods
3. **AR Mode** – Implementing AR anchors for more stable tracking
4. **Advanced Feedback** – Enhancing haptic and audio cues for better navigation

## Engineering Principles

The project follows three main engineering principles:

1. **Safe from Bugs** – Correct today and in the future
2. **Easy to Understand** – Clear communication with future developers
3. **Ready for Change** – Designed to accommodate change without rewriting

## Contact

For any questions or support, email mitassistivetechnologyclub@gmail.com
