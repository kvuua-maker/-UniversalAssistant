import Foundation

enum AudioDeviceTransport: String, Codable, CaseIterable, Sendable {
    case localDevice, wired, bluetoothSystemRoute, coreBluetoothAccessory
    case mfiExternalAccessory, airPlay, googleCast, lanIP, cloudAPI, carAudio, providerAppHandoff
}

enum AudioCapabilityState: String, Codable, Sendable {
    case supportedVerifiedLocal, supportedLiveRequired, systemHandoffOnly, readOnly
    case unsupportedVerified, unknown
}

enum AudioDeviceCapability: String, Codable, CaseIterable, Sendable {
    case routeSelect, connect, disconnect, volume, mute, play, pause, stop, next, previous, seek
    case queue, shuffle, repeatMode, metadata, sourceInput, grouping, groupVolume, perDeviceVolume
    case battery, charging, codec, hardwareEQ, bass, mid, treble, presets, loudness, balance
    case anc, transparency, ambient, adaptive, conversationEnhancement, spatialAudio, headTracking
    case microphone, sidetone, multipoint, lights, stereoParty, power, standby, firmware, status
    case assistantDSP
}

enum AudioControlMechanism: String, Codable, Sendable {
    case appleSystemPicker, appleSystemMedia, musicKit, googleCastSDK, sonosControlAPI
    case heosCLI, bangOlufsenControlLink, bluOSCustomIntegration, wiimHTTPAPI
    case documentedLAN, documentedBluetooth, mfiProtocol, providerCloudAPI, appHandoff, assistantDSP
}

struct AudioCapabilityEvidence: Codable, Equatable, Sendable {
    let mechanism: AudioControlMechanism
    let state: AudioCapabilityState
    let officialURL: URL
    let verifiedAt: Date
    let modelScope: Set<String>
    let firmwareScope: Set<String>
    let limitations: [String]
}

struct AudioDeviceIdentity: Codable, Hashable, Sendable {
    let routeID: String
    let vendor: String
    let modelFamily: String?
    let firmware: String?
    let transport: AudioDeviceTransport
    let roomID: String?
    let providerAccountID: String?
    let householdID: String?
    let groupID: String?

    var scopeKey: String {
        [providerAccountID ?? "local", householdID ?? "none", routeID, modelFamily ?? "unknown", firmware ?? "unknown"]
            .joined(separator: "|")
    }
}

struct AudioDeviceCapabilityRecord: Codable, Equatable, Sendable {
    let identity: AudioDeviceIdentity
    let capabilities: [AudioDeviceCapability: AudioCapabilityEvidence]
    let discoveredAt: Date
    let policyRevision: String
}

enum AudioCapabilityRegistryError: Error, Equatable {
    case invalidEvidence, unsupported, liveVerificationRequired, readOnly, identityMismatch
}

actor SpeakerHeadphoneCapabilityRegistry {
    private var records: [String: AudioDeviceCapabilityRecord] = [:]

    func upsert(_ record: AudioDeviceCapabilityRecord) throws {
        guard !record.identity.routeID.isEmpty, !record.identity.vendor.isEmpty,
              !record.policyRevision.isEmpty, !record.capabilities.isEmpty else {
            throw AudioCapabilityRegistryError.invalidEvidence
        }
        for evidence in record.capabilities.values {
            guard evidence.officialURL.scheme == "https", evidence.verifiedAt <= Date() else {
                throw AudioCapabilityRegistryError.invalidEvidence
            }
        }
        records[record.identity.scopeKey] = record
    }

    func record(for identity: AudioDeviceIdentity) -> AudioDeviceCapabilityRecord? {
        records[identity.scopeKey]
    }

    func require(_ capability: AudioDeviceCapability, for identity: AudioDeviceIdentity) throws -> AudioCapabilityEvidence {
        guard let record = records[identity.scopeKey] else { throw AudioCapabilityRegistryError.identityMismatch }
        guard let evidence = record.capabilities[capability] else { throw AudioCapabilityRegistryError.unsupported }
        switch evidence.state {
        case .supportedVerifiedLocal: return evidence
        case .supportedLiveRequired: throw AudioCapabilityRegistryError.liveVerificationRequired
        case .readOnly: throw AudioCapabilityRegistryError.readOnly
        case .systemHandoffOnly where capability == .routeSelect: return evidence
        case .systemHandoffOnly, .unsupportedVerified, .unknown: throw AudioCapabilityRegistryError.unsupported
        }
    }

    func invalidate(routeID: String) { records = records.filter { $0.value.identity.routeID != routeID } }
    func invalidate(providerAccountID: String) { records = records.filter { $0.value.identity.providerAccountID != providerAccountID } }
    func invalidate(policyRevision: String) { records = records.filter { $0.value.policyRevision == policyRevision } }
    func all() -> [AudioDeviceCapabilityRecord] { records.values.sorted { $0.identity.scopeKey < $1.identity.scopeKey } }
}

