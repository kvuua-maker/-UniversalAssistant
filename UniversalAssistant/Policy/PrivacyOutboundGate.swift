import Foundation

enum PrivacyDataClassification: Int, Codable, Comparable, Sendable {
    case publicData, internalNonSensitive, personal, sensitivePersonal, authSecret, paymentSecret, cryptographicSecret
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    var neverAI: Bool { self == .authSecret || self == .paymentSecret || self == .cryptographicSecret }
}

enum PrivacyOutboundDestination: Equatable, Sendable { case ai(providerID: String), provider(id: String), analytics, userExport }
enum PrivacyConsentState: String, Codable, Sendable { case granted, denied, notRequested, revoked }
enum PrivacyContentTrust: String, Codable, Sendable { case trustedLocal, verifiedProvider, untrustedRetrieved }

struct PrivacyPayloadField: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let value: String
    let classification: PrivacyDataClassification?
    let purpose: String
    var requiredForSemantics: Bool
    var metadata: Bool = false
}

struct PrivacyOutboundRequest: Equatable, Sendable {
    let destination: PrivacyOutboundDestination
    let purpose: String
    let fields: [PrivacyPayloadField]
    let consent: PrivacyConsentState
    let permittedPurposes: Set<String>
    let maxPersonalFields: Int
    let contentTrust: PrivacyContentTrust
}

struct PrivacyOutboundDecision: Equatable, Sendable {
    let allowedFields: [PrivacyPayloadField]
    let blockedFieldNames: [String]
    let requiresConsent: Bool
    let safeFallbackAvailable: Bool
}

enum PrivacyOutboundError: Error, Equatable, Sendable { case unknownClassification(String), missingPurpose, semanticFieldWouldBeRemoved(String) }

struct PrivacyOutboundGate: Sendable {
    private let secretPatterns = [
        #"(?i)bearer\s+[a-z0-9._~+/=-]+"#,
        #"(?i)(password|passwd|refresh[_ -]?token|api[_ -]?key|private[_ -]?key|client[_ -]?secret)\s*[:=]\s*\S+"#,
        #"\b(?:\d[ -]*?){13,19}\b"#
    ]

    func evaluate(_ request: PrivacyOutboundRequest) throws -> PrivacyOutboundDecision {
        guard !request.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.permittedPurposes.contains(request.purpose) else { throw PrivacyOutboundError.missingPurpose }
        let isAI: Bool = { if case .ai = request.destination { return true }; return false }()
        var allowed: [PrivacyPayloadField] = [], blocked: [String] = []
        for field in request.fields {
            guard let classification = field.classification else { throw PrivacyOutboundError.unknownClassification(field.name) }
            if isAI && (classification.neverAI || containsSecret(field.value)) { blocked.append(field.name); continue }
            if field.metadata && !field.requiredForSemantics { blocked.append(field.name); continue }
            allowed.append(field)
        }
        let personal = allowed.filter { ($0.classification ?? .cryptographicSecret) >= .personal }
        if personal.count > request.maxPersonalFields {
            let required = personal.filter(\.requiredForSemantics)
            guard required.count <= request.maxPersonalFields else { throw PrivacyOutboundError.semanticFieldWouldBeRemoved(required[request.maxPersonalFields].name) }
            let keepPersonal = Set((required + personal.filter { !$0.requiredForSemantics }.prefix(max(0, request.maxPersonalFields-required.count))).map(\.id))
            for field in allowed where (field.classification ?? .cryptographicSecret) >= .personal && !keepPersonal.contains(field.id) { blocked.append(field.name) }
            allowed.removeAll { ($0.classification ?? .cryptographicSecret) >= .personal && !keepPersonal.contains($0.id) }
        }
        let hasSensitive = allowed.contains { ($0.classification ?? .cryptographicSecret) >= .sensitivePersonal }
        let needsConsent = hasSensitive && request.consent != .granted
        if needsConsent { blocked.append(contentsOf: allowed.filter { ($0.classification ?? .cryptographicSecret) >= .sensitivePersonal }.map(\.name)); allowed.removeAll { ($0.classification ?? .cryptographicSecret) >= .sensitivePersonal } }
        return .init(allowedFields: allowed, blockedFieldNames: Array(Set(blocked)).sorted(), requiresConsent: needsConsent, safeFallbackAvailable: !allowed.isEmpty || !request.fields.isEmpty)
    }

    func sanitizeUntrustedContent(_ text: String) -> String {
        secretPatterns.reduce(text) { value, pattern in value.replacingOccurrences(of: pattern, with: "[REDACTED]", options: .regularExpression) }
    }

    private func containsSecret(_ value: String) -> Bool { secretPatterns.contains { value.range(of: $0, options: .regularExpression) != nil } }
}

struct PrivacyScopeKey: Hashable, Codable, Sendable { let userID: String; let accountID: String?; let providerID: String; let purpose: String }

actor PrivacyScopedAuthorizationCache<Value: Sendable> {
    struct Entry: Sendable { let value: Value; let expiresAt: Date }
    private var entries: [PrivacyScopeKey: Entry] = [:]
    func put(_ value: Value, for key: PrivacyScopeKey, expiresAt: Date) { entries[key] = .init(value: value, expiresAt: expiresAt) }
    func value(for key: PrivacyScopeKey, now: Date = .now) -> Value? { guard let e=entries[key], e.expiresAt >= now else { entries[key]=nil; return nil }; return e.value }
    func revoke(userID: String, providerID: String) { entries = entries.filter { $0.key.userID != userID || $0.key.providerID != providerID } }
}
