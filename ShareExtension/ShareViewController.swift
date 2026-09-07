import UIKit
import UniformTypeIdentifiers

private struct InboxItem: Codable {
    let kind: String
    let value: String
    let receivedAt: Date
}

final class ShareViewController: UIViewController {
    private static let suite = "group.com.universalassistant.shared"
    private static let key = "pending-share-v1"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        Task { await receive() }
    }

    private func receive() async {
        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }.flatMap { $0.attachments ?? [] } ?? []
        let accepted = await firstSupported(in: providers)
        guard let accepted,
              let defaults = UserDefaults(suiteName: Self.suite),
              let data = try? JSONEncoder().encode(accepted) else {
            extensionContext?.cancelRequest(withError: NSError(
                domain: "UniversalAssistantShare", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported shared content"]))
            return
        }
        defaults.set(data, forKey: Self.key)
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func firstSupported(in providers: [NSItemProvider]) async -> InboxItem? {
        let types: [(UTType, String)] = [
            (.url, "url"), (.plainText, "text"), (.vCard, "vcard"),
            (.image, "image"), (.data, "document")
        ]
        for provider in providers {
            for (type, kind) in types {
                if let value = await load(provider, type: type) {
                    return InboxItem(kind: kind, value: value, receivedAt: .now)
                }
            }
        }
        return nil
    }

    private func load(_ provider: NSItemProvider, type: UTType) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier) { item, _ in
                if let url = item as? URL { continuation.resume(returning: url.absoluteString) }
                else if let text = item as? String { continuation.resume(returning: text) }
                else if let image = item as? UIImage, let data = image.jpegData(compressionQuality: 0.95) { continuation.resume(returning: data.base64EncodedString()) }
                else if let data = item as? Data { continuation.resume(returning: data.base64EncodedString()) }
                else { continuation.resume(returning: nil) }
            }
        }
    }
}
