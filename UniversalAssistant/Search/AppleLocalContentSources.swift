import Foundation
import Photos
import CoreLocation
import CoreSpotlight
import UniformTypeIdentifiers
import SwiftUI
import UIKit
import Vision

struct PhotoSearchCriteria: Sendable {
    let dateRange: Range<Date>?
    let coordinate: CLLocationCoordinate2D?
    let radiusMeters: CLLocationDistance
    let albumName: String?

    init(dateRange: Range<Date>? = nil, coordinate: CLLocationCoordinate2D? = nil,
         radiusMeters: CLLocationDistance = 1_000, albumName: String? = nil) {
        self.dateRange = dateRange; self.coordinate = coordinate
        self.radiusMeters = max(0, radiusMeters); self.albumName = albumName
    }
}

struct PhotoAssetReference: Equatable, Sendable {
    let localIdentifier: String
    let creationDate: Date?
    let coordinate: CLLocationCoordinate2D?
    let album: String?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.localIdentifier == rhs.localIdentifier && lhs.creationDate == rhs.creationDate &&
        lhs.coordinate?.latitude == rhs.coordinate?.latitude && lhs.coordinate?.longitude == rhs.coordinate?.longitude &&
        lhs.album == rhs.album
    }
}

protocol PhotoLibrarySearching: Sendable {
    func authorization() -> LocalSearchAccess
    func search(_ criteria: PhotoSearchCriteria, limit: Int) async -> [PhotoAssetReference]
}

struct PhotoKitLibrarySearch: PhotoLibrarySearching {
    func authorization() -> LocalSearchAccess {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: .permitted
        case .limited: .limited
        case .notDetermined: .permissionRequired
        case .denied, .restricted: .denied
        @unknown default: .unavailable
        }
    }

    func search(_ criteria: PhotoSearchCriteria, limit: Int) async -> [PhotoAssetReference] {
        guard [.permitted, .limited].contains(authorization()) else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            if let range = criteria.dateRange {
                options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", range.lowerBound as NSDate, range.upperBound as NSDate)
            }
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = max(1, min(limit * 8, 200))
            var allowedIDs: Set<String>?
            if let albumName = criteria.albumName {
                let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
                var ids = Set<String>()
                collections.enumerateObjects { collection, _, _ in
                    guard collection.localizedTitle?.localizedCaseInsensitiveCompare(albumName) == .orderedSame else { return }
                    PHAsset.fetchAssets(in: collection, options: nil).enumerateObjects { asset, _, _ in
                        ids.insert(asset.localIdentifier)
                    }
                }
                allowedIDs = ids
            }
            let center = criteria.coordinate.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
            var output: [PhotoAssetReference] = []
            PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, stop in
                guard allowedIDs?.contains(asset.localIdentifier) ?? true else { return }
                if let center {
                    guard let location = asset.location, location.distance(from: center) <= criteria.radiusMeters else { return }
                }
                output.append(.init(localIdentifier: asset.localIdentifier, creationDate: asset.creationDate,
                                    coordinate: asset.location?.coordinate, album: criteria.albumName))
                if output.count >= max(1, min(limit, 20)) { stop.pointee = true }
            }
            return output
        }.value
    }
}

struct PhotoSemanticLabel: Equatable, Sendable { let name: String; let confidence: Float }
protocol PhotoAssetImageLoading: Sendable { func imageData(localIdentifier: String) async throws -> Data }
protocol PhotoSemanticLabeling: Sendable { func labels(imageData: Data) async throws -> [PhotoSemanticLabel] }

struct PhotoKitAssetImageLoader: PhotoAssetImageLoading {
    func imageData(localIdentifier: String) async throws -> Data {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else { throw CocoaError(.fileNoSuchFile) }
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = false; options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: CocoaError(.fileReadUnknown)) }
            }
        }
    }
}

struct VisionPhotoSemanticLabeler: PhotoSemanticLabeling {
    func labels(imageData: Data) async throws -> [PhotoSemanticLabel] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest(); try VNImageRequestHandler(data: imageData).perform([request])
            return (request.results ?? []).filter { $0.confidence >= 0.2 }.prefix(12).map { .init(name: $0.identifier, confidence: $0.confidence) }
        }.value
    }
}

