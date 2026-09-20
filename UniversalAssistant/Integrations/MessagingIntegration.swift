import Foundation
import MessageUI
import SwiftUI

enum MessengerKind: String, CaseIterable, Sendable { case messages, whatsapp, telegram, viber, signal }
enum MessengerCapability: String, CaseIterable, Sendable { case find, openChat, compose, send, call, searchHistory, appIntent, deepLink, api }

struct MessengerCapabilityEvidence: Equatable, Sendable {
    let messenger: MessengerKind
    let supported: Set<MessengerCapability>
    let userConfirmationRequired: Bool
    let limitation: String
}

enum MessagingDestination: Equatable, Sendable {
    case systemComposer(recipients: [String], body: String?)
    case verifiedHandoff(URL)
    case unavailable(reason: String)
}

enum MessagingPlanningError: Error, Equatable { case invalidRecipient, invalidContext }

struct MessengerHandoffPlanner: Sendable {
    static let evidence: [MessengerCapabilityEvidence] = [
        .init(messenger: .messages, supported: [.compose], userConfirmationRequired: true,
              limitation: "Public MessageUI composes SMS/iMessage; no inbox/history API and the user sends."),
        .init(messenger: .whatsapp, supported: [.openChat, .compose, .deepLink], userConfirmationRequired: true,
              limitation: "Official click-to-chat handoff; no consumer history access or silent send."),
        .init(messenger: .telegram, supported: [.openChat, .compose, .deepLink], userConfirmationRequired: true,
              limitation: "Public username/share links; no consumer history access or silent send."),
        .init(messenger: .viber, supported: [.compose, .deepLink], userConfirmationRequired: true,
              limitation: "Verified consumer viber://forward share chooser only; no public direct personal-contact addressing, history access, or silent send."),
        .init(messenger: .signal, supported: [], userConfirmationRequired: true,
              limitation: "No verified public consumer automation contract is claimed; use system share/compose when user selects Signal.")
    ]

    func plan(messenger: MessengerKind, recipient: String?, body: String?) throws -> MessagingDestination {
        let cleanBody = body?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch messenger {
        case .messages:
            let recipients = try recipient.map { [try phone($0)] } ?? []
            return .systemComposer(recipients: recipients, body: cleanBody)
        case .whatsapp:
            guard let recipient else { throw MessagingPlanningError.invalidRecipient }
            var components = URLComponents(string: "https://wa.me/\(try phone(recipient))")!
            if let cleanBody, !cleanBody.isEmpty { components.queryItems = [.init(name: "text", value: cleanBody)] }
            return .verifiedHandoff(components.url!)
        case .telegram:
            if let recipient {
                var components = URLComponents(string: "tg://resolve")!
                let digits = recipient.filter(\.isNumber)
                if digits.count >= 7 {
                    components.queryItems = [.init(name: "phone", value: recipient.hasPrefix("+") ? "+" + digits : digits)]
                } else {
                    let username = recipient.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
                    guard !username.isEmpty, username.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { throw MessagingPlanningError.invalidRecipient }
                    components.queryItems = [.init(name: "domain", value: username)]
                }
                if let cleanBody, !cleanBody.isEmpty { components.queryItems?.append(.init(name: "text", value: cleanBody)) }
                return .verifiedHandoff(components.url!)
            }
            guard let cleanBody, !cleanBody.isEmpty else { throw MessagingPlanningError.invalidContext }
            var components = URLComponents(string: "https://t.me/share/url")!
            components.queryItems = [.init(name: "url", value: ""), .init(name: "text", value: cleanBody)]
            return .verifiedHandoff(components.url!)
        case .viber:
            guard let cleanBody, !cleanBody.isEmpty else {
                return .verifiedHandoff(URL(string: "viber://")!)
            }
            var components = URLComponents(string: "viber://forward")!
            components.queryItems = [.init(name: "text", value: cleanBody)]
            return .verifiedHandoff(components.url!)
        case .signal:
            return .unavailable(reason: "use_system_share_sheet_to_choose_signal")
        }
    }

    private func phone(_ input: String) throws -> String {
        let digits = input.filter(\.isNumber)
        guard (7...15).contains(digits.count) else { throw MessagingPlanningError.invalidRecipient }
        return digits
    }
}

struct SystemMessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String?
    let completion: @MainActor (MessageComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        LocalVoiceDiagnosticReport.shared.recordBoundaryPre("MESSAGE_COMPOSE", "mechanism=MessageUI")
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients; controller.body = body
        controller.messageComposeDelegate = context.coordinator
        LocalVoiceDiagnosticReport.shared.recordBoundaryPost("MESSAGE_COMPOSE", "mechanism=MessageUI status=presented")
        return controller
    }
    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    @MainActor final class Coordinator: NSObject, @preconcurrency MFMessageComposeViewControllerDelegate {
        let completion: @MainActor (MessageComposeResult) -> Void
        init(completion: @escaping @MainActor (MessageComposeResult) -> Void) { self.completion = completion }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            completion(result)
            controller.dismiss(animated: true)
        }
    }
}

struct SystemMailComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String?
    let body: String?
    let completion: @MainActor (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.setToRecipients(recipients)
        if let subject { controller.setSubject(subject) }
        if let body { controller.setMessageBody(body, isHTML: false) }
        controller.mailComposeDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    @MainActor final class Coordinator: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
        let completion: @MainActor (MFMailComposeResult) -> Void
        init(completion: @escaping @MainActor (MFMailComposeResult) -> Void) { self.completion = completion }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            completion(result)
            controller.dismiss(animated: true)
        }
    }
}
