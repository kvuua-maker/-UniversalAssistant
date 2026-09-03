import Foundation

enum FavoriteKind: String, Codable, Sendable { case product, place, listing, event, service }
enum FavoriteFreshness: String, Codable, Sendable { case current, stale, unknown }

struct FavoriteReference: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let kind: FavoriteKind
    let providerID: String
    let externalReference: String
    var displayTitle: String
    var displaySubtitle: String?
    var mutableSummary: String?
    var sourceUpdatedAt: Date?
    var lastRefreshAttemptAt: Date?
    var freshness: FavoriteFreshness

    init(id: String, kind: FavoriteKind, providerID: String, externalReference: String,
         displayTitle: String, displaySubtitle: String? = nil, mutableSummary: String? = nil,
         sourceUpdatedAt: Date? = nil, lastRefreshAttemptAt: Date? = nil,
         freshness: FavoriteFreshness = .unknown) {
        self.id = id; self.kind = kind; self.providerID = providerID
        self.externalReference = externalReference; self.displayTitle = displayTitle
        self.displaySubtitle = displaySubtitle; self.mutableSummary = mutableSummary
        self.sourceUpdatedAt = sourceUpdatedAt; self.lastRefreshAttemptAt = lastRefreshAttemptAt
        self.freshness = freshness
    }
}

protocol FavoriteRefreshing: Sendable {
    func refresh(_ favorite: FavoriteReference) async throws -> FavoriteReference
}

enum FavoriteStoreError: Error, Equatable { case invalidReference, providerMismatch }

actor FavoriteStore {
    private let store: LocalStore
    private let filename: String
    private let maximumCount: Int
    private var values: [FavoriteReference] = []

    init(store: LocalStore = .shared, filename: String = "favorite-references.json", maximumCount: Int = 250) {
        self.store = store; self.filename = filename; self.maximumCount = max(1, maximumCount)
    }

    func restore() async throws {
        values = Array((try await store.load([FavoriteReference].self, from: filename) ?? [])
            .filter(Self.valid).prefix(maximumCount))
    }

    func save(_ value: FavoriteReference) async throws {
        guard Self.valid(value) else { throw FavoriteStoreError.invalidReference }
        values.removeAll { $0.id == value.id }
        values.insert(value, at: 0)
        if values.count > maximumCount { values.removeLast(values.count - maximumCount) }
        try await store.save(values, as: filename)
    }

    func remove(id: String) async throws {
        values.removeAll { $0.id == id }
        try await store.save(values, as: filename)
    }

    func snapshot() -> [FavoriteReference] { values }

    func refresh(id: String, using refresher: any FavoriteRefreshing, now: Date = .now) async throws -> FavoriteReference {
        guard let index = values.firstIndex(where: { $0.id == id }) else { throw FavoriteStoreError.invalidReference }
        var refreshed = try await refresher.refresh(values[index])
        guard refreshed.id == values[index].id, refreshed.providerID == values[index].providerID,
              refreshed.externalReference == values[index].externalReference else { throw FavoriteStoreError.providerMismatch }
        refreshed.lastRefreshAttemptAt = now
        values[index] = refreshed
        try await store.save(values, as: filename)
        return refreshed
    }

    private static func valid(_ value: FavoriteReference) -> Bool {
        !value.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !value.providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !value.externalReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !value.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        value.displayTitle.count <= 160 && (value.displaySubtitle?.count ?? 0) <= 240 &&
        (value.mutableSummary?.count ?? 0) <= 240
    }
}

enum PersonalTaskKind: String, Codable, Sendable { case booking, order, appointment, watch, unfinished, upcoming }
enum PersonalTaskSource: String, Codable, Sendable { case assistant, provider, systemReference }

enum PersonalTaskStatus: String, Codable, Sendable {
    case pending, confirmed, inProgress, actionRequired, completed, cancelled, unknown
    var requiresAttention: Bool { self == .actionRequired }
}

struct PersonalTaskItem: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let kind: PersonalTaskKind
    let source: PersonalTaskSource
    let externalReference: String
    let title: String
    let status: PersonalTaskStatus
    let relevantAt: Date?
    let verifiedAt: Date?
    var requiresAttention: Bool { status.requiresAttention }
}

struct PersonalTaskHub: Sendable {
    func aggregate(assistantOwned: [PersonalTaskItem], systemReferences: [PersonalTaskItem]) -> [PersonalTaskItem] {
        var selected: [String: PersonalTaskItem] = [:]
        for item in assistantOwned + systemReferences where valid(item) {
            let key = "\(item.source.rawValue):\(item.externalReference)"
            if let current = selected[key] {
                if (item.verifiedAt ?? .distantPast) > (current.verifiedAt ?? .distantPast) { selected[key] = item }
            } else { selected[key] = item }
        }
        return selected.values
            .filter { ![.completed, .cancelled].contains($0.status) }
            .sorted {
                if $0.requiresAttention != $1.requiresAttention { return $0.requiresAttention }
                return ($0.relevantAt ?? .distantFuture) < ($1.relevantAt ?? .distantFuture)
            }
    }

    private func valid(_ item: PersonalTaskItem) -> Bool {
        !item.id.isEmpty && !item.externalReference.isEmpty && !item.title.isEmpty &&
        (item.source != .systemReference || [.upcoming, .appointment].contains(item.kind))
    }
}
