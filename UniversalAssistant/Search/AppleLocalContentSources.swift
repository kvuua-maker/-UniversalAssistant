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
    func requestAuthorization() async -> LocalSearchAccess
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

    func requestAuthorization() async -> LocalSearchAccess {
        guard authorization() == .permissionRequired else { return authorization() }
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return authorization()
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
struct PhotoSemanticMatch: Equatable, Sendable {
    let asset: PhotoAssetReference
    let confidence: Float
    let matchedLabels: [String]
}
protocol PhotoAssetImageLoading: Sendable { func imageData(localIdentifier: String) async throws -> Data }
protocol PhotoSemanticLabeling: Sendable { func labels(imageData: Data) async throws -> [PhotoSemanticLabel] }

struct PhotoKitAssetImageLoader: PhotoAssetImageLoading {
    func imageData(localIdentifier: String) async throws -> Data {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else { throw CocoaError(.fileNoSuchFile) }
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = true; options.deliveryMode = .highQualityFormat
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

private final class PhotoSemanticSearchCompletion<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[Value], Never>?
    private var result: [Value]?
    func install(_ value: CheckedContinuation<[Value], Never>) {
        lock.lock(); if let result { lock.unlock(); value.resume(returning: result) } else { continuation = value; lock.unlock() }
    }
    func finish(_ value: [Value]) {
        lock.lock(); guard result == nil else { lock.unlock(); return }; result = value
        let continuation = continuation; self.continuation = nil; lock.unlock(); continuation?.resume(returning: value)
    }
}

struct PhotoSemanticSearchEngine: Sendable {
    let library: any PhotoLibrarySearching; let loader: any PhotoAssetImageLoading; let labeler: any PhotoSemanticLabeling

    func search(_ query: String, criteria: PhotoSearchCriteria = .init(), limit: Int = 5, timeout: Duration = .seconds(5)) async -> [PhotoAssetReference] {
        await matches(query, criteria: criteria, limit: limit, timeout: timeout).map(\.asset)
    }

    func matches(_ query: String, criteria: PhotoSearchCriteria = .init(), limit: Int = 5, timeout: Duration = .seconds(5)) async -> [PhotoSemanticMatch] {
        guard [.permitted, .limited].contains(library.authorization()) else { return [] }
        let terms = Self.semanticTerms(query)
        guard !terms.isEmpty else { return [] }
        let candidates = await library.search(criteria, limit: min(max(limit * 4, 8), 20))
        let completion = PhotoSemanticSearchCompletion<PhotoSemanticMatch>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                completion.install(continuation)
                Task.detached(priority: .userInitiated) {
                    let matches = await withTaskGroup(of: (Int, PhotoSemanticMatch)?.self) { group in
                        for (index, asset) in candidates.enumerated() {
                            group.addTask(priority: .userInitiated) {
                                guard let data = try? await loader.imageData(localIdentifier: asset.localIdentifier),
                                      let labels = try? await labeler.labels(imageData: data) else { return nil }
                                let evidence = labels.filter { label in
                                          let normalized = Self.normalize(label.name)
                                          return terms.contains { normalized.contains($0) || $0.contains(normalized) }
                                      }.sorted { $0.confidence > $1.confidence }
                                guard let confidence = evidence.first?.confidence,
                                      confidence >= Self.minimumReliableConfidence else { return nil }
                                return (index, .init(asset: asset, confidence: confidence, matchedLabels: evidence.map(\.name)))
                            }
                        }
                        var values: [(Int, PhotoSemanticMatch)] = []
                        for await value in group { if let value { values.append(value) } }
                        return values.sorted {
                            if $0.1.confidence != $1.1.confidence { return $0.1.confidence > $1.1.confidence }
                            return $0.0 < $1.0
                        }.prefix(max(1, min(limit, 10))).map { $0.1 }
                    }
                    completion.finish(matches)
                }
                Task.detached(priority: .background) {
                    try? await Task.sleep(for: timeout)
                    completion.finish([])
                }
            }
        } onCancel: {
            completion.finish([])
        }
    }

    private static let minimumReliableConfidence: Float = 0.65

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func semanticTerms(_ query: String) -> Set<String> {
        let ignored: Set<String> = ["знайди", "покажи", "моїх", "моих", "фото", "фотографії", "фотографии", "pictures", "photos", "with", "на", "у", "в", "з", "с"]
        let aliases: [String: Set<String>] = [
            "машиною": ["car", "automobile", "vehicle"], "машина": ["car", "automobile", "vehicle"], "авто": ["car", "automobile", "vehicle"],
            "документом": ["document", "text", "receipt", "paper"], "документ": ["document", "text", "receipt", "paper"],
            "квитанцією": ["receipt", "invoice", "document"], "чеком": ["receipt", "invoice", "document"]
        ]
        var output = Set<String>()
        for token in normalize(query).split(separator: " ").map(String.init) where !ignored.contains(token) {
            output.insert(token)
            output.formUnion(aliases[token] ?? [])
        }
        return output
    }
}

