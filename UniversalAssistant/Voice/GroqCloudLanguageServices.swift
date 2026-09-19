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
    static func select(groq: String?, appleFallback: String) -> FinalVoiceTranscript? {
        let cloud = groq?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cloud.isEmpty { return .init(text: cloud, source: .groq) }
        let apple = appleFallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apple.isEmpty else { return nil }
        return .init(text: apple, source: .appleFallback)
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
        guard let intent = CommandIntent(rawValue: frame.intent), intent != .unknown else {
            throw GenericDiscoveryError.invalidIntent
        }
        var entities: [String: String] = [:]
        if let action = frame.action { entities["action"] = action }
        if let app = frame.app { entities["app"] = app }
        if let contact = frame.contact {
            entities[intent == .messageCompose ? "recipient" : "contact"] = contact
        }
        if let entity = frame.entity { entities["query"] = entity }
        if let product = frame.product { entities["query"] = product }
        if let city = frame.city { entities["location"] = city; entities["explicit_location"] = "true" }
        if let date = frame.date { entities["date_expression"] = date }
        if let time = frame.time { entities["time_expression"] = time }
        if let quantity = frame.quantity {
            entities[intent == .reservation ? "party_size" : "quantity"] = String(quantity)
        }
        if let mediaAction = frame.mediaAction { entities["media_action"] = mediaAction }
        if let query = frame.query, entities["query"] == nil { entities["query"] = query }
        if let provider = Self.explicitProvider(in: text) ?? frame.provider {
            entities["explicit_provider_id"] = provider
            entities["provider_id"] = provider
        }
        if let channel = Self.explicitChannel(in: text) ?? frame.channel {
            entities[intent == .contactCall ? "call_service" : "message_service"] = channel
            entities["explicit_channel"] = channel
        }
        var constraints = CommandConstraints()
        if let brand = Self.explicitBrand(in: text) ?? frame.brand {
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
        return ExplicitCurrentCommandPolicy.apply(to: command)
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
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "uk_UA"))
        let values: [(String, [String])] = [
            ("whatsapp", ["whatsapp", "ватсап", "вотсап"]),
            ("viber", ["viber", "вайбер", "вібер"]),
            ("telegram", ["telegram", "телеграм"]),
            ("email", ["email", "пошта", "почта"]),
            ("telephone", ["телефон", "phone", "cellular"])
        ]
        return values.first { $0.1.contains(where: normalized.contains) }?.0
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
        result.brandOrProvider = Self.explicitProvider(in: text)
            ?? Self.explicitBrand(in: text)
            ?? frame.provider
            ?? frame.brand
        result.requestedAction = ["open", "show", "find", "search", nil].contains(frame.action) ? "open" : frame.action
        result.requiredFreshness = ["jobs", "events", "local_service", "restaurant"].contains(domain) ? 86_400 : 604_800
        result.metadata = [
            "semantic_model": frame.model,
            "explicit_channel": frame.channel,
            "explicit_provider": frame.provider,
            "explicit_app": frame.app,
            "explicit_city": frame.city,
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
