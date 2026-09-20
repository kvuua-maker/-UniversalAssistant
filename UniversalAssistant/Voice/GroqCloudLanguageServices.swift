import Foundation

enum GroqLanguageServiceError: Error, Equatable, Sendable {
    case privacyBlocked
}

protocol CloudVoiceTranscribing: Sendable {
    func transcribe(audioURL: URL, requestID: UUID, prompt: [String]) async throws -> String
}

enum FinalVoiceTranscriptSource: String, Equatable, Sendable {
    case groq
    case appleFallback
}

struct FinalVoiceTranscript: Equatable, Sendable {
    let text: String
    let source: FinalVoiceTranscriptSource
}

enum VoiceAuthoritativeTranscriptSelector {
    static func select(
        groq: String?,
        appleFallback: String,
        appleEvidence: VoiceRecognitionEvidence? = nil
    ) -> FinalVoiceTranscript? {
        let cloud = groq?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var apple = appleFallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if let appleEvidence {
            let stabilized = VoiceTranscriptStabilizer.stabilize(
                appleEvidence,
                contextualVocabulary: CanonicalSpeechEntityRegistry.speechVocabulary
            ).text
            if VoiceDeterministicCommandAssessment(text: stabilized).score > VoiceDeterministicCommandAssessment(text: apple).score {
                apple = stabilized
            }
        }
        if cloud.isEmpty { return apple.isEmpty ? nil : .init(text: apple, source: .appleFallback) }
        if apple.isEmpty { return .init(text: cloud, source: .groq) }

        let cloudEvidence = VoiceDeterministicCommandAssessment(text: cloud)
        let appleEvidence = VoiceDeterministicCommandAssessment(text: apple)
        if let fused = fuseComplementaryRoles(apple: apple, cloud: cloud, appleAssessment: appleEvidence, cloudAssessment: cloudEvidence) {
            let source: FinalVoiceTranscriptSource = cloudEvidence.score > appleEvidence.score ? .groq : .appleFallback
            return .init(text: fused, source: source)
        }
        if cloudEvidence.conflicts(with: appleEvidence) {
            let common = commonPrefix(cloud, apple)
            return common.isEmpty ? nil : .init(text: common, source: .appleFallback)
        }
        if appleEvidence.score > cloudEvidence.score {
            return .init(text: apple, source: .appleFallback)
        }
        if cloudEvidence.score > appleEvidence.score {
            return .init(text: cloud, source: .groq)
        }
        // Equal structured evidence prefers the candidate that preserved more
        // spoken material; an equal-length Apple final avoids a network result
        // replacing equivalent on-device evidence.
        if cloud.split(whereSeparator: \.isWhitespace).count > apple.split(whereSeparator: \.isWhitespace).count {
            return .init(text: cloud, source: .groq)
        }
        return .init(text: apple, source: .appleFallback)
    }

    private static func fuseComplementaryRoles(
        apple: String,
        cloud: String,
        appleAssessment: VoiceDeterministicCommandAssessment,
        cloudAssessment: VoiceDeterministicCommandAssessment
    ) -> String? {
        let appleWords = apple.split(whereSeparator: \.isWhitespace).count
        let cloudWords = cloud.split(whereSeparator: \.isWhitespace).count
        let base = appleWords >= cloudWords ? apple : cloud
        let baseAssessment = appleWords >= cloudWords ? appleAssessment : cloudAssessment
        let other = appleWords >= cloudWords ? cloudAssessment : appleAssessment

        if [.open, .appAction].contains(baseAssessment.command.intent),
           baseAssessment.application == nil, let application = other.application {
            return "\(base) \(application)"
        }
        if [.contactCall, .messageCompose].contains(baseAssessment.command.intent),
           baseAssessment.channel == nil, let channel = other.channel,
           baseAssessment.command.entities["contact"] != nil || baseAssessment.command.entities["recipient"] != nil {
            return "\(base) через \(channel)"
        }
        return nil
    }

    private static func commonPrefix(_ lhs: String, _ rhs: String) -> String {
        let left = lhs.split(whereSeparator: \.isWhitespace).map(String.init)
        let right = rhs.split(whereSeparator: \.isWhitespace).map(String.init)
        var output: [String] = []
        for (a, b) in zip(left, right) {
            guard a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame else { break }
            output.append(a)
        }
        return output.joined(separator: " ")
    }
}

struct VoiceDeterministicCommandAssessment: Sendable {
    let command: StructuredCommand
    let application: String?
    let channel: String?
    let score: Int

