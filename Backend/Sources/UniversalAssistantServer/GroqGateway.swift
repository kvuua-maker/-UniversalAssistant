import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Vapor

struct GroqTranscriptionInput: Codable, Equatable, Sendable {
    let requestID: UUID
    let audioBase64: String
    let fileName: String
    let language: String
    let prompt: String?
}

struct GroqTranscriptionOutput: Content, Codable, Equatable, Sendable {
    let requestID: UUID
    let text: String
    let model: String
    let source: String
}

struct GroqSemanticInput: Codable, Equatable, Sendable {
    let requestID: UUID
    let text: String
    let language: String
}

struct GroqSemanticFrame: Content, Codable, Equatable, Sendable {
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

private struct GroqAssertionClientData<Payload: Codable & Sendable>: Codable, Sendable {
    let challengeID: UUID
    let challenge: String
    let operation: String
    let payload: Payload
}

private struct GroqChatResponse: Decodable {
    struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
    let choices: [Choice]
}

private struct GroqTranscriptionResponse: Decodable { let text: String }
private enum GroqGatewayError: Error { case quotaExceeded, invalidResponse }

private actor GroqDailyQuota {
    private var day = Calendar(identifier: .gregorian).startOfDay(for: .now)
    private var audioSeconds = 0.0
    private var semanticRequests = 0
    private let maximumAudioSeconds: Double
    private let maximumSemanticRequests: Int

    init(maximumAudioSeconds: Double, maximumSemanticRequests: Int) {
        self.maximumAudioSeconds = maximumAudioSeconds
        self.maximumSemanticRequests = maximumSemanticRequests
    }

    func reserveAudio(estimatedSeconds: Double, now: Date = .now) throws {
        resetIfNeeded(now)
        guard estimatedSeconds > 0, audioSeconds + estimatedSeconds <= maximumAudioSeconds else { throw GroqGatewayError.quotaExceeded }
        audioSeconds += estimatedSeconds
    }

    func reserveSemantic(now: Date = .now) throws {
        resetIfNeeded(now)
        guard semanticRequests + 1 <= maximumSemanticRequests else { throw GroqGatewayError.quotaExceeded }
        semanticRequests += 1
    }

    private func resetIfNeeded(_ now: Date) {
        let current = Calendar(identifier: .gregorian).startOfDay(for: now)
        if current != day { day = current; audioSeconds = 0; semanticRequests = 0 }
    }
}

private struct GroqAPIClient: Sendable {
    let apiKey: String
    let session: URLSession
    let baseURL: URL

    init(apiKey: String, session: URLSession = .shared, baseURL: URL = URL(string: "https://api.groq.com/openai/v1")!) {
        self.apiKey = apiKey; self.session = session; self.baseURL = baseURL
    }

    func transcribe(_ input: GroqTranscriptionInput) async throws -> GroqTranscriptionOutput {
        guard let audio = Data(base64Encoded: input.audioBase64), !audio.isEmpty, audio.count <= 15_000_000 else { throw GroqGatewayError.invalidResponse }
        let boundary = "ua-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", "whisper-large-v3")
        field("language", input.language)
        field("response_format", "json")
        if let prompt = input.prompt, !prompt.isEmpty { field("prompt", String(prompt.prefix(1_000))) }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(input.fileName)\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var request = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"; request.timeoutInterval = 25; request.httpBody = body
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(GroqTranscriptionResponse.self, from: data) else { throw GroqGatewayError.invalidResponse }
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GroqGatewayError.invalidResponse }
        return .init(requestID: input.requestID, text: text, model: "whisper-large-v3", source: "groq")
    }

    func semantic(_ input: GroqSemanticInput) async throws -> GroqSemanticFrame {
        let nullableString: [String: Any] = ["type": ["string", "null"]]
        let canonicalIntents = [
            "placeSearch", "productSearch", "fashionDiscovery", "groceryBasket", "serviceSearch",
            "restaurantSearch", "reservation", "taxiSearch", "taxiCompare", "navigation", "routeSearch",
            "routeAwareSearch", "calendarCreate", "calendarQuery", "calendarUpdate", "calendarDelete",
            "reminderCreate", "reminderQuery", "reminderComplete", "reminderDelete", "noteCreate", "noteQuery",
            "shoppingList", "contactLookup", "contactCall", "messageCompose", "photoSearch", "fileSearch",
            "cameraCapture", "translation", "musicRecognition", "mediaSearch", "podcastSearch", "parcelTrack",
            "weather", "publicTransport", "transportRoute", "ticketSearch", "ticketPurchaseHandoff", "hotelSearch",
            "travelPlan", "emergency", "webSearch", "deviceAction", "appAction", "audioRecord", "show", "open",
            "cancel", "undo", "localUtility", "currencyConversion", "multiStep", "settings", "help",
            "contextualSelection", "unknown"
        ]
        let properties: [String: Any] = [
            "intent": ["type": "string", "enum": canonicalIntents], "action": nullableString, "channel": nullableString,
            "provider": nullableString, "app": nullableString, "contact": nullableString,
            "entity": nullableString, "brand": nullableString, "product": nullableString,
            "city": nullableString, "date": nullableString, "time": nullableString,
            "quantity": ["type": ["integer", "null"]], "mediaAction": nullableString,
            "query": nullableString, "ambiguous": ["type": "boolean"]
        ]
        let required = ["intent", "action", "channel", "provider", "app", "contact", "entity", "brand", "product", "city", "date", "time", "quantity", "mediaAction", "query", "ambiguous"]
        let schema: [String: Any] = ["name": "universal_assistant_semantic_frame", "strict": true,
            "schema": ["type": "object", "additionalProperties": false, "properties": properties, "required": required]]
        let payload: [String: Any] = [
            "model": "openai/gpt-oss-20b", "temperature": 0, "max_completion_tokens": 800,
            "reasoning_effort": "low",
            "messages": [
                ["role": "system", "content": "Extract only explicit semantic roles. Preserve Ukrainian names, brands, providers, cities and channels verbatim. Never choose or substitute a provider. Return the strict schema only."],
                ["role": "user", "content": input.text]
            ],
            "response_format": ["type": "json_schema", "json_schema": schema]
        ]
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"; request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let response = try? JSONDecoder().decode(GroqChatResponse.self, from: responseData),
              let content = response.choices.first?.message.content.data(using: .utf8) else { throw GroqGatewayError.invalidResponse }
        struct Parsed: Decodable {
            let intent: String; let action: String?; let channel: String?; let provider: String?; let app: String?
            let contact: String?; let entity: String?; let brand: String?; let product: String?; let city: String?
            let date: String?; let time: String?; let quantity: Int?; let mediaAction: String?; let query: String?; let ambiguous: Bool
        }
        let value = try JSONDecoder().decode(Parsed.self, from: content)
        return .init(requestID: input.requestID, intent: value.intent, action: value.action, channel: value.channel,
                     provider: value.provider, app: value.app, contact: value.contact, entity: value.entity,
                     brand: value.brand, product: value.product, city: value.city, date: value.date, time: value.time,
                     quantity: value.quantity, mediaAction: value.mediaAction, query: value.query,
                     ambiguous: value.ambiguous, model: "openai/gpt-oss-20b")
    }
}

