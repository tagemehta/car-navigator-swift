// MARK: - App Entry
import MWDATCore
import SwiftUI

@main
struct ThingFinderApp: App {
  @AppStorage("app_language") private var appLanguageRaw: String = SupportedLanguage.system.rawValue
  @StateObject private var sharedSettings = Settings()

  private var appLanguage: SupportedLanguage {
    SupportedLanguage(rawValue: appLanguageRaw) ?? .system
  }

  init() {
    let language =
      SupportedLanguage(
        rawValue: UserDefaults.standard.string(forKey: "app_language")
          ?? SupportedLanguage.system.rawValue) ?? .system
    LanguageManager.applyLanguage(language)
  @StateObject private var glassesEnvironment = MetaGlassesEnvironment.shared

  init() {
    // Configure Wearables SDK on launch (matches Meta sample pattern)
    do {
      try Wearables.configure()
    } catch {
      print("[ThingFinderApp] Failed to configure Wearables SDK: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup {
      MainTabView()
        .environmentObject(sharedSettings)
        .environment(\.locale, LanguageManager.locale(for: appLanguage))
        .onChange(of: appLanguageRaw) { _, newValue in
          LanguageManager.applyLanguage(SupportedLanguage(rawValue: newValue) ?? .system)
        }
        .environmentObject(glassesEnvironment.wearablesViewModel)
        .environmentObject(glassesEnvironment.streamSessionViewModel)
        .onOpenURL { url in
          // Handle callback from Meta AI app after registration/permission flows
          // Filter for DAT SDK URLs using metaWearablesAction param (matches Meta sample)
          guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
          else { return }
          Task {
            do {
              _ = try await Wearables.shared.handleUrl(url)
            } catch let error as RegistrationError {
              print("[ThingFinderApp] Registration error: \(error.description)")
            } catch {
              print("[ThingFinderApp] Failed to handle URL: \(error)")
            }
          }
        }
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
          "This app is an experimental product. While we make every effort to provide accurate results, we cannot guarantee accuracy. You should use discretion and secondary methods to verify information related to your car and services. This app is not intended to replace any mobility aid."
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
  @EnvironmentObject var sharedSettings: Settings

  var body: some View {
    TabView {
      NavigationStack {
        InputView()
      }
      .tabItem {
        Label("Find", systemImage: "magnifyingglass")
      }

      NavigationStack {
        SettingsView(settings: sharedSettings)
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
