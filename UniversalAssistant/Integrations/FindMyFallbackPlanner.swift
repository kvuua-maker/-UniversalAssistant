import Foundation

enum FindMyFallbackKind: String, Equatable, Sendable { case openSystemAppManually, unavailable }
struct FindMyFallback: Equatable, Sendable {
    let kind: FindMyFallbackKind
    let instructionKey: String
    let personLabel: String?
    let claimsLocation: Bool
}
enum FindMyFallbackError: Error, Equatable, Sendable { case invalidRequest }

struct FindMyFallbackPlanner: Sendable {
    func plan(personLabel: String?, deviceHasFindMy: Bool) throws -> FindMyFallback {
        let trimmed = personLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, trimmed.isEmpty { throw FindMyFallbackError.invalidRequest }
        guard deviceHasFindMy else {
            return .init(kind: .unavailable, instructionKey: "find_my_not_available", personLabel: trimmed, claimsLocation: false)
        }
        return .init(kind: .openSystemAppManually, instructionKey: "open_find_my_people_tab_and_select_person",
                     personLabel: trimmed, claimsLocation: false)
    }
}
