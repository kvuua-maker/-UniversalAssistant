import Foundation

enum BusinessProfileVerificationState: String, Codable, Sendable {
    case unclaimed = "UNCLAIMED"
    case pending = "PENDING"
    case verified = "VERIFIED"
    case rejected = "REJECTED"
    case suspended = "SUSPENDED"
}

struct BusinessOpeningHours: Equatable, Codable, Sendable {
    let weeklySchedule: [String: String]
    let sourceReference: String
    let observedAt: Date
}

struct BusinessContactDetails: Equatable, Codable, Sendable {
    let phone: String?
    let website: URL?
    let address: String?
}

struct BusinessProfileAuditEvent: Equatable, Codable, Sendable {
    let sequence: Int
    let actorReference: String
    let action: String
    let reason: String
    let occurredAt: Date
}

struct BusinessProfileReport: Equatable, Codable, Sendable {
    let reportID: UUID
    let category: String
    let evidenceReference: String?
    let createdAt: Date
}

struct BusinessProfile: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let partnerID: UUID
    var displayName: String
    var state: BusinessProfileVerificationState
    var claimantReference: String?
    var hours: BusinessOpeningHours?
    var contacts: BusinessContactDetails
    var reports: [BusinessProfileReport]
    var auditTrail: [BusinessProfileAuditEvent]
}

enum BusinessProfileError: Error, Equatable, Sendable {
    case invalidProfile
    case invalidTransition
    case verificationRequired
}

actor PartnerProfileService {
    private var profiles: [UUID: BusinessProfile] = [:]

    func registerUnclaimed(partnerID: UUID, name: String) throws -> BusinessProfile {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw BusinessProfileError.invalidProfile }
        let profile = BusinessProfile(id: UUID(), partnerID: partnerID, displayName: clean, state: .unclaimed,
                                      claimantReference: nil, hours: nil,
                                      contacts: .init(phone: nil, website: nil, address: nil), reports: [], auditTrail: [])
        profiles[profile.id] = profile
        return profile
    }

    func claim(_ profileID: UUID, claimant: String, at: Date = .now) throws -> BusinessProfile {
        var profile = try existing(profileID)
        guard profile.state == .unclaimed, !claimant.isEmpty else { throw BusinessProfileError.invalidTransition }
        profile.claimantReference = claimant
        transition(&profile, to: .pending, actor: claimant, action: "profile_claimed", reason: "verification_required", at: at)
        profiles[profileID] = profile
        return profile
    }

    func decide(_ profileID: UUID, approved: Bool, actor: String, evidenceReference: String, at: Date = .now) throws -> BusinessProfile {
        var profile = try existing(profileID)
        guard profile.state == .pending, !actor.isEmpty, !evidenceReference.isEmpty else { throw BusinessProfileError.invalidTransition }
        transition(&profile, to: approved ? .verified : .rejected, actor: actor,
                   action: approved ? "profile_verified" : "profile_rejected", reason: evidenceReference, at: at)
        profiles[profileID] = profile
        return profile
    }

    func update(_ profileID: UUID, name: String, hours: BusinessOpeningHours?, contacts: BusinessContactDetails,
                actor: String, at: Date = .now) throws -> BusinessProfile {
        var profile = try existing(profileID)
        guard profile.state == .verified else { throw BusinessProfileError.verificationRequired }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !actor.isEmpty,
              hours.map({ !$0.sourceReference.isEmpty && $0.observedAt <= at }) ?? true,
              contacts.website.map({ $0.scheme == "https" }) ?? true
        else { throw BusinessProfileError.invalidProfile }
        profile.displayName = clean
        profile.hours = hours
        profile.contacts = contacts
        audit(&profile, actor: actor, action: "permitted_profile_data_updated", reason: "partner_update", at: at)
        profiles[profileID] = profile
        return profile
    }

    func report(_ profileID: UUID, category: String, evidenceReference: String?, at: Date = .now) throws -> BusinessProfile {
        var profile = try existing(profileID)
        guard !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BusinessProfileError.invalidProfile }
        profile.reports.append(.init(reportID: UUID(), category: category, evidenceReference: evidenceReference, createdAt: at))
        audit(&profile, actor: "user_report", action: "profile_reported", reason: category, at: at)
        profiles[profileID] = profile
        return profile
    }

    func suspend(_ profileID: UUID, actor: String, reason: String, at: Date = .now) throws -> BusinessProfile {
        var profile = try existing(profileID)
        guard profile.state == .verified, !actor.isEmpty, !reason.isEmpty else { throw BusinessProfileError.invalidTransition }
        transition(&profile, to: .suspended, actor: actor, action: "profile_suspended", reason: reason, at: at)
        profiles[profileID] = profile
        return profile
    }

    func profile(_ id: UUID) -> BusinessProfile? { profiles[id] }

    private func existing(_ id: UUID) throws -> BusinessProfile {
        guard let value = profiles[id] else { throw BusinessProfileError.invalidProfile }
        return value
    }

    private func transition(_ profile: inout BusinessProfile, to state: BusinessProfileVerificationState,
                            actor: String, action: String, reason: String, at: Date) {
        profile.state = state
        audit(&profile, actor: actor, action: action, reason: reason, at: at)
    }

    private func audit(_ profile: inout BusinessProfile, actor: String, action: String, reason: String, at: Date) {
        profile.auditTrail.append(.init(sequence: profile.auditTrail.count + 1, actorReference: actor,
                                        action: action, reason: reason, occurredAt: at))
    }
}
