import Foundation
import Combine
import SwiftUI

/// A model for managing debug messages to be displayed in an overlay
public class DebugOverlayModel: ObservableObject {
    /// Maximum number of messages to keep in history (increase for scrollable history)
    private let maxMessages = 200
    
    /// Time a message stays visible before fading (in seconds)
    /// Lifetime of a message. Set to nil to persist indefinitely.
    private let messageLifetime: TimeInterval? = nil
    
    /// Debug message struct that conforms to Identifiable and Equatable
    public struct DebugMessage: Identifiable, Equatable {
        public let id: UUID
        public let message: String
        public let timestamp: Date
        public let type: MessageType
        
        public static func == (lhs: DebugMessage, rhs: DebugMessage) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    /// Published array of debug messages with timestamps
    @Published private(set) var messages: [DebugMessage] = []
    
    /// Publisher for new debug messages
    private let messageSubject = PassthroughSubject<(String, MessageType), Never>()
    
    /// Message type for styling
    public enum MessageType {
        case error
        case warning
        case info
        case success
        
        var color: Color {
            switch self {
            case .error: return .red
            case .warning: return .orange
            case .info: return .blue
            case .success: return .green
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupSubscriptions()
        
        // Subscribe to the DebugPublisher for messages from anywhere in the app
        DebugPublisher.shared.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message, type in
                self?.addMessage(message, type: type)
            }
            .store(in: &cancellables)
    }
    
    private func setupSubscriptions() {
        // Process incoming messages
        messageSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message, type in
                self?.addMessage(message, type: type)
            }
            .store(in: &cancellables)
    }
    
    /// Add a new debug message
    /// - Parameters:
    ///   - message: The message text
    ///   - type: The message type (error, warning, info, success)
    private func addMessage(_ message: String, type: MessageType) {
        let newMessage = DebugMessage(id: UUID(), message: message, timestamp: Date(), type: type)
        
        // Add new message and trim if needed
        messages.append(newMessage)
        if messages.count > maxMessages {
            messages.removeFirst()
        }
        
        // Auto-remove only if a lifetime is configured
        if let lifetime = messageLifetime {
            DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) { [weak self] in
                self?.removeMessage(id: newMessage.id)
            }
        }
    }
    
    /// Remove a message by ID
    /// - Parameter id: The UUID of the message to remove
    private func removeMessage(id: UUID) {
        messages.removeAll { $0.id == id }
    }
    
    /// Clear all messages
    func clearAllMessages() {
        messages.removeAll()
    }
    
    // MARK: - Public API
    
    /// Add an error message
    /// - Parameter message: The error message text
    func addError(_ message: String) {
        messageSubject.send((message, .error))
    }
    
    /// Add a warning message
    /// - Parameter message: The warning message text
    func addWarning(_ message: String) {
        messageSubject.send((message, .warning))
    }
    
    /// Add an info message
    /// - Parameter message: The info message text
    func addInfo(_ message: String) {
        messageSubject.send((message, .info))
    }
    
    /// Add a success message
    /// - Parameter message: The success message text
    func addSuccess(_ message: String) {
        messageSubject.send((message, .success))
    }
}
