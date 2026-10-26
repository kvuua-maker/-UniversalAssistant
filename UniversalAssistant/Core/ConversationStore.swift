import Foundation

/// Visible conversation: what the user said, what the assistant is doing, and
/// how it ended. Kept in memory for the session so the user can scroll back.
@MainActor
@Observable
final class ConversationStore {
    static let shared = ConversationStore()

    enum Role: String { case user, assistant, status, error }

    struct Message: Identifiable, Equatable {
        let id = UUID()
        let role: Role
        let text: String
        let at: Date
    }

    private(set) var messages: [Message] = []
    private let limit = 200

    private init() {}

    func add(_ role: Role, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(.init(role: role, text: trimmed, at: Date()))
        if messages.count > limit { messages.removeFirst(messages.count - limit) }
    }

    func clear() { messages.removeAll() }
}
