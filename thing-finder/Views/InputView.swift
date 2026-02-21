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

  @AppStorage("InputView.searchHistory") private var searchHistoryData: String = "[]"

  private var historyItems: [String] {
    (try? JSONDecoder().decode([String].self, from: Data(searchHistoryData.utf8))) ?? []
  }

  private func saveToHistory(_ entry: String) {
    let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    var items = historyItems.filter { $0 != trimmed }
    items.insert(trimmed, at: 0)
    if items.count > 5 { items = Array(items.prefix(5)) }
    if let data = try? JSONEncoder().encode(items),
      let json = String(data: data, encoding: .utf8)
    {
      searchHistoryData = json
    }
  }
  @State private var searchMode: SearchMode = .uberFinder
  @State private var selectedClass: String = "car"
  @State private var description: String = ""
  @State private var isShowingCamera = false
  @State private var showPlaceholder = true
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

  var placeholderText: String {
    searchMode == .uberFinder
      ? "Describe your ride (e.g., 'white Toyota Camry with license plate ABC123')"
      : "Describe it in detail (e.g., 'silver laptop with a white and green laptop sticker')"
  }

  var body: some View {
    NavigationStack {
      Form {
        Section(
          header: HStack {
            Text(searchMode == .uberFinder ? "Vehicle Description" : "What are you looking for?")
              .font(.headline)

            Spacer()

            if !description.isEmpty {
              Button("Clear") {
                description = ""
                showPlaceholder = true
              }
              .font(.subheadline)
              .foregroundColor(.blue)
            }
          }
        ) {
          if searchMode == .objectFinder {
            Picker("Object Class", selection: $selectedClass) {
              ForEach(yoloClasses, id: \.self) { className in
                Text(className.capitalized).tag(className)
              }
            }
            .pickerStyle(MenuPickerStyle())
          }

          ZStack(alignment: .topLeading) {
            TextField("", text: $description, axis: .vertical)
              .textFieldStyle(RoundedBorderTextFieldStyle())
              .lineLimit(2, reservesSpace: true)
              .focused($isInputFocused)
              .onChange(of: isInputFocused) { oldValue, newValue in
                if newValue {
                  showPlaceholder = false
                } else {
                  showPlaceholder = description.isEmpty
                }
              }

            if showPlaceholder {
              Text(placeholderText)
                .foregroundColor(.gray)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .onTapGesture {
                  isInputFocused = true
                }
            }
          }
          .frame(minHeight: 80)
        }

        Section {
          Button(searchMode == .uberFinder ? "Find My Ride" : "Start Searching") {
            saveToHistory(description)
            isShowingCamera = true
          }
          .frame(maxWidth: .infinity, alignment: .center)
          .buttonStyle(.borderedProminent)
          .disabled(
            searchMode == .uberFinder
              ? description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              : false)
        }

        if !historyItems.isEmpty {
          Section(
            header: HStack {
              Text("Recent Searches")
                .font(.headline)
              Spacer()
              Button("Clear All") {
                searchHistoryData = "[]"
              }
              .font(.subheadline)
              .foregroundColor(.blue)
            }
          ) {
            ForEach(historyItems.prefix(5), id: \.self) { item in
              Button {
                description = item
                showPlaceholder = false
                saveToHistory(item)
                isShowingCamera = true
              } label: {
                HStack {
                  Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                  Text(item)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
              }
              .accessibilityLabel("Recent search: \(item)")
              .accessibilityHint("Double tap to search with this description")
            }
          }
        }
      }
      .scrollDismissesKeyboard(.immediately)
      .navigationTitle("Find My Car")
      .onAppear {
        hideKeyboard()
      }
      .onDisappear {
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
  }
}

#Preview {
  InputView()
}
