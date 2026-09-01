import Foundation

enum CommandIntent: String, Codable, Sendable {
    case open, show, calendarCreate, reminderCreate, navigate, cancel, undo, unknown
}

struct StructuredCommand: Equatable, Codable, Sendable {
    let originalText: String
    let normalizedText: String
    let intent: CommandIntent
    let entities: [String: String]
}

protocol CommandParsing: Sendable { func parse(_ text: String) -> StructuredCommand }

struct LocalCommandEngine: CommandParsing {
    func parse(_ text: String) -> StructuredCommand {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let intent: CommandIntent
        if ["відкрий", "открой", "open ", "öffne", "ouvre"].contains(where: normalized.hasPrefix) {
            intent = .open
        } else if ["покажи", "show ", "zeige", "montre"].contains(where: normalized.hasPrefix) {
            intent = .show
        } else if normalized.contains("календар") || normalized.hasPrefix("запиши") || normalized.hasPrefix("создай встреч") {
            intent = .calendarCreate
        } else if ["нагадай", "напомни", "remind"].contains(where: normalized.hasPrefix) {
            intent = .reminderCreate
        } else if ["веди", "navigate", "route"].contains(where: normalized.hasPrefix) {
            intent = .navigate
        } else if ["скасуй", "отмени", "cancel"].contains(where: normalized.hasPrefix) {
            intent = .cancel
        } else if normalized.contains("відміни останнє") || normalized == "undo" {
            intent = .undo
        } else { intent = .unknown }
        return StructuredCommand(originalText: text, normalizedText: normalized, intent: intent, entities: [:])
    }
}