enum AudioCommandKind: String, Codable, Sendable {
    case showRoutePicker, setVolume, mute, unmute, play, pause, stop, next, previous, seek
    case setBass, setMid, setTreble, setBalance, setPreset, setANC, setTransparency
    case selectSource, group, ungroup, setGroupVolume, power, standby, applyDSPProfile
}

struct AudioDeviceCommand: Codable, Equatable, Sendable {
    let idempotencyKey: String
    let device: AudioDeviceIdentity
    let kind: AudioCommandKind
    let numericValue: Double?
    let textValue: String?
}

struct AudioDeviceSnapshot: Codable, Equatable, Sendable {
    let identity: AudioDeviceIdentity
    let volume: Double?
    let muted: Bool?
    let playback: String?
    let metadataTitle: String?
    let batteryPercent: Int?
    let observedAt: Date
}

enum AudioCommandOutcome: String, Codable, Sendable { case systemHandoffPrepared, sentUnconfirmed, confirmed }
struct AudioCommandResult: Codable, Equatable, Sendable {
    let commandID: String
    let outcome: AudioCommandOutcome
    let authoritativeSnapshot: AudioDeviceSnapshot?
}

protocol AudioDeviceProviderAdapter: Sendable {
    var providerID: String { get }
    func snapshot(for device: AudioDeviceIdentity) async throws -> AudioDeviceSnapshot
    func execute(_ command: AudioDeviceCommand) async throws
}

enum AudioProviderPolicyDecision: String, Codable, Sendable { case allowed, handoffOnly, prohibited, unknown }
struct AudioProviderPolicy: Codable, Equatable, Sendable {
    let providerID: String
    let voiceControl: AudioProviderPolicyDecision
    let rawAudioDSP: AudioProviderPolicyDecision
    let commercialUse: AudioProviderPolicyDecision
    let evidenceURL: URL
    let effectiveAt: Date
    let revision: String
}

actor AudioProviderPolicyRegistry {
    private var policies: [String: AudioProviderPolicy] = [:]
    func upsert(_ policy: AudioProviderPolicy) throws {
        guard !policy.providerID.isEmpty, !policy.revision.isEmpty,
              policy.evidenceURL.scheme == "https", policy.effectiveAt <= Date() else {
            throw AudioCapabilityRegistryError.invalidEvidence
        }
        policies[policy.providerID] = policy
    }
    func policy(providerID: String) -> AudioProviderPolicy? { policies[providerID] }
}

enum AudioControlError: Error, Equatable { case invalidValue, providerUnavailable, policyProhibited, confirmationUnavailable }