struct PhotoSemanticSearchEngine: Sendable {
    let library: any PhotoLibrarySearching; let loader: any PhotoAssetImageLoading; let labeler: any PhotoSemanticLabeling
    func search(_ query: String, criteria: PhotoSearchCriteria = .init(), limit: Int = 5) async -> [PhotoAssetReference] {
        guard [.permitted, .limited].contains(library.authorization()) else { return [] }
        let needle = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let candidates = await library.search(criteria, limit: min(max(limit * 4, 8), 20))
        return await withTaskGroup(of: (Int, PhotoAssetReference)?.self) { group in
            for (index, asset) in candidates.enumerated() { group.addTask {
                guard let data = try? await loader.imageData(localIdentifier: asset.localIdentifier),
                      let labels = try? await labeler.labels(imageData: data),
                      labels.contains(where: { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(needle) }) else { return nil }
                return (index, asset)
            } }
            var matches: [(Int, PhotoAssetReference)] = []; for await value in group { if let value { matches.append(value) } }
            return matches.sorted { $0.0 < $1.0 }.prefix(max(1, min(limit, 10))).map { $0.1 }
        }
    }
}

struct AuthorizedFileReference: Equatable, Codable, Sendable {
    let url: URL
    let authorizedAt: Date
}

struct AuthorizedDocumentPicker: UIViewControllerRepresentable {
    let onSelection: @MainActor ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelection: onSelection) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelection: @MainActor ([URL]) -> Void
        init(onSelection: @escaping @MainActor ([URL]) -> Void) { self.onSelection = onSelection }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onSelection(urls)
        }
    }
}

actor AuthorizedFileSearchSource: LocalSearchSource {
    let kind: LocalSearchSourceKind = .files
    private var references: [AuthorizedFileReference]

    init(references: [AuthorizedFileReference] = []) { self.references = references }

    func replaceAuthorizedReferences(_ values: [AuthorizedFileReference]) { references = values }

    func search(_ query: LocalSearchQuery) async -> LocalSearchSourceResponse {
        let needle = query.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let snapshot = references
        let matches = await Task.detached(priority: .userInitiated) {
            snapshot.compactMap { reference -> LocalSearchResult? in
                let accessed = reference.url.startAccessingSecurityScopedResource()
                defer { if accessed { reference.url.stopAccessingSecurityScopedResource() } }
                guard FileManager.default.fileExists(atPath: reference.url.path) else { return nil }
                let name = reference.url.lastPathComponent
                guard name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(needle) else { return nil }
                let values = try? reference.url.resourceValues(forKeys: [.contentModificationDateKey])
                return .init(id: reference.url.absoluteString, source: .files, title: name, subtitle: nil,
                             occurredAt: values?.contentModificationDate, exactNameMatch: name.localizedCaseInsensitiveCompare(query.text) == .orderedSame,
                             relevance: 70, openReference: reference.url.absoluteString)
            }
        }.value
        return .init(source: kind, access: .permitted, results: Array(matches.prefix(query.limit)))
    }
}

protocol AssistantSpotlightIndexing: Sendable {
    func index(_ results: [LocalSearchResult]) async throws
    func remove(source: LocalSearchSourceKind) async throws
}

struct CoreSpotlightAssistantIndexer: AssistantSpotlightIndexing {
    private let domainPrefix = "com.universalassistant.local"

    func index(_ results: [LocalSearchResult]) async throws {
        let items = results.map { result in
            let attributes = CSSearchableItemAttributeSet(contentType: .item)
            attributes.title = result.title
            attributes.contentDescription = result.subtitle
            return CSSearchableItem(uniqueIdentifier: "\(result.source.rawValue):\(result.id)",
                                    domainIdentifier: "\(domainPrefix).\(result.source.rawValue)", attributeSet: attributes)
        }
        try await CSSearchableIndex.default().indexSearchableItems(items)
    }

    func remove(source: LocalSearchSourceKind) async throws {
        try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: ["\(domainPrefix).\(source.rawValue)"])
    }
}
