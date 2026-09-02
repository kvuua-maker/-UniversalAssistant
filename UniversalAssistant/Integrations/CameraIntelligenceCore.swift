import Foundation

enum QRPayloadKind: String, Equatable, Sendable {
    case webURL, payment, contact, wifi, telephone, email, plainText, unknown
}

struct QRPayloadAssessment: Equatable, Sendable {
    let kind: QRPayloadKind
    let normalizedValue: String
    let requiresConfirmation: Bool
    let mayAutoExecute: Bool
}

enum CameraProductEvidence: Equatable, Sendable {
    case exactGTIN(String)
    case probableVisualSimilarity(label: String, confidence: Double)
    case insufficient
}

struct LocalTranslationPlan: Equatable, Sendable {
    let text: String
    let sourceLanguage: String?
    let targetLanguage: String
    let usesLocalOrSystemFramework: Bool
    let narrate: Bool
}

enum CameraIntelligenceError: Error, Equatable, Sendable {
    case emptyPayload, invalidTargetLanguage, invalidConfidence
}

struct CameraIntelligenceCore: Sendable {
    func assessQR(_ rawValue: String) throws -> QRPayloadAssessment {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw CameraIntelligenceError.emptyPayload }
        let lower = value.lowercased()
        let kind: QRPayloadKind
        if lower.hasPrefix("bitcoin:") || lower.hasPrefix("ethereum:") || lower.hasPrefix("upi:") || lower.hasPrefix("payto:") {
            kind = .payment
        } else if lower.hasPrefix("wifi:") {
            kind = .wifi
        } else if lower.hasPrefix("mecard:") || lower.hasPrefix("begin:vcard") {
            kind = .contact
        } else if lower.hasPrefix("tel:") {
            kind = .telephone
        } else if lower.hasPrefix("mailto:") {
            kind = .email
        } else if let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil {
            kind = .webURL
        } else if value.contains(":") {
            kind = .unknown
        } else {
            kind = .plainText
        }
        let sensitive = kind != .plainText
        return .init(kind: kind, normalizedValue: value, requiresConfirmation: sensitive, mayAutoExecute: false)
    }

    func productEvidence(barcode: String?, visualLabel: String?, confidence: Double?) throws -> CameraProductEvidence {
        if let barcode {
            let digits = barcode.filter(\.isNumber)
            if GTINValidator().isValid(digits) { return .exactGTIN(digits) }
        }
        guard let label = visualLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty,
              let confidence else { return .insufficient }
        guard (0...1).contains(confidence) else { throw CameraIntelligenceError.invalidConfidence }
        guard confidence >= 0.5 else { return .insufficient }
        return .probableVisualSimilarity(label: label, confidence: confidence)
    }

    func translationPlan(text: String, sourceLanguage: String?, targetLanguage: String, readAloud: Bool = false) throws -> LocalTranslationPlan {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else { throw CameraIntelligenceError.emptyPayload }
        guard !target.isEmpty else { throw CameraIntelligenceError.invalidTargetLanguage }
        return .init(text: cleanedText, sourceLanguage: sourceLanguage, targetLanguage: target,
                     usesLocalOrSystemFramework: true, narrate: readAloud)
    }
}