actor UniversalAudioDeviceCoordinator {
    private let capabilities: SpeakerHeadphoneCapabilityRegistry
    private let policies: AudioProviderPolicyRegistry
    private let adapters: [String: any AudioDeviceProviderAdapter]
    private var completed: [String: AudioCommandResult] = [:]

    init(capabilities: SpeakerHeadphoneCapabilityRegistry,
         policies: AudioProviderPolicyRegistry,
         adapters: [any AudioDeviceProviderAdapter]) {
        self.capabilities = capabilities
        self.policies = policies
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.providerID, $0) })
    }

    func execute(_ command: AudioDeviceCommand, providerID: String, originatedFromAI: Bool = false) async throws -> AudioCommandResult {
        if let prior = completed[command.idempotencyKey] { return prior }
        let capability = Self.capability(for: command.kind)
        let evidence = try await capabilities.require(capability, for: command.device)
        try Self.validate(command)

        if originatedFromAI, let policy = await policies.policy(providerID: providerID), policy.voiceControl != .allowed {
            throw AudioControlError.policyProhibited
        }
        if evidence.state == .systemHandoffOnly {
            let result = AudioCommandResult(commandID: command.idempotencyKey, outcome: .systemHandoffPrepared, authoritativeSnapshot: nil)
            completed[command.idempotencyKey] = result
            return result
        }
        guard let adapter = adapters[providerID] else { throw AudioControlError.providerUnavailable }
        try await adapter.execute(command)
        let snapshot = try await adapter.snapshot(for: command.device)
        guard snapshot.identity.scopeKey == command.device.scopeKey else { throw AudioCapabilityRegistryError.identityMismatch }
        let result = AudioCommandResult(commandID: command.idempotencyKey, outcome: .confirmed, authoritativeSnapshot: snapshot)
        completed[command.idempotencyKey] = result
        return result
    }

    private static func validate(_ command: AudioDeviceCommand) throws {
        switch command.kind {
        case .setVolume, .setGroupVolume:
            guard let value = command.numericValue, (0...1).contains(value) else { throw AudioControlError.invalidValue }
        case .setBass, .setMid, .setTreble:
            guard let value = command.numericValue, (-6...6).contains(value) else { throw AudioControlError.invalidValue }
        case .setBalance:
            guard let value = command.numericValue, (-1...1).contains(value) else { throw AudioControlError.invalidValue }
        default: break
        }
    }

    static func capability(for kind: AudioCommandKind) -> AudioDeviceCapability {
        switch kind {
        case .showRoutePicker: .routeSelect
        case .setVolume: .volume
        case .mute, .unmute: .mute
        case .play: .play
        case .pause: .pause
        case .stop: .stop
        case .next: .next
        case .previous: .previous
        case .seek: .seek
        case .setBass: .bass
        case .setMid: .mid
        case .setTreble: .treble
        case .setBalance: .balance
        case .setPreset: .presets
        case .setANC: .anc
        case .setTransparency: .transparency
        case .selectSource: .sourceInput
        case .group, .ungroup: .grouping
        case .setGroupVolume: .groupVolume
        case .power: .power
        case .standby: .standby
        case .applyDSPProfile: .assistantDSP
        }
    }
}

struct AudioDSPProfile: Codable, Equatable, Sendable {
    let id: String
    let lowGainDB: Double
    let midGainDB: Double
    let highGainDB: Double
    let balance: Double
    let outputGainDB: Double
    let limiterCeiling: Double

    static let flat = AudioDSPProfile(id: "flat", lowGainDB: 0, midGainDB: 0, highGainDB: 0,
                                      balance: 0, outputGainDB: 0, limiterCeiling: 0.95)
}

enum AudioStreamAuthorization: String, Sendable { case assistantOwned, explicitlyLicensed, externalUnmodifiable }
enum AudioDSPError: Error, Equatable { case unauthorizedStream, invalidProfile }

struct UniversalAudioDSP: Sendable {
    func process(mono samples: [Float], sampleRate: Double, profile: AudioDSPProfile,
                 authorization: AudioStreamAuthorization) throws -> [Float] {
        guard authorization != .externalUnmodifiable else { throw AudioDSPError.unauthorizedStream }
        guard sampleRate >= 8_000, (-6...6).contains(profile.lowGainDB), (-6...6).contains(profile.midGainDB),
              (-6...6).contains(profile.highGainDB), (-1...1).contains(profile.balance),
              (-12...3).contains(profile.outputGainDB), (0.1...1).contains(profile.limiterCeiling) else {
            throw AudioDSPError.invalidProfile
        }
        let lowMultiplier = pow(10, profile.lowGainDB / 20)
        let midMultiplier = pow(10, profile.midGainDB / 20)
        let highMultiplier = pow(10, profile.highGainDB / 20)
        let outputMultiplier = pow(10, profile.outputGainDB / 20)
        let lowAlpha = min(1, 2 * Double.pi * 250 / sampleRate)
        let highAlpha = min(1, 2 * Double.pi * 4_000 / sampleRate)
        var low = 0.0, highBase = 0.0
        return samples.map { raw in
            let x = Double(raw)
            low += lowAlpha * (x - low)
            highBase += highAlpha * (x - highBase)
            let high = x - highBase
            let mid = x - low - high
            let mixed = (low * lowMultiplier + mid * midMultiplier + high * highMultiplier) * outputMultiplier
            let ceiling = profile.limiterCeiling
            return Float(max(-ceiling, min(ceiling, mixed)))
        }
    }
}