extension Application {
    func configureGroqGateway(challenges: ChallengeStore, registrations: AppAttestRegistrationStore, verifier: ProductionAppAttestVerifier) throws {
        let enabled = Environment.get("GROQ_ENABLED")?.lowercased() == "true"
        let key = Environment.get("GROQ_API_KEY") ?? ""
        let audioLimit = Double(Environment.get("GROQ_DAILY_AUDIO_SECONDS") ?? "0") ?? 0
        let semanticLimit = Int(Environment.get("GROQ_DAILY_SEMANTIC_REQUESTS") ?? "0") ?? 0
        let configured = enabled && !key.isEmpty && audioLimit > 0 && semanticLimit > 0
        let client = GroqAPIClient(apiKey: key)
        let quota = GroqDailyQuota(maximumAudioSeconds: audioLimit, maximumSemanticRequests: semanticLimit)
        let rateLimit = PrincipalRateLimiter(policy: .init(maximumRequests: 20, window: 60))

        @Sendable func verifiedPayload<T: Codable & Sendable>(_ request: Request, operation: String, type: T.Type) async throws -> T {
            guard configured else { throw Abort(.serviceUnavailable, reason: "groq_gateway_disabled") }
            guard await rateLimit.allow(subjectID: request.remoteAddress?.description ?? "unknown") else { throw Abort(.tooManyRequests) }
            let body = try request.content.decode(AssertionEnvelope.self)
            guard let assertion = Data(base64Encoded: body.assertion), let clientData = Data(base64Encoded: body.clientData),
                  clientData.count <= 21_000_000, let registration = await registrations.record(for: body.keyID) else { throw Abort(.unauthorized) }
            let decoded: GroqAssertionClientData<T>
            do { decoded = try JSONDecoder().decode(GroqAssertionClientData<T>.self, from: clientData) } catch { throw Abort(.badRequest) }
            let challenge: ChallengeStore.Entry
            do { challenge = try await challenges.consume(id: decoded.challengeID, operation: operation) } catch { throw Abort(.unauthorized) }
            guard decoded.challenge == challenge.value.base64EncodedString(), decoded.operation == operation else { throw Abort(.unauthorized) }
            let counter: Int
            do { counter = try verifier.verifyAssertion(challenge: challenge.value, clientData: clientData, assertion: assertion, publicKey: registration.publicKey) } catch { throw Abort(.unauthorized) }
            do { try await registrations.advanceCounter(keyID: body.keyID, to: counter) } catch { throw Abort(.unauthorized) }
            return decoded.payload
        }

        routes.grouped("v1", "ai").post("transcriptions") { request async throws -> GroqTranscriptionOutput in
            let input = try await verifiedPayload(request, operation: "groq-transcription", type: GroqTranscriptionInput.self)
            guard input.language == "uk", input.fileName.lowercased().hasSuffix(".wav") else { throw Abort(.badRequest) }
            let bytes = Data(base64Encoded: input.audioBase64)?.count ?? 0
            do { try await quota.reserveAudio(estimatedSeconds: max(1, Double(bytes) / 32_000)) } catch { throw Abort(.tooManyRequests, reason: "daily_audio_quota") }
            do { return try await client.transcribe(input) } catch { throw Abort(.badGateway, reason: "groq_transcription_failed") }
        }
        routes.grouped("v1", "ai").post("semantic") { request async throws -> GroqSemanticFrame in
            let input = try await verifiedPayload(request, operation: "groq-semantic", type: GroqSemanticInput.self)
            guard input.language == "uk", !input.text.isEmpty, input.text.utf8.count <= 4_000 else { throw Abort(.badRequest) }
            do { try await quota.reserveSemantic() } catch { throw Abort(.tooManyRequests, reason: "daily_semantic_quota") }
            do { return try await client.semantic(input) } catch { throw Abort(.badGateway, reason: "groq_semantic_failed") }
        }
    }
}
