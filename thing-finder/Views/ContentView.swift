import Combine
import SwiftUI

struct ContentView: View {
  @State private var isCameraRunning = true
  /// Changing this key forces SwiftUI to recreate `DetectorContainer`,
  /// which in turn rebuilds the `CameraViewModel` and fully resets the pipeline.
  @State private var detectorKey = UUID()
  let description: String
  let searchMode: SearchMode
  let targetClasses: [String]
  private let settings: Settings

  init(
    description: String,
    searchMode: SearchMode,
    targetClasses: [String]
  ) {
    self.description = description
    self.searchMode = searchMode
    self.targetClasses = targetClasses
    let settings = Settings()
    self.settings = settings
  }

  var title: String {
    searchMode == .uberFinder ? "Finding Your Ride" : "Finding: \(targetClasses[0].capitalized)"
  }

  var body: some View {
    VStack {
      ZStack {
        DetectorContainer(
          isRunning: $isCameraRunning,
          description: description,
          targetClasses: targetClasses,
          settings: settings
        )
        .id(detectorKey)

        VStack {
          Spacer()
          HStack {
            // Pause / Resume Toggle
            Button(action: {
              if isCameraRunning {
                AudioControl.pauseAll()
              }
              isCameraRunning.toggle()
            }) {
              Text(isCameraRunning ? "Pause" : "Resume")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .padding()
                .background(isCameraRunning ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
              // .clipShape(Circle())
            }
            // Reset Detection Pipeline
            Button(action: {
              // 1. Stop current capture
              AudioControl.pauseAll()
              isCameraRunning = false
              // 2. Allow AVFoundation to release the camera.
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                // 3. Recreate the container (new pipeline)
                detectorKey = UUID()
                // 4. Start capture after the new view has appeared
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                  isCameraRunning = true
                }
              }
            }) {
              Text("Reset")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .padding()
                .background(Color.blue.opacity(0.8))
              // .clipShape(Circle())
            }

          }
          .padding(.vertical)
        }
      }

    }
    .navigationBarTitle(title, displayMode: .inline)
    .onRotate { _ in
      // Orientation changes are handled inside DetectorContainer
    }
  }
}

#Preview {
  NavigationView {
    ContentView(
      description: "wearing a red shirt", searchMode: .objectFinder, targetClasses: ["person"])
  }
}
