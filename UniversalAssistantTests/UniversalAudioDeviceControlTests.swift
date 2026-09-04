import Foundation
import Testing
@testable import UniversalAssistant

private actor AudioAdapterFixture: AudioDeviceProviderAdapter {
    let providerID: String
    var snapshotValue: AudioDeviceSnapshot
    private(set) var commands: [AudioDeviceCommand] = []
    init(providerID: String, device: AudioDeviceIdentity, volume: Double = 0.2) {
        self.providerID = providerID
        snapshotValue = .init(identity: device, volume: volume, muted: false, playback: "paused",
                              metadataTitle: nil, batteryPercent: nil, observedAt: Date())
    }
    func snapshot(for device: AudioDeviceIdentity) -> AudioDeviceSnapshot { snapshotValue }
    func execute(_ command: AudioDeviceCommand) { commands.append(command) }
    func count() -> Int { commands.count }
}

private func audioDevice(_ route: String = "route-1", user: String = "account-1",
                         model: String? = "Generic") -> AudioDeviceIdentity {
    .init(routeID: route, vendor: "Test", modelFamily: model, firmware: "1.0",
          transport: .bluetoothSystemRoute, roomID: "room", providerAccountID: user,
          householdID: "home", groupID: nil)
}

private func evidence(_ state: AudioCapabilityState = .supportedVerifiedLocal,
                      mechanism: AudioControlMechanism = .appleSystemMedia) -> AudioCapabilityEvidence {
    .init(mechanism: mechanism, state: state, officialURL: URL(string: "https://example.com/official")!,
          verifiedAt: Date(timeIntervalSince1970: 1_700_000_000), modelScope: ["Generic"],
          firmwareScope: ["1.0"], limitations: [])
}

private func record(_ device: AudioDeviceIdentity, capability: AudioDeviceCapability,
                    state: AudioCapabilityState = .supportedVerifiedLocal,
                    mechanism: AudioControlMechanism = .appleSystemMedia) -> AudioDeviceCapabilityRecord {
    .init(identity: device, capabilities: [capability: evidence(state, mechanism: mechanism)],
          discoveredAt: Date(), policyRevision: "policy-v1")
}

@Suite("Universal audio device control")
struct UniversalAudioDeviceControlTests {
    @Test func genericBluetoothExposesBasicControlWithoutFabricatedDeepEQ() async throws {
        let device = audioDevice(), registry = SpeakerHeadphoneCapabilityRegistry()
        try await registry.upsert(.init(identity: device,
            capabilities: [.volume: evidence(), .play: evidence(), .hardwareEQ: evidence(.unsupportedVerified)],
            discoveredAt: Date(), policyRevision: "v1"))
        _ = try await registry.require(.volume, for: device)
        await #expect(throws: AudioCapabilityRegistryError.unsupported) { try await registry.require(.hardwareEQ, for: device) }
    }

    @Test func airPlayIsPickerHandoffAndNeverClaimsSelection() async throws {
        let device = audioDevice(), registry = SpeakerHeadphoneCapabilityRegistry(), policies = AudioProviderPolicyRegistry()
        try await registry.upsert(record(device, capability: .routeSelect, state: .systemHandoffOnly,
                                         mechanism: .appleSystemPicker))
        let coordinator = UniversalAudioDeviceCoordinator(capabilities: registry, policies: policies, adapters: [])
        let command = AudioDeviceCommand(idempotencyKey: "route", device: device, kind: .showRoutePicker,
                                         numericValue: nil, textValue: nil)
        let result = try await coordinator.execute(command, providerID: "system")
        #expect(result.outcome == .systemHandoffPrepared)
        #expect(result.authoritativeSnapshot == nil)
    }

    @Test func commandRequiresAuthoritativeReadbackAndIsIdempotent() async throws {
        let device = audioDevice(), registry = SpeakerHeadphoneCapabilityRegistry(), policies = AudioProviderPolicyRegistry()
        try await registry.upsert(record(device, capability: .volume))
        let adapter = AudioAdapterFixture(providerID: "official", device: device, volume: 0.35)
        let coordinator = UniversalAudioDeviceCoordinator(capabilities: registry, policies: policies, adapters: [adapter])
        let command = AudioDeviceCommand(idempotencyKey: "volume-35", device: device, kind: .setVolume,
                                         numericValue: 0.35, textValue: nil)
        let first = try await coordinator.execute(command, providerID: "official")
        let second = try await coordinator.execute(command, providerID: "official")
        #expect(first == second)
        #expect(first.outcome == .confirmed)
        #expect(first.authoritativeSnapshot?.volume == 0.35)
        #expect(await adapter.count() == 1)
    }

