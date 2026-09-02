import Foundation
import SwiftUI
import UIKit

enum AppleSystemDomain: String, CaseIterable, Sendable {
    case mail, messages, calendar, reminders, phone, photos, files, notes, maps, camera, clock, audio, search
}

struct AppleSystemDomainEvidence: Equatable, Sendable {
    let domain: AppleSystemDomain
    let deepestPublicBehavior: String
    let implemented: Bool
    let limitation: String?
}

enum AppleSystemDomainAudit {
    static let evidence: [AppleSystemDomainEvidence] = [
        .init(domain: .mail, deepestPublicBehavior: "system compose/share plus connected EmailProvider APIs", implemented: true, limitation: "No public Apple Mail inbox database API"),
        .init(domain: .messages, deepestPublicBehavior: "MessageUI user-confirmed compose", implemented: true, limitation: "No public SMS/iMessage history API"),
        .init(domain: .calendar, deepestPublicBehavior: "EventKit CRUD/query/undo", implemented: true, limitation: nil),
        .init(domain: .reminders, deepestPublicBehavior: "EventKit CRUD/query/undo", implemented: true, limitation: nil),
        .init(domain: .phone, deepestPublicBehavior: "validated contact/tel handoff with confirmation policy", implemented: true, limitation: "No private call control"),
        .init(domain: .photos, deepestPublicBehavior: "PhotoKit permitted metadata search", implemented: true, limitation: "No access to Photos private semantic index"),
        .init(domain: .files, deepestPublicBehavior: "document picker and authorized security-scoped search", implemented: true, limitation: "No global filesystem access"),
        .init(domain: .notes, deepestPublicBehavior: "assistant-owned notes and system share handoff", implemented: true, limitation: "No public Apple Notes database API"),
        .init(domain: .maps, deepestPublicBehavior: "MapKit search/routes and exact public handoff", implemented: true, limitation: nil),
        .init(domain: .camera, deepestPublicBehavior: "user-visible in-app camera capture", implemented: true, limitation: "No private Camera.app control"),
        .init(domain: .clock, deepestPublicBehavior: "truthful unavailable result", implemented: true, limitation: "No general public iOS timer/alarm creation API for this app target"),
        .init(domain: .audio, deepestPublicBehavior: "MusicKit authorization/search/managed playback boundary and local recorder", implemented: true, limitation: "Entitlement/device verification required"),
        .init(domain: .search, deepestPublicBehavior: "local concurrent search and assistant-owned Core Spotlight indexing", implemented: true, limitation: "No access to other apps' private Spotlight indexes")
    ]
}

struct SystemCameraCapture: UIViewControllerRepresentable {
    let onCapturedImage: @MainActor (UIImage?) -> Void
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeCoordinator() -> Coordinator { Coordinator(onCapturedImage) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        precondition(Self.isAvailable, "Camera capture must only be presented when the public camera source is available")
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    @MainActor final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: @MainActor (UIImage?) -> Void
        init(_ completion: @escaping @MainActor (UIImage?) -> Void) { self.completion = completion }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion(info[.originalImage] as? UIImage); picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil); picker.dismiss(animated: true)
        }
    }
}
