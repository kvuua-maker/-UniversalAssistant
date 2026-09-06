import Foundation
import Contacts
#if canImport(UIKit)
import UIKit
#endif

enum SharedContent: Equatable, Sendable {
    case url(URL)
    case text(String)
    case imageReference(String)
    case document(URL)
    case location(latitude: Double, longitude: Double)
    case vCard(Data)
    case retailBarcode(String)
}

enum SharedContentAction: String, Equatable, Sendable {
    case open, remind, findCheaper, route, save, searchNearby, call, importContact, identifyProduct
}

struct SharedContentRoute: Equatable, Sendable {
    let content: SharedContent
    let action: SharedContentAction
    let requiresConfirmation: Bool
    let reason: String
}

enum SharedContentRoutingError: Error, Equatable, Sendable {
    case unsupportedAction, invalidPayload, clipboardUnavailable
}

struct SharedContentActionRouter: Sendable {
    func route(_ content: SharedContent, requested action: SharedContentAction) throws -> SharedContentRoute {
        let allowed: Set<SharedContentAction>
        switch content {
        case .url: allowed = [.open, .remind, .findCheaper, .save]
        case .text: allowed = [.remind, .save, .searchNearby, .call, .findCheaper]
        case .imageReference, .document: allowed = [.save, .remind, .findCheaper]
        case .location: allowed = [.route, .save, .searchNearby]
        case .vCard: allowed = [.importContact, .call, .save]
        case .retailBarcode: allowed = [.identifyProduct, .findCheaper]
        }
        guard allowed.contains(action) else { throw SharedContentRoutingError.unsupportedAction }
        let confirmation = [.open, .route, .call, .importContact].contains(action)
        return .init(content: content, action: action, requiresConfirmation: confirmation,
                     reason: "user_initiated_shared_content")
    }

    func routeQR(_ value: String) throws -> SharedContentRoute {
        let assessment = try CameraIntelligenceCore().assessQR(value)
        switch assessment.kind {
        case .webURL:
            guard let url = URL(string: assessment.normalizedValue) else { throw SharedContentRoutingError.invalidPayload }
            return try route(.url(url), requested: .open)
        case .contact:
            guard let data = assessment.normalizedValue.data(using: .utf8),
                  let contacts = try? CNContactVCardSerialization.contacts(with: data), !contacts.isEmpty
            else { throw SharedContentRoutingError.invalidPayload }
            return try route(.vCard(data), requested: .importContact)
        case .telephone:
            return try route(.text(assessment.normalizedValue), requested: .call)
        case .payment:
            throw SharedContentRoutingError.unsupportedAction
        case .wifi, .email:
            let safe = try route(.text(assessment.normalizedValue), requested: .save)
            return .init(content: safe.content, action: safe.action, requiresConfirmation: true, reason: safe.reason)
        case .plainText:
            return try route(.text(assessment.normalizedValue), requested: .save)
        case .unknown:
            throw SharedContentRoutingError.unsupportedAction
        }
    }

    func routeRetailBarcode(_ rawValue: String) throws -> SharedContentRoute {
        guard case let .exactGTIN(gtin) = try CameraIntelligenceCore()
            .productEvidence(barcode: rawValue, visualLabel: nil, confidence: nil)
        else { throw SharedContentRoutingError.invalidPayload }
        return try route(.retailBarcode(gtin), requested: .identifyProduct)
    }
}

@MainActor
protocol UserInitiatedClipboardReading {
    func readAfterUserAction() throws -> SharedContent
}

#if canImport(UIKit)
@MainActor
struct SystemUserInitiatedClipboardReader: UserInitiatedClipboardReading {
    func readAfterUserAction() throws -> SharedContent {
        let pasteboard = UIPasteboard.general
        if let url = pasteboard.url { return .url(url) }
        if let text = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return .text(text)
        }
        throw SharedContentRoutingError.clipboardUnavailable
    }
}
#endif
