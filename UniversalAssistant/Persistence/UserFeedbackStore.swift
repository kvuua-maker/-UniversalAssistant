import Foundation

enum UserFeedbackCategory: String, Codable, Sendable { case wrongResult }

struct UserFeedbackRecord: Codable, Equatable, Sendable {
    let diagnosticID: String
    let category: UserFeedbackCategory
    let createdAt: Date
}

actor UserFeedbackStore {
    static let shared = UserFeedbackStore()
    private let localStore: LocalStore
    private let filename: String

    init(localStore: LocalStore = .shared, filename: String = "feedback-queue.json") {
        self.localStore = localStore
        self.filename = filename
    }

    func record(_ category: UserFeedbackCategory, now: Date = .now) async throws -> UserFeedbackRecord {
        var records = try await localStore.load([UserFeedbackRecord].self, from: filename) ?? []
        let identifier = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let record = UserFeedbackRecord(
            diagnosticID: "UA-" + identifier.prefix(12).uppercased(),
            category: category,
            createdAt: now
        )
        records.append(record)
        if records.count > 100 { records.removeFirst(records.count - 100) }
        try await localStore.save(records, as: filename)
        return record
    }

    func records() async throws -> [UserFeedbackRecord] {
        try await localStore.load([UserFeedbackRecord].self, from: filename) ?? []
    }
}