    init(text: String) {
        command = CanonicalCurrentCommandRoleNormalizer.apply(to: LanguageUnderstandingBlock().parse(text))
        application = CanonicalSpeechEntityRegistry.applicationID(in: text)
        channel = CanonicalSpeechEntityRegistry.communicationChannel(in: text)
        var value = 0
        if command.intent != .unknown && command.intent != .webSearch { value += 80 }
        if !command.needsClarification { value += 30 }
        if application != nil { value += 45 }
        if channel != nil { value += 45 }
        if command.constraints.brand != nil { value += 30 }
        value += Self.canonicalExplicitEntityCount(in: text) * 25
        if command.entities["explicit_location"] == "true" { value += 20 }
        if command.entities["contact"] != nil || command.entities["recipient"] != nil { value += 15 }
        value += min(20, text.split(whereSeparator: \.isWhitespace).count)
        score = value
    }

    var isResolvedDeterministic: Bool {
        guard !command.needsClarification, command.intent != .unknown, command.intent != .webSearch else { return false }
        switch command.intent {
        case .open, .appAction:
            return command.entities["app"] != nil || application != nil
        case .contactCall:
            return (command.entities["contact"] != nil || command.entities["phone_number"] != nil) &&
                (!Self.hasChannelMarker(text: command.originalText) || channel != nil || command.entities["call_service"] != nil)
        case .messageCompose:
            return (command.entities["recipient"] != nil || command.entities["contact"] != nil) &&
                (!Self.hasChannelMarker(text: command.originalText) || channel != nil || command.entities["message_service"] != nil)
        case .calendarCreate:
            return EventKitCommandArgumentExtractor().extract(command).subject?.isEmpty == false && Self.hasTemporalRole(command)
        case .reminderCreate:
            return EventKitCommandArgumentExtractor().extract(command).subject?.isEmpty == false && Self.hasTemporalRole(command)
        case .localUtility, .calendarQuery, .cameraCapture, .settings, .deviceAction,
             .reminderQuery, .audioRecord, .fileSearch:
            return true
        default:
            return false
        }
    }

    private static func hasChannelMarker(text: String) -> Bool {
        let tokens = text.lowercased().split { !$0.isLetter }.map(String.init)
        return tokens.contains(where: { ["через", "via", "using"].contains($0) }) ||
            CanonicalSpeechEntityRegistry.communicationChannel(in: text) != nil
    }

    /// Scores only canonical names/aliases that are actually present in this
    /// transcript. It never promotes acoustic context fragments into entities.
    private static func canonicalExplicitEntityCount(in text: String) -> Int {
        let normalized = " " + comparablePhrase(text) + " "
        return CanonicalCatalogEntityRegistry.candidates.reduce(into: 0) { count, candidate in
            let evidence = candidate.aliases.union([candidate.displayName])
            if evidence.contains(where: {
                let alias = comparablePhrase($0)
                return !alias.isEmpty && normalized.contains(" \(alias) ")
            }) {
                count += 1
            }
        }
    }

