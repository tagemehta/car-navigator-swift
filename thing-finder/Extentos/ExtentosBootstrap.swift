// EXTENTOS-GENERATED — do not edit manually. Regenerate via generateConnectionModule.
import Foundation
import SwiftUI
import os
import GlassesCore

/// Singleton wrapper that instantiates the Extentos SDK and opens the
/// transport when the app launches. Reference `ExtentosBootstrap.shared.glasses`
/// from your root view / Handler classes to subscribe to SDK primitives.
@MainActor
final class ExtentosBootstrap: ObservableObject {
    static let shared = ExtentosBootstrap()

    let glasses: ExtentosGlasses
    let sceneObserver: ExtentosSceneObserver

    private static let log = Logger(subsystem: "com.mitat.thing-finder", category: "Extentos")

    private init() {
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        let config = ExtentosConfig(
            appId: Bundle.main.infoDictionary?["EXTENTOS_APP_ID"] as? String,
            accountId: Bundle.main.infoDictionary?["EXTENTOS_ACCOUNT_ID"] as? String,
            transport: .auto,
            debug: isDebugBuild,
            telemetryConsent: true,
            usedCapabilities: [.camera]
        )
        glasses = Extentos.create(config: config)
        sceneObserver = ExtentosSceneObserver(glasses: glasses)

        Task.detached { [glasses] in
            await glasses.connect()
        }
    }
}
