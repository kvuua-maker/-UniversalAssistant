import UIKit
import UniformTypeIdentifiers

private struct InboxItem: Codable {
    let kind: String
    let value: String
    let receivedAt: Date
}

final class ShareViewController: UIViewController {
    nonisolated private static let suite = "group.com.universalassistant.shared"
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
        // A shared photo frequently also conforms to public.file-url. Prefer its
        // semantic type so it cannot be downgraded into an ordinary URL.
        let types: [(UTType, String)] = [
            (.image, "image"), (.url, "url"), (.plainText, "text"),
            (.vCard, "vcard"), (.data, "document")
        ]
        for provider in providers {
            for (type, kind) in types {
                if let value = await load(provider, type: type, kind: kind) {
                    return InboxItem(kind: kind, value: value, receivedAt: .now)
                }
            }
        }
        return nil
    }

    private func load(_ provider: NSItemProvider, type: UTType, kind: String) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier) { item, _ in
                if kind == "image", let data = Self.imageData(from: item) {
                    continuation.resume(returning: Self.persistSharedImage(data))
                } else if let url = item as? URL { continuation.resume(returning: url.absoluteString) }
                else if let text = item as? String { continuation.resume(returning: text) }
                else if let data = item as? Data { continuation.resume(returning: data.base64EncodedString()) }
                else { continuation.resume(returning: nil) }
            }
        }
    }

    nonisolated private static func imageData(from item: NSSecureCoding?) -> Data? {
        if let image = item as? UIImage { return image.jpegData(compressionQuality: 0.92) }
        if let data = item as? Data { return data }
        if let url = item as? URL { return try? Data(contentsOf: url) }
        return nil
    }

    nonisolated private static func persistSharedImage(_ data: Data) -> String? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suite) else { return nil }
        let directory = container.appendingPathComponent("SharedInbox", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("shared-image-\(UUID().uuidString).jpg")
            try data.write(to: destination, options: .atomic)
            return destination.absoluteString
        } catch {
            return nil
        }
    }
}