struct PhotoAssetPresentationView: View {
    enum AutomaticAction { case none, ocr, share }
    let localIdentifier: String
    let onOCR: @MainActor (UIImage?) -> Void
    let automaticAction: AutomaticAction
    @State private var image: UIImage?
    @State private var showsShareSheet = false
    @State private var automaticActionPerformed = false

    init(localIdentifier: String, onOCR: @escaping @MainActor (UIImage?) -> Void = { _ in }, automaticAction: AutomaticAction = .none) {
        self.localIdentifier = localIdentifier
        self.onOCR = onOCR
        self.automaticAction = automaticAction
    }

    var body: some View {
        VStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                HStack {
                    Button("Розпізнати текст") { onOCR(image) }
                    Button("Поділитися") { showsShareSheet = true }
                }
            } else { ProgressView() }
        }
        .padding()
        .sheet(isPresented: $showsShareSheet) {
            if let image { SystemShareSheet(items: [image]) }
        }
        .task {
            guard image == nil, let data = try? await PhotoKitAssetImageLoader().imageData(localIdentifier: localIdentifier) else { return }
            image = UIImage(data: data)
            guard !automaticActionPerformed else { return }
            automaticActionPerformed = true
            switch automaticAction {
            case .none: break
            case .ocr: onOCR(image)
            case .share: showsShareSheet = image != nil
            }
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

enum AuthorizedFileQueryError: Error, Equatable { case timedOut, cancelled }

protocol AuthorizedFileQuerying: Sendable {
    func search(references: [AuthorizedFileReference], query: LocalSearchQuery, timeout: Duration) async throws -> [LocalSearchResult]
}

private final class FileQueryCompletion<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    func install(_ value: CheckedContinuation<Value, Error>) {
        lock.lock(); if let result { lock.unlock(); value.resume(with: result) } else { continuation = value; lock.unlock() }
    }
    func finish(_ value: Result<Value, Error>) {
        lock.lock(); guard result == nil else { lock.unlock(); return }; result = value
        let continuation = continuation; self.continuation = nil; lock.unlock(); continuation?.resume(with: value)
    }
}

final class SystemAuthorizedFileQuery: AuthorizedFileQuerying, @unchecked Sendable {
    private static let deadlineQueue = DispatchQueue(label: "com.universalassistant.files.deadline", qos: .userInteractive)
    typealias Operation = @Sendable ([AuthorizedFileReference], LocalSearchQuery) -> [LocalSearchResult]
    private let queue = DispatchQueue(label: "com.universalassistant.files.query", qos: .userInitiated)
    private let operation: Operation
    init(operation: @escaping Operation = SystemAuthorizedFileQuery.searchSynchronously) { self.operation = operation }
    func search(references: [AuthorizedFileReference], query: LocalSearchQuery, timeout: Duration) async throws -> [LocalSearchResult] {
        let completion = FileQueryCompletion<[LocalSearchResult]>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                queue.async { [operation] in completion.finish(.success(operation(references, query))) }
                let components = timeout.components
                let delay = Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
                Self.deadlineQueue.asyncAfter(deadline: .now() + delay) {
                    completion.finish(.failure(AuthorizedFileQueryError.timedOut))
                }
            }
        } onCancel: { completion.finish(.failure(AuthorizedFileQueryError.cancelled)) }
    }
    private static func searchSynchronously(references: [AuthorizedFileReference], query: LocalSearchQuery) -> [LocalSearchResult] {
        let needle = query.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return references.compactMap { reference -> LocalSearchResult? in
            let accessed = reference.url.startAccessingSecurityScopedResource()
            defer { if accessed { reference.url.stopAccessingSecurityScopedResource() } }
            guard FileManager.default.fileExists(atPath: reference.url.path) else { return nil }
            let name = reference.url.lastPathComponent
            guard name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(needle) else { return nil }
            let values = try? reference.url.resourceValues(forKeys: [.contentModificationDateKey])
            return .init(id: reference.url.absoluteString, source: .files, title: name, subtitle: nil, occurredAt: values?.contentModificationDate, exactNameMatch: name.localizedCaseInsensitiveCompare(query.text) == .orderedSame, relevance: 70, openReference: reference.url.absoluteString)
        }
    }
}

actor AuthorizedFileSearchSource: LocalSearchSource {
    let kind: LocalSearchSourceKind = .files
    private var references: [AuthorizedFileReference]
    private let query: any AuthorizedFileQuerying
    /// Local metadata reads should finish immediately; three seconds matches the bounded interactive Contacts lifecycle.
    private let timeout: Duration
    init(references: [AuthorizedFileReference] = [], query: any AuthorizedFileQuerying = SystemAuthorizedFileQuery(), timeout: Duration = .seconds(3)) { self.references = references; self.query = query; self.timeout = timeout }
    func replaceAuthorizedReferences(_ values: [AuthorizedFileReference]) { references = values }
    func search(_ value: LocalSearchQuery) async -> LocalSearchSourceResponse {
        do { return .init(source: kind, access: .permitted, results: Array(try await query.search(references: references, query: value, timeout: timeout).prefix(value.limit))) }
        catch { return .init(source: kind, access: .unavailable, results: []) }
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
