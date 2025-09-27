import Foundation
import Combine
import SwiftUI

/// A utility class for publishing debug messages to the debug overlay from anywhere in the app
public final class DebugPublisher {
    /// Shared instance for easy access
    public static let shared = DebugPublisher()
    
    /// Publisher for debug messages
    private let messageSubject = PassthroughSubject<(String, DebugOverlayModel.MessageType), Never>()
    
    /// Publisher for debug messages
    public var messagePublisher: AnyPublisher<(String, DebugOverlayModel.MessageType), Never> {
        messageSubject.eraseToAnyPublisher()
    }
    
    /// Reference to settings to check if debug is enabled
    private let settings = Settings()
    
    private init() {}
    
    /// Publish an error message to the debug overlay
    /// - Parameter message: The error message text
    public func error(_ message: String) {
        guard settings.debugOverlayEnabled else { return }
        DispatchQueue.main.async { self.messageSubject.send((message, .error)) }
    }
    
    /// Publish a warning message to the debug overlay
    /// - Parameter message: The warning message text
    public func warning(_ message: String) {
        guard settings.debugOverlayEnabled else { return }
        DispatchQueue.main.async { self.messageSubject.send((message, .warning)) }
    }
    
    /// Publish an info message to the debug overlay
    /// - Parameter message: The info message text
    public func info(_ message: String) {
        guard settings.debugOverlayEnabled else { return }
        DispatchQueue.main.async { self.messageSubject.send((message, .info)) }
    }
    
    /// Publish a success message to the debug overlay
    /// - Parameter message: The success message text
    public func success(_ message: String) {
        guard settings.debugOverlayEnabled else { return }
        DispatchQueue.main.async { self.messageSubject.send((message, .success)) }
    }
}
