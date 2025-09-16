import SwiftUI

struct ContentView: View {
  @State private var isCameraRunning = true
  let description: String
  let searchMode: SearchMode
  let targetClasses: [String]
  private let settings: Settings
  @StateObject private var detectionModel: CameraViewModel

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
    _detectionModel = StateObject(
      wrappedValue: CameraViewModel(
        targetClasses: targetClasses,
        targetTextDescription: description,
        settings: settings
      )
    )
  }

  var title: String {
    searchMode == .uberFinder ? "Finding Your Ride" : "Finding: \(targetClasses[0].capitalized)"
  }

  var body: some View {
    VStack {
      ZStack {
        CameraPreviewWrapper(
          isRunning: $isCameraRunning,
          delegate: detectionModel, source: settings.useARMode ? .arKit : .avFoundation
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        BoundingBoxViewOverlay(
          boxes: $detectionModel.boundingBoxes
        )

        // FPS Display
        VStack {
          HStack {
            Spacer()
            Text(String(format: "%.1f FPS", detectionModel.currentFPS))
              .font(.system(size: 14, weight: .medium, design: .monospaced))
              .foregroundColor(.white)
              .padding(8)
              .background(Color.black.opacity(0.5))
              .cornerRadius(8)
              .padding()
          }
          Spacer()
        }
      }
    }
    .navigationBarTitle(title, displayMode: .inline)
    .onRotate { newOrientation in
      detectionModel.handleOrientationChange()
    }
    .onAppear {
      detectionModel.handleOrientationChange()
    }
  }
}

#Preview {
  NavigationView {
    ContentView(
      description: "wearing a red shirt", searchMode: .objectFinder, targetClasses: ["person"])
  }
}