    @Test func unsafeVolumeAndEQAreRejectedBeforeProviderCall() async throws {
        let device = audioDevice(), registry = SpeakerHeadphoneCapabilityRegistry(), policies = AudioProviderPolicyRegistry()
        try await registry.upsert(record(device, capability: .volume))
        let adapter = AudioAdapterFixture(providerID: "official", device: device)
        let coordinator = UniversalAudioDeviceCoordinator(capabilities: registry, policies: policies, adapters: [adapter])
        let command = AudioDeviceCommand(idempotencyKey: "unsafe", device: device, kind: .setVolume,
                                         numericValue: 1.5, textValue: nil)
        await #expect(throws: AudioControlError.invalidValue) { try await coordinator.execute(command, providerID: "official") }
        #expect(await adapter.count() == 0)
    }

    @Test func AIAndDeterministicCommandsShareTypedValidation() async throws {
        let device = audioDevice(), registry = SpeakerHeadphoneCapabilityRegistry(), policies = AudioProviderPolicyRegistry()
        try await registry.upsert(record(device, capability: .bass))
        try await policies.upsert(.init(providerID: "official", voiceControl: .allowed, rawAudioDSP: .allowed,
                                        commercialUse: .allowed, evidenceURL: URL(string: "https://example.com/policy")!,
                                        effectiveAt: Date(timeIntervalSince1970: 1_700_000_000), revision: "v1"))
        let adapter = AudioAdapterFixture(providerID: "official", device: device)
        let coordinator = UniversalAudioDeviceCoordinator(capabilities: registry, policies: policies, adapters: [adapter])
        let command = AudioDeviceCommand(idempotencyKey: "bass", device: device, kind: .setBass,
                                         numericValue: 2, textValue: nil)
        #expect(try await coordinator.execute(command, providerID: "official", originatedFromAI: true).outcome == .confirmed)
    }

