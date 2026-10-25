import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Vapor

/// Token-authenticated AI routes used by the iOS client while App Attest is
/// being fixed. The token is a shared secret from the environment; it is a
/// deliberate, time-boxed trade-off for TestFlight and must be replaced by
/// attestation before release.
struct TokenTranscribeInput: Content {
    let requestID: UUID
    let audioBase64: String
    let fileName: String
    let language: String
    let prompt: String?
}

struct TokenTranscribeOutput: Content {
    let requestID: UUID
    let text: String
    let model: String
    let source: String
}

struct TokenInterpretInput: Content {
    let requestID: UUID
    let text: String
    let language: String
}

struct TokenInterpretOutput: Content {
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

private func requireToken(_ request: Request) throws {
    guard let expected = Environment.get("UA_AI_TOKEN"), !expected.isEmpty else {
        throw Abort(.serviceUnavailable, reason: "ai_token_not_configured")
    }
    guard request.headers.first(name: "X-UA-Token") == expected else {
        throw Abort(.unauthorized, reason: "invalid_token")
    }
}

extension Application {
    func configureTokenAIRoutes() throws {
        let apiKey = Environment.get("GROQ_API_KEY") ?? ""
        let enabled = (Environment.get("GROQ_ENABLED") ?? "false").lowercased() == "true"

        post("v1", "ai", "transcribe") { request async throws -> TokenTranscribeOutput in
            try requireToken(request)
            guard enabled, !apiKey.isEmpty else { throw Abort(.serviceUnavailable, reason: "groq_disabled") }
            let body = try request.content.decode(TokenTranscribeInput.self)
            guard body.language == "uk" || body.language == "en" else { throw Abort(.badRequest, reason: "unsupported_language") }
            guard let audio = Data(base64Encoded: body.audioBase64), !audio.isEmpty, audio.count <= 15_000_000 else {
                throw Abort(.badRequest, reason: "invalid_audio")
            }

            let boundary = "UA-\(UUID().uuidString)"
            var multipart = Data()
            func field(_ name: String, _ value: String) {
                multipart.append("--\(boundary)\r\n".data(using: .utf8)!)
                multipart.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
                multipart.append("\(value)\r\n".data(using: .utf8)!)
            }
            field("model", "whisper-large-v3")
            field("language", body.language)
            field("response_format", "json")
            if let prompt = body.prompt, !prompt.isEmpty { field("prompt", String(prompt.prefix(900))) }
            multipart.append("--\(boundary)\r\n".data(using: .utf8)!)
            multipart.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(body.fileName)\"\r\n".data(using: .utf8)!)
            multipart.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
            multipart.append(audio)
            multipart.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

            var urlRequest = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = multipart
            urlRequest.timeoutInterval = 25
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw Abort(.badGateway, reason: "groq_transcription_failed")
            }
            struct GroqResponse: Decodable { let text: String }
            let decoded = try JSONDecoder().decode(GroqResponse.self, from: data)
            let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw Abort(.badGateway, reason: "empty_transcription") }
            return .init(requestID: body.requestID, text: text, model: "whisper-large-v3", source: "groq")
        }

        post("v1", "ai", "interpret") { request async throws -> TokenInterpretOutput in
            try requireToken(request)
            guard enabled, !apiKey.isEmpty else { throw Abort(.serviceUnavailable, reason: "groq_disabled") }
            let body = try request.content.decode(TokenInterpretInput.self)
            guard body.text.utf8.count <= 4000 else { throw Abort(.badRequest, reason: "text_too_long") }

            let system = """
            Ти — парсер команд для iOS-асистента. Поверни ЛИШЕ JSON.
            Дозволені intent: open, call, message, search, navigation, weather, music, photo, unknown.
            Виправляй помилки розпізнавання: "теле гімн"/"телега" -> telegram, "вай бєр"/"вайбер" -> viber,
            "вотсап"/"ватсап" -> whatsapp, "пошта" -> mail, "музика" -> music.
            Схема: {"intent":"open","app":"telegram","ambiguous":false}
            Поля: intent, app, contact, query, city, product, provider, channel, action, ambiguous.
            """
            var urlRequest = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.timeoutInterval = 15
            let payload: [String: Any] = [
                "model": "openai/gpt-oss-120b",
                "temperature": 0,
                "max_completion_tokens": 400,
                "response_format": ["type": "json_object"],
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": body.text]
                ]
            ]
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw Abort(.badGateway, reason: "groq_interpretation_failed")
            }
            struct GroqChat: Decodable {
                struct Choice: Decodable { let message: Message }
                struct Message: Decodable { let content: String }
                let choices: [Choice]
            }
            let chat = try JSONDecoder().decode(GroqChat.self, from: data)
            guard let content = chat.choices.first?.message.content,
                  let frameData = content.data(using: .utf8),
                  let frame = try? JSONSerialization.jsonObject(with: frameData) as? [String: Any] else {
                throw Abort(.badGateway, reason: "invalid_model_output")
            }
            func str(_ key: String) -> String? { frame[key] as? String }
            return .init(
                requestID: body.requestID,
                intent: str("intent") ?? "unknown",
                action: str("action"), channel: str("channel"), provider: str("provider"),
                app: str("app"), contact: str("contact"), entity: str("entity"),
                brand: str("brand"), product: str("product"), city: str("city"),
                date: str("date"), time: str("time"),
                quantity: frame["quantity"] as? Int,
                mediaAction: str("mediaAction"), query: str("query"),
                ambiguous: (frame["ambiguous"] as? Bool) ?? false,
                model: "openai/gpt-oss-120b")
        }
    }
}