struct SpeakerHeadphoneProfile: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let userID: String
    let deviceScopeKey: String
    let friendlyName: String
    let roomOrContext: String
    let preferredSafeVolume: Double
    let hardwareSettings: [AudioDeviceCapability: Double]
    let dspProfile: AudioDSPProfile?
    let enabled: Bool
}

actor SpeakerHeadphoneProfileStore {
    private let fileURL: URL?
    private var profiles: [String: SpeakerHeadphoneProfile] = [:]
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: SpeakerHeadphoneProfile].self, from: data) {
            profiles = decoded
        }
    }

    func upsert(_ profile: SpeakerHeadphoneProfile) throws {
        guard !profile.userID.isEmpty, !profile.deviceScopeKey.isEmpty,
              (0...1).contains(profile.preferredSafeVolume) else { throw AudioControlError.invalidValue }
        profiles[profile.id] = profile; try persist()
    }
    func profile(id: String, userID: String, device: AudioDeviceIdentity) -> SpeakerHeadphoneProfile? {
        guard let value = profiles[id], value.userID == userID, value.deviceScopeKey == device.scopeKey else { return nil }
        return value
    }
    func all(userID: String) -> [SpeakerHeadphoneProfile] { profiles.values.filter { $0.userID == userID }.sorted { $0.id < $1.id } }

    private func persist() throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(profiles).write(to: fileURL, options: .atomic)
    }
}

enum AudioAutomationTrigger: String, Codable, Sendable { case routeConnected, nightMode, carConnected, speechContent, routeDisconnected }
struct AudioAutomationRule: Codable, Equatable, Sendable {
    let id: String
    let userID: String
    let trigger: AudioAutomationTrigger
    let deviceScopeKey: String
    let profileID: String
    let enabled: Bool
    let maximumVolume: Double
}

struct AudioAutomationPlan: Equatable, Sendable {
    let profileID: String
    let targetVolume: Double
    let rampSteps: [Double]
}

struct AudioAutomationEngine: Sendable {
    func plan(rule: AudioAutomationRule, profile: SpeakerHeadphoneProfile,
              currentVolume: Double, userID: String, device: AudioDeviceIdentity) -> AudioAutomationPlan? {
        guard rule.enabled, profile.enabled, rule.userID == userID, profile.userID == userID,
              rule.deviceScopeKey == device.scopeKey, profile.deviceScopeKey == device.scopeKey,
              rule.profileID == profile.id else { return nil }
        let target = min(max(0, profile.preferredSafeVolume), min(0.8, rule.maximumVolume))
        let distance = target - currentVolume
        let stepCount = max(1, Int(ceil(abs(distance) / 0.05)))
        let steps = (1...stepCount).map { currentVolume + distance * Double($0) / Double(stepCount) }
        return AudioAutomationPlan(profileID: profile.id, targetVolume: target, rampSteps: steps)
    }
}

struct HEOSResponse: Equatable, Sendable {
    let command: String
    let succeeded: Bool
    let message: [String: String]
    let payload: [[String: String]]
}

enum HEOSParserError: Error, Equatable { case malformed }
struct HEOSForwardCompatibleParser: Sendable {
    func parse(json data: Data) throws -> HEOSResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = root["command"] as? String,
              let heos = root["heos"] as? [String: Any],
              let result = heos["result"] as? String else { throw HEOSParserError.malformed }
        let message: [String: String] = Self.stringMap(heos["message"])
        let payload: [[String: String]] = (root["payload"] as? [[String: Any]] ?? []).map { Self.stringMap($0) }
        return HEOSResponse(command: command, succeeded: result == "success", message: message, payload: payload)
    }
    private static func stringMap(_ value: Any?) -> [String: String] {
        guard let dictionary = value as? [String: Any] else { return [:] }
        return dictionary.reduce(into: [:]) { result, pair in result[pair.key] = String(describing: pair.value) }
    }
}