    private static func comparablePhrase(_ value: String) -> String {
        value.split { !$0.isLetter && !$0.isNumber }
            .map { CanonicalMorphology.comparableText(String($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func hasTemporalRole(_ command: StructuredCommand) -> Bool {
        ["relative_day_offset", "relative_interval_seconds", "calendar_day", "weekday", "hour"]
            .contains(where: { command.entities[$0] != nil })
    }

    func conflicts(with other: Self) -> Bool {
        if let application, let otherApplication = other.application, application != otherApplication { return true }
        if let channel, let otherChannel = other.channel, channel != otherChannel { return true }
        if let brand = command.constraints.brand, let otherBrand = other.command.constraints.brand,
           brand.caseInsensitiveCompare(otherBrand) != .orderedSame { return true }
        return false
    }
}

struct GroqCloudVoiceTranscriber: CloudVoiceTranscribing {
    private struct Input: Codable, Sendable {
        let requestID: UUID
        let audioBase64: String
        let fileName: String
        let language: String
        let prompt: String?
    }
    private struct Output: Decodable {
        let requestID: UUID
        let text: String
        let model: String
        let source: String
    }

    func transcribe(audioURL: URL, requestID: UUID, prompt: [String]) async throws -> String {
        let audio = try Data(contentsOf: audioURL, options: [.mappedIfSafe])
        guard !audio.isEmpty, audio.count <= 15_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
        let context = prompt.prefix(80).joined(separator: ", ")
        let result: Output = try await PhysicalDiagnosticDelivery.shared.postAttested(
            operation: "groq-transcription",
            path: "v1/ai/transcriptions",
            payload: Input(
                requestID: requestID,
                audioBase64: audio.base64EncodedString(),
                fileName: "\(requestID.uuidString.lowercased()).wav",
                language: "uk",
                prompt: context.isEmpty ? nil : context
            ),
            response: Output.self
        )
        guard result.requestID == requestID, result.source == "groq", result.model == "whisper-large-v3" else {
            throw URLError(.cannotParseResponse)
        }
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw URLError(.zeroByteResource) }
        return text
    }
}

struct CloudSemanticFrame: Codable, Equatable, Sendable {
    let requestID: UUID
    let intent: String
    let action: String?
    let channel: String?
    let provider: String?
    let app: String?
    let contact: String?
    let entity: String?
    let brand: String?
    let product: String?
    let city: String?
    let date: String?
    let time: String?
    let quantity: Int?
    let mediaAction: String?
    let query: String?
    let ambiguous: Bool
    let model: String
}

protocol CloudSemanticUnderstanding: Sendable {
    func interpret(_ text: String, requestID: UUID) async throws -> CloudSemanticFrame
}

protocol SemanticCommandResolving: Sendable {
    func resolveCommand(_ text: String, language: CommandLanguage) async throws -> StructuredCommand
}

struct GroqSemanticCommandResolver: SemanticCommandResolving {
    let generic: GroqGenericIntentResolver

    init(
        engine: any CloudSemanticUnderstanding = GroqCloudSemanticEngine(),
        privacyGate: PrivacyOutboundGate = .init(),
        timeout: Duration = .seconds(5)
    ) {
        generic = .init(engine: engine, privacyGate: privacyGate, timeout: timeout)
    }

    func resolveCommand(_ text: String, language: CommandLanguage) async throws -> StructuredCommand {
        let frame = try await generic.semanticFrame(for: text)
        let currentEvidence = CanonicalCurrentCommandRoleNormalizer.apply(to: LanguageUnderstandingBlock().parse(text))
        guard let intent = CommandIntent(rawValue: frame.intent), intent != .unknown else {
            throw GenericDiscoveryError.invalidIntent
        }
        var entities: [String: String] = [:]
        if let action = frame.action { entities["action"] = action }
        if let app = CanonicalSpeechEntityRegistry.applicationID(in: text) { entities["app"] = app }
        if let contact = currentEvidence.entities[intent == .messageCompose ? "recipient" : "contact"] {
            entities[intent == .messageCompose ? "recipient" : "contact"] = contact
        }
        if let entity = frame.entity { entities["query"] = entity }
        if let product = frame.product { entities["query"] = product }
        if currentEvidence.entities["explicit_location"] == "true",
           let city = currentEvidence.entities["location"] {
            entities["location"] = city; entities["explicit_location"] = "true"
        }
        if let date = frame.date { entities["date_expression"] = date }
        if let time = frame.time { entities["time_expression"] = time }
        if let quantity = frame.quantity {
            entities[intent == .reservation ? "party_size" : "quantity"] = String(quantity)
        }
        if let mediaAction = frame.mediaAction { entities["media_action"] = mediaAction }
        if let query = frame.query, entities["query"] == nil { entities["query"] = query }
        if let provider = Self.explicitProvider(in: text) {
            entities["explicit_provider_id"] = provider
            entities["provider_id"] = provider
        }
        if [.contactCall, .messageCompose].contains(intent),
           let channel = Self.explicitChannel(in: text) {
            entities[intent == .contactCall ? "call_service" : "message_service"] = channel
            entities["explicit_channel"] = channel
        }
        var constraints = CommandConstraints()
        if let brand = Self.explicitBrand(in: text) {
            constraints.brand = brand
            constraints.hardConstraintKeys.insert("brand")
            entities["brand"] = brand
        }
        let risk: ActionRisk = switch intent {
        case .calendarCreate, .calendarUpdate, .calendarDelete, .reminderCreate,
             .reminderComplete, .reminderDelete, .contactCall, .messageCompose,
             .ticketPurchaseHandoff: .consequential
        case .audioRecord, .deviceAction, .settings: .reversible
        case .emergency: .emergency
        default: .informational
        }
        let command = StructuredCommand(
            originalText: text,
            normalizedText: text.lowercased(with: Locale(identifier: "uk_UA")),
            language: language,
            intent: intent,
            entities: entities,
            constraints: constraints,
            risk: risk,
            needsClarification: frame.ambiguous
        )
        return CanonicalCurrentCommandRoleNormalizer.apply(to: command)
    }

    private static func explicitBrand(in text: String) -> String? {
        CanonicalCatalogEntityRegistry.brandNames.first {
            text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private static func explicitProvider(in text: String) -> String? {
        OfficialPublicProviderHandoffRegistry.records.first { provider in
            ([provider.displayName, provider.id] + provider.aliases).contains {
                text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }?.id
    }

    private static func explicitChannel(in text: String) -> String? {
        CanonicalSpeechEntityRegistry.communicationChannel(in: text)
    }
}

struct GroqCloudSemanticEngine: CloudSemanticUnderstanding {
    private struct Input: Codable, Sendable { let requestID: UUID; let text: String; let language: String }
    func interpret(_ text: String, requestID: UUID) async throws -> CloudSemanticFrame {
        let result: CloudSemanticFrame = try await PhysicalDiagnosticDelivery.shared.postAttested(
            operation: "groq-semantic",
            path: "v1/ai/semantic",
            payload: Input(requestID: requestID, text: text, language: "uk"),
            response: CloudSemanticFrame.self
        )
        guard result.requestID == requestID, result.model == "openai/gpt-oss-20b" else { throw URLError(.cannotParseResponse) }
        return result
    }
}

struct GroqGenericIntentResolver: GenericAIIntentResolver {
    let engine: any CloudSemanticUnderstanding
    let privacyGate: PrivacyOutboundGate
    let timeout: Duration

    init(
        engine: any CloudSemanticUnderstanding = GroqCloudSemanticEngine(),
        privacyGate: PrivacyOutboundGate = .init(),
        timeout: Duration = .seconds(5)
    ) {
        self.engine = engine
        self.privacyGate = privacyGate
        self.timeout = timeout
    }

    func resolve(_ text: String) async throws -> GenericIntent {
        let frame = try await semanticFrame(for: text)
        let domain = Self.domain(for: frame.intent)
        var result = GenericIntent(
            domain: domain,
            subject: frame.product ?? frame.entity ?? frame.query ?? text,
            goal: frame.action ?? "find"
        )
        if let city = frame.city { result.location = .init(locality: city, nearCurrentLocation: false) }
        result.quantity = frame.quantity
        // Model output can enrich an unresolved command, but it cannot replace
        // a provider or brand explicitly present in the current user text.
        result.brandOrProvider = Self.explicitProvider(in: text) ?? Self.explicitBrand(in: text)
        result.requestedAction = ["open", "show", "find", "search", nil].contains(frame.action) ? "open" : frame.action
        result.requiredFreshness = ["jobs", "events", "local_service", "restaurant"].contains(domain) ? 86_400 : 604_800
        result.metadata = [
            "semantic_model": frame.model,
            "explicit_channel": CanonicalSpeechEntityRegistry.communicationChannel(in: text),
            "explicit_provider": Self.explicitProvider(in: text),
            "explicit_app": CanonicalSpeechEntityRegistry.applicationID(in: text),
            "explicit_date": frame.date,
            "explicit_time": frame.time,
            "media_action": frame.mediaAction
        ].compactMapValues { $0 }
        return try result.validated()
    }

    func semanticFrame(for text: String) async throws -> CloudSemanticFrame {
        let privacy = try privacyGate.evaluate(.init(
            destination: .ai(providerID: "groq-semantic"),
            purpose: "semantic_interpretation",
            fields: [.init(
                id: "request-text", name: "request_text", value: text,
                classification: .personal, purpose: "semantic_interpretation",
                requiredForSemantics: true
            )],
            consent: .granted,
            permittedPurposes: ["semantic_interpretation"],
            maxPersonalFields: 1,
            contentTrust: .trustedLocal
        ))
        guard let permittedValue = privacy.allowedFields.first?.value else {
            throw GroqLanguageServiceError.privacyBlocked
        }
        let permittedText = privacyGate.sanitizeUntrustedContent(permittedValue)
        guard
              !permittedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GenericDiscoveryError.allSourcesFailed
        }
        let frame = try await interpretOnce(permittedText, requestID: UUID())
        guard !frame.ambiguous else { throw GenericDiscoveryError.ambiguous("Потрібне одне уточнення") }
        LocalVoiceDiagnosticReport.shared.record(
            "semantic_engine_result",
            "engine=groq model=\(frame.model) intent=\(frame.intent) schema=valid"
        )
        return frame
    }

    private func interpretOnce(_ text: String, requestID: UUID) async throws -> CloudSemanticFrame {
        let engine = engine
        let timeout = timeout
        return try await withThrowingTaskGroup(of: CloudSemanticFrame.self) { group in
            group.addTask { try await engine.interpret(text, requestID: requestID) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw URLError(.timedOut)
            }
            guard let first = try await group.next() else { throw URLError(.timedOut) }
            group.cancelAll()
            return first
        }
    }

    private static func explicitBrand(in text: String) -> String? {
        CanonicalCatalogEntityRegistry.brandNames.first { brand in
            text.range(of: brand, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private static func explicitProvider(in text: String) -> String? {
        OfficialPublicProviderHandoffRegistry.records.first { provider in
            ([provider.displayName, provider.id] + provider.aliases).contains { name in
                text.range(of: name, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }?.id
    }

    private static func domain(for intent: String) -> String {
        switch CommandIntent(rawValue: intent) {
        case .hotelSearch: "accommodation"
        case .ticketSearch, .ticketPurchaseHandoff: "events"
        case .serviceSearch: "local_service"
        case .restaurantSearch, .reservation: "restaurant"
        case .productSearch, .fashionDiscovery, .groceryBasket: "shopping"
        case .parcelTrack: "delivery"
        default: "general"
        }
    }
}
