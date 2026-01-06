// MARK: - App Entry
import SwiftUI

@main
struct ThingFinderApp: App {
  var body: some Scene {
    WindowGroup {
      MainTabView()
      //      ContentView(description: "always return false", searchMode: .objectFinder, targetClasses: ["laptop"])
    }
  }
}

private struct ExperimentalDisclaimerView: View {
  @Binding var hasAcceptedExperimentalDisclaimer: Bool

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 16) {
        Text("Experimental Product")
          .font(.title)
          .bold()

        Text(
          "This app is an experimental product. While we make every effort to provide accurate results, we cannot guarantee accuracy. You should use discretion and secondary methods to verify information related to your car and services."
        )
        .font(.body)

        Text("By continuing, you acknowledge and accept the above.")
          .font(.body)
          .bold()

        Spacer()

        Button {
          hasAcceptedExperimentalDisclaimer = true
        } label: {
          Text("I Agree / Continue")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
      }
      .padding()
      .navigationBarTitleDisplayMode(.inline)
    }
    .interactiveDismissDisabled(true)
  }
}

struct MainTabView: View {
  @AppStorage("hasAcceptedExperimentalDisclaimer") private var hasAcceptedExperimentalDisclaimer:
    Bool = false

  var body: some View {
    TabView {
      NavigationStack {
        InputView()
      }
      .tabItem {
        Label("Find", systemImage: "magnifyingglass")
      }

      NavigationStack {
        SettingsView(settings: Settings())
      }
      .tabItem {
        Label("Settings", systemImage: "gear")
      }

      // NavigationStack {
      //     CompassView()
      // }
      // .tabItem {
      //   Label("Compass", systemImage: "square.and.arrow.up")
      // }

    }
    .fullScreenCover(
      isPresented: Binding(
        get: { !hasAcceptedExperimentalDisclaimer },
        set: { _ in }
      )
    ) {
      ExperimentalDisclaimerView(
        hasAcceptedExperimentalDisclaimer: $hasAcceptedExperimentalDisclaimer
      )
    }
  }
}
