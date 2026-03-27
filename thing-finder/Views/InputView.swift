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
  @AppStorage("InputView.isParatransitMode") private var isParatransitMode = false
  @State private var shortcutNavigationState = ShortcutNavigationState.shared

  private var historyItems: [SearchHistoryItem] {
    (try? JSONDecoder().decode([SearchHistoryItem].self, from: Data(searchHistoryData.utf8))) ?? []
  }

  private var favoriteItems: [SearchHistoryItem] {
    historyItems.filter { $0.isFavorite }
  }

  private var recentItems: [SearchHistoryItem] {
    historyItems.filter { !$0.isFavorite }.prefix(5).map { $0 }
  }

  private func saveToHistory(_ entry: String, mode: SearchMode, paratransit: Bool) {
    let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    var items = historyItems
    if let existingIndex = items.firstIndex(where: { $0.description == trimmed }) {
      let existingItem = items[existingIndex]
      items.remove(at: existingIndex)
      let updatedItem = SearchHistoryItem(
        id: existingItem.id,
        description: trimmed, mode: mode, isParatransitMode: paratransit,
        isFavorite: existingItem.isFavorite)
      items.insert(updatedItem, at: 0)
    } else {
      let newItem = SearchHistoryItem(
        description: trimmed, mode: mode, isParatransitMode: paratransit)
      items.insert(newItem, at: 0)
    }

    let nonFavorites = items.filter { !$0.isFavorite }
    let favorites = items.filter { $0.isFavorite }
    let trimmedNonFavorites = nonFavorites.count > 5 ? Array(nonFavorites.prefix(5)) : nonFavorites
    items = favorites + trimmedNonFavorites

    if let data = try? JSONEncoder().encode(items),
      let json = String(data: data, encoding: .utf8)
    {
      searchHistoryData = json
    }
  }

  private func toggleFavorite(_ item: SearchHistoryItem) {
    var items = historyItems
    if let index = items.firstIndex(where: { $0.id == item.id }) {
      var updatedItem = items[index]
      updatedItem.isFavorite.toggle()
      items[index] = updatedItem

      if let data = try? JSONEncoder().encode(items),
        let json = String(data: data, encoding: .utf8)
      {
        searchHistoryData = json
      }
    }
  }

  private func deleteItem(_ item: SearchHistoryItem) {
    var items = historyItems
    items.removeAll { $0.id == item.id }

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
  @State private var showPasteAlert = false
  @State private var pasteAlertMessage = ""
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
      ? "Describe your ride (e.g., white Toyota Camry with license plate ABC123)"
      : "Describe it in detail (e.g., silver laptop with a white and green laptop sticker)"
  }

  private func checkForShortcutNavigation() {
    if let carDesc = shortcutNavigationState.consumePendingDescription() {
      description = carDesc
      searchMode = .uberFinder
      showPlaceholder = false
      isParatransitMode = false
      saveToHistory(carDesc, mode: .uberFinder, paratransit: false)
      isShowingCamera = true
    }
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

          Button {
            if let clipboardText = UIPasteboard.general.string, !clipboardText.isEmpty {
              description = clipboardText
              showPlaceholder = false
            } else {
              pasteAlertMessage = "Clipboard is empty"
              showPasteAlert = true
            }
          } label: {
            HStack {
              Image(systemName: "doc.on.clipboard")
              Text("Paste from Clipboard")
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .accessibilityLabel("Paste from clipboard")
          .accessibilityHint("Pastes text from clipboard into the description field")

          if searchMode == .uberFinder {
            Toggle(isOn: $isParatransitMode) {
              VStack(alignment: .leading, spacing: 2) {
                Text("Transit Mode")
                Text("For buses with route numbers and logos")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
            .accessibilityLabel("Transit mode")
            .accessibilityHint(
              "Enable for public transit buses. Matches by route number and agency logo instead of make and model."
            )
          }
        }

        Section {
          Button(searchMode == .uberFinder ? "Find My Ride" : "Start Searching") {
            saveToHistory(description, mode: searchMode, paratransit: isParatransitMode)
            isShowingCamera = true
          }
          .frame(maxWidth: .infinity, alignment: .center)
          .buttonStyle(.borderedProminent)
          .disabled(
            searchMode == .uberFinder
              ? description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              : false)
        }

        if !favoriteItems.isEmpty {
          Section(
            header: Text("Favorites")
              .font(.headline)
          ) {
            ForEach(favoriteItems, id: \.id) { item in
              HStack(spacing: 12) {
                Button {
                  description = item.description
                  searchMode = item.mode
                  isParatransitMode = item.isParatransitMode
                  showPlaceholder = false
                  saveToHistory(
                    item.description, mode: item.mode, paratransit: item.isParatransitMode)
                  isShowingCamera = true
                } label: {
                  HStack {
                    Image(systemName: "star.fill")
                      .foregroundColor(.yellow)
                      .accessibilityHidden(true)
                    Image(systemName: item.mode == .uberFinder ? "car.fill" : "magnifyingglass")
                      .foregroundColor(.secondary)
                      .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                      Text(item.description)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(.primary)
                      if item.mode == .uberFinder && item.isParatransitMode {
                        Text("Transit Mode")
                          .font(.caption2)
                          .foregroundColor(.secondary)
                      }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                  }
                }
                .accessibilityLabel(
                  "Favorite: \(item.description), \(item.mode.description)\(item.isParatransitMode ? ", Transit mode" : "")"
                )
                .accessibilityHint("Double tap to search with this description")

                Button {
                  toggleFavorite(item)
                } label: {
                  Image(systemName: "star.slash")
                    .font(.body)
                    .foregroundColor(.orange)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove from favorites")
                .accessibilityHint("Moves this search back to recent searches")

                Button(role: .destructive) {
                  deleteItem(item)
                } label: {
                  Image(systemName: "trash")
                    .font(.body)
                    .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete favorite")
                .accessibilityHint("Removes this search from favorites")
              }
            }
          }
        }

        if !recentItems.isEmpty {
          Section(
            header: HStack {
              Text("Recent Searches")
                .font(.headline)
              Spacer()
              Button("Clear All") {
                let favorites = historyItems.filter { $0.isFavorite }
                if let data = try? JSONEncoder().encode(favorites),
                  let json = String(data: data, encoding: .utf8)
                {
                  searchHistoryData = json
                }
              }
              .font(.subheadline)
              .foregroundColor(.blue)
              .accessibilityLabel("Clear all recent searches")
              .accessibilityHint("Removes all non-favorite searches from history")
            }
          ) {
            ForEach(recentItems, id: \.id) { item in
              HStack(spacing: 12) {
                Button {
                  description = item.description
                  searchMode = item.mode
                  isParatransitMode = item.isParatransitMode
                  showPlaceholder = false
                  saveToHistory(
                    item.description, mode: item.mode, paratransit: item.isParatransitMode)
                  isShowingCamera = true
                } label: {
                  HStack {
                    Image(systemName: item.mode == .uberFinder ? "car.fill" : "magnifyingglass")
                      .foregroundColor(.secondary)
                      .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                      Text(item.description)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(.primary)
                      if item.mode == .uberFinder && item.isParatransitMode {
                        Text("Transit Mode")
                          .font(.caption2)
                          .foregroundColor(.secondary)
                      }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                  }
                }
                .accessibilityLabel(
                  "Recent search: \(item.description), \(item.mode.description)\(item.isParatransitMode ? ", Transit mode" : "")"
                )
                .accessibilityHint("Double tap to search with this description")

                Button {
                  toggleFavorite(item)
                } label: {
                  Image(systemName: "star")
                    .font(.body)
                    .foregroundColor(.yellow)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add to favorites")
                .accessibilityHint("Saves this search to favorites")

                Button(role: .destructive) {
                  deleteItem(item)
                } label: {
                  Image(systemName: "trash")
                    .font(.body)
                    .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete search")
                .accessibilityHint("Removes this search from history")
              }
            }
          }
        }
      }
      .scrollDismissesKeyboard(.immediately)
      .navigationTitle("CurbToCar")
      .alert(pasteAlertMessage, isPresented: $showPasteAlert) {
        Button("OK", role: .cancel) {}
      }
      .onAppear {
        hideKeyboard()
        checkForShortcutNavigation()
      }
      .onChange(of: shortcutNavigationState.pendingCarDescription) { _, newValue in
        if newValue != nil {
          checkForShortcutNavigation()
        }
      }
      .onDisappear {
        hideKeyboard()
      }
      .navigationDestination(isPresented: $isShowingCamera) {
        ContentView(
          description: description,
          searchMode: searchMode,
          targetClasses: selectedClasses,
          isParatransitMode: isParatransitMode
        )
      }
    }
  }
}

#Preview {
  InputView()
}