    @Test func AIAndVoiceCannotBypassProviderPolicy() async throws {
        let device = audioDevice(), registry = SpeakerHeadphoneCapabilityRegistry(), policies = AudioProviderPolicyRegistry()
        try await registry.upsert(record(device, capability: .play))
        try await policies.upsert(.init(providerID: "spotify", voiceControl: .prohibited,
                                        rawAudioDSP: .prohibited, commercialUse: .prohibited,
                                        evidenceURL: URL(string: "https://developer.spotify.com/policy")!,
                                        effectiveAt: Date(timeIntervalSince1970: 1_747_267_200), revision: "2025-05-15"))
        let adapter = AudioAdapterFixture(providerID: "spotify", device: device)
        let coordinator = UniversalAudioDeviceCoordinator(capabilities: registry, policies: policies, adapters: [adapter])
        let command = AudioDeviceCommand(idempotencyKey: "spotify-voice", device: device, kind: .play,
                                         numericValue: nil, textValue: nil)
        await #expect(throws: AudioControlError.policyProhibited) {
            try await coordinator.execute(command, providerID: "spotify", originatedFromAI: true)
        }
        #expect(await adapter.count() == 0)
    }

    @Test func capabilityCacheInvalidatesOnDisconnectFirmwareAuthAndPolicyChange() async throws {
        let device = audioDevice(), registry = SpeakerHeadphoneCapabilityRegistry()
        try await registry.upsert(record(device, capability: .volume))
        await registry.invalidate(routeID: device.routeID)
        #expect(await registry.record(for: device) == nil)
        try await registry.upsert(record(device, capability: .volume))
        await registry.invalidate(providerAccountID: "account-1")
        #expect(await registry.record(for: device) == nil)
        try await registry.upsert(record(device, capability: .volume))
        await registry.invalidate(policyRevision: "v2")
        #expect(await registry.record(for: device) == nil)
    }

    @Test func airPodsSystemOnlySettingCannotBecomeDirectSetter() async throws {
        let device = audioDevice(model: "AirPods"), registry = SpeakerHeadphoneCapabilityRegistry()
        try await registry.upsert(record(device, capability: .transparency, state: .systemHandoffOnly,
                                         mechanism: .appHandoff))
        await #expect(throws: AudioCapabilityRegistryError.unsupported) { try await registry.require(.transparency, for: device) }
    }

    @Test func vendorAppFeatureWithoutOfficialEvidenceIsNotCapability() async throws {
        let device = audioDevice(model: "Vendor Earbuds"), registry = SpeakerHeadphoneCapabilityRegistry()
        try await registry.upsert(record(device, capability: .anc, state: .unknown, mechanism: .appHandoff))
        await #expect(throws: AudioCapabilityRegistryError.unsupported) { try await registry.require(.anc, for: device) }
    }

    @Test func assistantDSPIsBoundedReversibleAndOwnedStreamOnly() throws {
        let dsp = UniversalAudioDSP(), samples: [Float] = [-1, -0.5, 0, 0.5, 1]
        #expect(try dsp.process(mono: samples, sampleRate: 44_100, profile: .flat,
                                authorization: .assistantOwned).allSatisfy { abs($0) <= 0.95 })
        #expect(throws: AudioDSPError.unauthorizedStream) {
            try dsp.process(mono: samples, sampleRate: 44_100, profile: .flat,
                            authorization: .externalUnmodifiable)
        }
        let unsafe = AudioDSPProfile(id: "unsafe", lowGainDB: 30, midGainDB: 0, highGainDB: 0,
                                     balance: 0, outputGainDB: 0, limiterCeiling: 1)
        #expect(throws: AudioDSPError.invalidProfile) {
            try dsp.process(mono: samples, sampleRate: 44_100, profile: unsafe, authorization: .assistantOwned)
        }
    }

    @Test func profilesAreScopedAcrossUsersDevicesAndRestart() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "audio.json")
        let firstDevice = audioDevice("one", user: "provider-a"), secondDevice = audioDevice("two", user: "provider-a")
        let profile = SpeakerHeadphoneProfile(id: "night", userID: "user-a", deviceScopeKey: firstDevice.scopeKey,
                                              friendlyName: "Bedroom", roomOrContext: "bedroom", preferredSafeVolume: 0.25,
                                              hardwareSettings: [:], dspProfile: .flat, enabled: true)
        let store = SpeakerHeadphoneProfileStore(fileURL: url)
        try await store.upsert(profile)
        #expect(await store.profile(id: "night", userID: "user-b", device: firstDevice) == nil)
        #expect(await store.profile(id: "night", userID: "user-a", device: secondDevice) == nil)
        let restored = SpeakerHeadphoneProfileStore(fileURL: url)
        #expect(await restored.profile(id: "night", userID: "user-a", device: firstDevice) == profile)
    }

    @Test func deterministicAutomationRampsAndNeverJumpsToUnsafeVolume() {
        let device = audioDevice(), profile = SpeakerHeadphoneProfile(
            id: "car", userID: "user", deviceScopeKey: device.scopeKey, friendlyName: "Car",
            roomOrContext: "car", preferredSafeVolume: 0.9, hardwareSettings: [:], dspProfile: nil, enabled: true)
        let rule = AudioAutomationRule(id: "rule", userID: "user", trigger: .carConnected,
                                       deviceScopeKey: device.scopeKey, profileID: "car", enabled: true,
                                       maximumVolume: 0.6)
        let plan = AudioAutomationEngine().plan(rule: rule, profile: profile, currentVolume: 0.1,
                                                userID: "user", device: device)
        #expect(plan?.targetVolume == 0.6)
        let steps = plan?.rampSteps ?? []
        #expect(zip([0.1] + steps, steps).allSatisfy { abs($1 - $0) <= 0.051 })
    }

    @Test func oneAdapterFailureDoesNotAlterOtherRegistryCapabilities() async throws {
        let one = audioDevice("one"), two = audioDevice("two"), registry = SpeakerHeadphoneCapabilityRegistry()
        try await registry.upsert(record(one, capability: .volume))
        try await registry.upsert(record(two, capability: .play))
        await registry.invalidate(routeID: one.routeID)
        #expect(await registry.record(for: two) != nil)
    }

    @Test func HEOSParserIgnoresAddedFieldsButRequiresOfficialEnvelope() throws {
        let json = #"{"command":"heos://player/get_players","heos":{"result":"success","message":{"pid":"1"},"future":"ignored"},"payload":[{"pid":1,"name":"Kitchen","new_field":"ok"}],"future_root":true}"#.data(using: .utf8)!
        let result = try HEOSForwardCompatibleParser().parse(json: json)
        #expect(result.succeeded)
        #expect(result.command == "heos://player/get_players")
        #expect(result.payload.first?["new_field"] == "ok")
        #expect(throws: HEOSParserError.malformed) { try HEOSForwardCompatibleParser().parse(json: Data("{}".utf8)) }
    }

    @Test func deterministicParserProducesTypedCommandsWithoutAI() {
        let parser = AudioCommandParser()
        #expect(parser.parse("Гучність 35%", knownRooms: []) ==
                .command(kind: .setVolume, numericValue: 0.35, textValue: nil))
        #expect(parser.parse("podcast mode", knownRooms: []) ==
                .command(kind: .applyDSPProfile, numericValue: nil, textValue: "speech"))
        #expect(parser.parse("бас", knownRooms: []) == .clarification("На скільки змінити бас?"))
    }

    @Test func ambiguousRoomProducesOnlyOneNecessaryClarification() {
        #expect(AudioCommandParser().parse("кухня спальня", knownRooms: ["кухня", "спальня"]) ==
                .clarification("Який аудіопристрій обрати?"))
    }
}
