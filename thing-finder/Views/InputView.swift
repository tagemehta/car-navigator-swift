import AVFoundation
import SwiftUI

// Add this extension to dismiss the keyboard
extension InputView {
  func hideKeyboard() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }
}

struct InputView: View {
  @State private var searchMode: SearchMode = .uberFinder
  @State private var selectedClass: String = "car"
  @State private var description: String = ""
  @State private var isShowingCamera = false
  @FocusState private var isInputFocused: Bool

  // Vehicle classes for Uber Finder
  private let vehicleClasses = ["car", "truck", "bus"]

  // Full YOLO class list for Object Finder
  private let yoloClasses = [
    "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
    "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat", "dog",
    "horse", "backpack", "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard",
    "sports ball", "kite", "baseball bat", "baseball glove", "skateboard", "surfboard",
    "tennis racket", "bottle",
    "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich",
    "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch",
    "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse", "remote",
    "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator",
    "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush",
  ].sorted()

  var selectedClasses: [String] {
    searchMode == .uberFinder ? vehicleClasses : [selectedClass]
  }

  var body: some View {
    NavigationStack {
      Form {
        Section(
          header: Text(
            searchMode == .uberFinder ? "Vehicle Description" : "What are you looking for?")
        ) {
          if searchMode == .objectFinder {
            Picker("Object Class", selection: $selectedClass) {
              ForEach(yoloClasses, id: \.self) { className in
                Text(className.capitalized).tag(className)
              }
            }
            .pickerStyle(MenuPickerStyle())
          }

          TextField(
            searchMode == .uberFinder
              ? "Describe your ride (e.g., 'white Toyota Camry with license plate ABC123')"
              : "Describe it in detail (e.g., 'silver laptop with a white and green laptop sticker')",
            text: $description,
            axis: .vertical
          )
          .textFieldStyle(RoundedBorderTextFieldStyle())
          .lineLimit(3, reservesSpace: true)
          .focused($isInputFocused)
        }

        Section {
          Button(searchMode == .uberFinder ? "Find My Ride" : "Start Searching") {
            isShowingCamera = true
          }
          .frame(maxWidth: .infinity, alignment: .center)
          .buttonStyle(.borderedProminent)
          .disabled(
            searchMode == .uberFinder
              ? description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              : false)
        }
      }
      .navigationTitle("Find My Uber")
      .onAppear {
        // Dismiss keyboard when view appears
        hideKeyboard()
      }
      .onDisappear {
        // Dismiss keyboard when view disappears
        hideKeyboard()
      }
      .navigationDestination(isPresented: $isShowingCamera) {
        ContentView(
          description: description,
          searchMode: searchMode,
          targetClasses: selectedClasses
        )
      }
    }
    .simultaneousGesture(
      TapGesture().onEnded { isInputFocused = false }
    )

  }
}

#Preview {
  InputView()
}
