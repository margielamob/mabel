import Foundation
import SwiftData

/// The role of the entity sending a message in a chat thread.
enum Role: String, Codable {
    case user
    case assistant
}

/// Represents a single message within a chat thread.
@Model
final class ChatMessage {
    @Attribute(.unique)
    var id: UUID
    var role: Role
    var text: String
    var timestamp: Date

    // FIX: Add a relationship back-pointer to the parent thread.
    var thread: ChatThread?

    init(id: UUID = UUID(), role: Role, text: String, timestamp: Date = .now, thread: ChatThread?) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.thread = thread
    }
}

/// Represents a chat thread associated with a specific translation.
@Model
final class ChatThread {
    @Attribute(.unique)
    var id: UUID
    
    // Establishes a one-to-one relationship with a Translation
    var translationId: UUID

    // FIX: The inverse now correctly points to the 'thread' property on ChatMessage.
    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.thread)
    var messages: [ChatMessage] = []

    // FIX: Removed the @Transient property as it's not supported by the SwiftData macro.
    // The parent translation object will be managed by the ViewModel.

    init(id: UUID = UUID(), translationId: UUID) {
        self.id = id
        self.translationId = translationId
    }
}

// Conformance for use in SwiftUI navigation.
extension ChatThread: Hashable {
    static func == (lhs: ChatThread, rhs: ChatThread) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
