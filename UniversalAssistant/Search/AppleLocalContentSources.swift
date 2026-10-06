import Foundation
import Photos
import PhotosUI
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
    var modificationDate: Date? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.localIdentifier == rhs.localIdentifier && lhs.creationDate == rhs.creationDate &&
        lhs.coordinate?.latitude == rhs.coordinate?.latitude && lhs.coordinate?.longitude == rhs.coordinate?.longitude &&
        lhs.album == rhs.album && lhs.modificationDate == rhs.modificationDate
    }
}

protocol PhotoLibrarySearching: Sendable {
    func authorization() -> LocalSearchAccess
    func requestAuthorization() async -> LocalSearchAccess
    func search(_ criteria: PhotoSearchCriteria, limit: Int) async -> [PhotoAssetReference]
    func currentlyAccessible(_ assets: [PhotoAssetReference]) -> [PhotoAssetReference]
}

extension PhotoLibrarySearching {
    func currentlyAccessible(_ assets: [PhotoAssetReference]) -> [PhotoAssetReference] {
        [.permitted, .limited].contains(authorization()) ? assets : []
    }
}

struct PhotoKitLibrarySearch: PhotoLibrarySearching {
    func currentlyAccessible(_ assets: [PhotoAssetReference]) -> [PhotoAssetReference] {
        guard [.permitted, .limited].contains(authorization()), !assets.isEmpty else { return [] }
        // Authorization can remain .limited while the user changes the
        // selection. Re-fetch only the result identifiers before publishing.
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: assets.map(\.localIdentifier), options: nil)
        var visible = Set<String>()
        fetched.enumerateObjects { asset, _, _ in visible.insert(asset.localIdentifier) }
        return assets.filter { visible.contains($0.localIdentifier) }
    }

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
        guard limit > 0 else { return [] }
        guard [.permitted, .limited].contains(authorization()) else { return [] }
        guard !Task.isCancelled else { return [] }
        let options = PHFetchOptions()
        if let range = criteria.dateRange {
            options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", range.lowerBound as NSDate, range.upperBound as NSDate)
        }
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // Location filtering requires inspecting metadata across the accessible
        // library. Applying a newest-200 limit before the coordinate predicate
        // makes older geotagged assets permanently invisible.
        options.fetchLimit = criteria.coordinate == nil && criteria.albumName == nil ? min(limit, 200) : 0
        var allowedIDs: Set<String>?
        if let albumName = criteria.albumName {
            let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            var ids = Set<String>()
            collections.enumerateObjects { collection, _, stop in
                guard !Task.isCancelled else { stop.pointee = true; return }
                guard collection.localizedTitle?.localizedCaseInsensitiveCompare(albumName) == .orderedSame else { return }
                PHAsset.fetchAssets(in: collection, options: nil).enumerateObjects { asset, _, assetStop in
                    guard !Task.isCancelled else { assetStop.pointee = true; return }
                    ids.insert(asset.localIdentifier)
                }
            }
            allowedIDs = ids
        }
        let center = criteria.coordinate.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        var output: [PhotoAssetReference] = []
        PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, stop in
            guard !Task.isCancelled else { stop.pointee = true; return }
            guard allowedIDs?.contains(asset.localIdentifier) ?? true else { return }
            if let center {
                guard let location = asset.location, location.distance(from: center) <= criteria.radiusMeters else { return }
            }
            output.append(.init(localIdentifier: asset.localIdentifier, creationDate: asset.creationDate,
                                coordinate: asset.location?.coordinate, album: criteria.albumName,
                                modificationDate: asset.modificationDate))
            if output.count >= min(limit, 200) { stop.pointee = true }
        }
        return output
    }
}

struct PhotoSemanticLabel: Equatable, Codable, Sendable { let name: String; let confidence: Float }
struct PhotoSemanticMatch: Equatable, Sendable {
    let asset: PhotoAssetReference
    let confidence: Float
    let matchedLabels: [String]
}
protocol PhotoAssetImageLoading: Sendable {
    func imageData(localIdentifier: String) async throws -> Data
    func semanticThumbnailData(localIdentifier: String) async throws -> Data
    func documentThumbnailData(localIdentifier: String) async throws -> Data
}
extension PhotoAssetImageLoading {
    func semanticThumbnailData(localIdentifier: String) async throws -> Data {
        try await imageData(localIdentifier: localIdentifier)
    }
    func documentThumbnailData(localIdentifier: String) async throws -> Data {
        try await semanticThumbnailData(localIdentifier: localIdentifier)
    }
}
protocol PhotoSemanticLabeling: Sendable {
    func labels(imageData: Data) async throws -> [PhotoSemanticLabel]
    func documentLabels(imageData: Data) async throws -> [PhotoSemanticLabel]
}
extension PhotoSemanticLabeling {
    // Scene labels are not OCR evidence. Implementations without text
    // recognition must not silently claim document support.
    func documentLabels(imageData: Data) async throws -> [PhotoSemanticLabel] { [] }
}

enum PhotoAssetImageLoadError: Error, Equatable { case timedOut, unavailable }

private final class PhotoAssetImageLoadCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private let manager: PHImageManager
    private var continuation: CheckedContinuation<Data, Error>?
    private var result: Result<Data, Error>?
    private var requestID: PHImageRequestID?
    private var cancellationRequested = false

    init(manager: PHImageManager) { self.manager = manager }
    func install(_ value: CheckedContinuation<Data, Error>) {
        lock.lock()
        if let result { lock.unlock(); value.resume(with: result) }
        else { continuation = value; lock.unlock() }
    }
    func setRequestID(_ value: PHImageRequestID) {
        lock.lock(); requestID = value; let cancel = cancellationRequested; lock.unlock()
        if cancel { manager.cancelImageRequest(value) }
    }
    func finish(_ value: Result<Data, Error>, cancelRequest: Bool = false) {
        lock.lock(); guard result == nil else { lock.unlock(); return }
        result = value; cancellationRequested = cancelRequest
        let continuation = continuation; self.continuation = nil; let id = requestID; lock.unlock()
        if cancelRequest, let id { manager.cancelImageRequest(id) }
        continuation?.resume(with: value)
    }
}

struct PhotoKitAssetImageLoader: PhotoAssetImageLoading {
    func imageData(localIdentifier: String) async throws -> Data {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else { throw CocoaError(.fileNoSuchFile) }
        let manager = PHImageManager.default()
        let completion = PhotoAssetImageLoadCompletion(manager: manager)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                let options = PHImageRequestOptions()
                // A user-selected exact asset may legitimately be backed by
                // iCloud. PhotoKit owns the authenticated network transfer.
                options.isNetworkAccessAllowed = true
                options.deliveryMode = .highQualityFormat
                let id = manager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                    if let error = info?[PHImageErrorKey] as? Error { completion.finish(.failure(error)) }
                    else if let data { completion.finish(.success(data)) }
                    else { completion.finish(.failure(PhotoAssetImageLoadError.unavailable)) }
                }
                completion.setRequestID(id)
                Task {
                    try? await Task.sleep(for: .seconds(15))
                    completion.finish(.failure(PhotoAssetImageLoadError.timedOut), cancelRequest: true)
                }
            }
        } onCancel: {
            completion.finish(.failure(CancellationError()), cancelRequest: true)
        }
    }

    func semanticThumbnailData(localIdentifier: String) async throws -> Data {
        try await thumbnailData(localIdentifier: localIdentifier, dimension: 384)
    }

    func documentThumbnailData(localIdentifier: String) async throws -> Data {
        try await thumbnailData(localIdentifier: localIdentifier, dimension: 1_024)
    }

    private func thumbnailData(localIdentifier: String, dimension: CGFloat) async throws -> Data {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
            throw CocoaError(.fileNoSuchFile)
        }
        let manager = PHImageManager.default()
        let completion = PhotoAssetImageLoadCompletion(manager: manager)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                let options = PHImageRequestOptions()
                options.deliveryMode = dimension > 384 ? .highQualityFormat : .fastFormat
                options.resizeMode = dimension > 384 ? .exact : .fast
                options.isNetworkAccessAllowed = false
                let id = manager.requestImage(
                    for: asset,
                    targetSize: .init(width: dimension, height: dimension),
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    if dimension > 384, info?[PHImageResultIsDegradedKey] as? Bool == true { return }
                    if let error = info?[PHImageErrorKey] as? Error { completion.finish(.failure(error)) }
                    else if let data = image?.jpegData(compressionQuality: 0.72) { completion.finish(.success(data)) }
                    else { completion.finish(.failure(PhotoAssetImageLoadError.unavailable)) }
                }
                completion.setRequestID(id)
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    completion.finish(.failure(PhotoAssetImageLoadError.timedOut), cancelRequest: true)
                }
            }
        } onCancel: {
            completion.finish(.failure(CancellationError()), cancelRequest: true)
        }
    }
}

actor PhotoSemanticIndex {
    struct Entry: Codable, Sendable {
        let fingerprint: String
        let labels: [PhotoSemanticLabel]
        let indexedAt: Date
    }

    static let shared = PhotoSemanticIndex()
    private var entries: [String: Entry]
    private let storeURL: URL?

    init(storeURL: URL? = nil) {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        self.storeURL = storeURL ?? root?.appendingPathComponent("UniversalAssistant/photo-semantic-index.json")
        if let url = self.storeURL, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    func labels(for asset: PhotoAssetReference, namespace: String = "scene-v1") -> [PhotoSemanticLabel]? {
        let fingerprint = Self.fingerprint(asset)
        guard let entry = entries[asset.localIdentifier + "|" + namespace], entry.fingerprint == fingerprint else { return nil }
        return entry.labels
    }

    func store(_ labels: [PhotoSemanticLabel], for asset: PhotoAssetReference, namespace: String = "scene-v1") {
        entries[asset.localIdentifier + "|" + namespace] = .init(
            fingerprint: Self.fingerprint(asset), labels: labels, indexedAt: .now
        )
        persist()
    }

    private func persist() {
        guard let storeURL, let data = try? JSONEncoder().encode(entries) else { return }
        let directory = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: storeURL, options: .atomic)
    }

    private static func fingerprint(_ asset: PhotoAssetReference) -> String {
        "\(asset.localIdentifier)|\(asset.creationDate?.timeIntervalSince1970 ?? 0)|\(asset.modificationDate?.timeIntervalSince1970 ?? 0)"
    }
}

struct VisionPhotoSemanticLabeler: PhotoSemanticLabeling {
    func labels(imageData: Data) async throws -> [PhotoSemanticLabel] {
        try Task.checkCancellation()
        let values: [PhotoSemanticLabel] = try await Task.detached(priority: .userInitiated) { () throws -> [PhotoSemanticLabel] in
            let request = VNClassifyImageRequest(); try VNImageRequestHandler(data: imageData).perform([request])
            return (request.results ?? []).filter { $0.confidence >= 0.2 }.prefix(12).map {
                PhotoSemanticLabel(name: $0.identifier, confidence: $0.confidence)
            }
        }.value
        try Task.checkCancellation()
        return values
    }

    func documentLabels(imageData: Data) async throws -> [PhotoSemanticLabel] {
        try Task.checkCancellation()
        let work = Task.detached(priority: .userInitiated) { () throws -> [PhotoSemanticLabel] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            request.usesLanguageCorrection = false
            let supported = try request.supportedRecognitionLanguages()
            let preferred = ["uk-UA", "ru-RU", "en-US"].filter { supported.contains($0) }
            if !preferred.isEmpty { request.recognitionLanguages = preferred }
            try VNImageRequestHandler(data: imageData).perform([request])
            try Task.checkCancellation()
            // Keep only aggregate evidence: recognized text never leaves this
            // on-device operation and is neither cached nor logged.
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first }
                .filter { $0.confidence >= 0.65 && $0.string.filter(\.isLetter).count >= 3 }
            guard lines.count >= 2, lines.reduce(0, { $0 + $1.string.count }) >= 16 else { return [] }
            return [.init(name: "document", confidence: lines.map(\.confidence).min() ?? 0)]
        }
        return try await withTaskCancellationHandler {
            let values = try await work.value
            try Task.checkCancellation()
            return values
        } onCancel: { work.cancel() }
    }
}

struct PhotoSemanticSearchReport: Sendable {
    let matches: [PhotoSemanticMatch]
    let isComplete: Bool
    let timedOut: Bool
}

private final class PhotoSemanticDeadlineCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<PhotoSemanticSearchReport, Never>?
    private var result: PhotoSemanticSearchReport?
    private var partial: [(Int, PhotoSemanticMatch)] = []
    private var unavailableAssets = false
    private let limit: Int
    private var work: Task<Void, Never>?

    init(limit: Int) { self.limit = max(1, min(limit, 10)) }

    func install(_ continuation: CheckedContinuation<PhotoSemanticSearchReport, Never>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(returning: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func setWork(_ work: Task<Void, Never>) {
        lock.lock()
        if result == nil { self.work = work; lock.unlock() }
        else { lock.unlock(); work.cancel() }
    }

    func record(_ value: PhotoSemanticMatch, position: Int) {
        lock.withLock {
            guard result == nil else { return }
            partial.append((position, value))
        }
    }

    func markUnavailableAsset() { lock.withLock { unavailableAssets = true } }

    func finish(isComplete: Bool, timedOut: Bool = false, cancelWork: Bool = false, discard: Bool = false) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        let matches = discard ? [] : partial.sorted {
            if $0.1.confidence != $1.1.confidence { return $0.1.confidence > $1.1.confidence }
            return $0.0 < $1.0
        }.prefix(limit).map { $0.1 }
        let result = PhotoSemanticSearchReport(matches: matches, isComplete: isComplete && !unavailableAssets, timedOut: timedOut)
        self.result = result
        let continuation = continuation
        let work = cancelWork ? work : nil
        self.continuation = nil
        self.work = nil
        lock.unlock()
        work?.cancel()
        continuation?.resume(returning: result)
    }
}

struct PhotoSemanticSearchEngine: Sendable {
    let library: any PhotoLibrarySearching; let loader: any PhotoAssetImageLoading; let labeler: any PhotoSemanticLabeling
    var index: PhotoSemanticIndex = .shared

    func search(_ query: String, criteria: PhotoSearchCriteria = .init(), limit: Int = 5, timeout: Duration = .seconds(2)) async -> [PhotoAssetReference] {
        await matches(query, criteria: criteria, limit: limit, timeout: timeout).map(\.asset)
    }

    func matches(_ query: String, criteria: PhotoSearchCriteria = .init(), limit: Int = 5, timeout: Duration = .seconds(2)) async -> [PhotoSemanticMatch] {
        await report(query, criteria: criteria, limit: limit, timeout: timeout).matches
    }

    func report(_ query: String, criteria: PhotoSearchCriteria = .init(), limit: Int = 5, timeout: Duration = .seconds(2)) async -> PhotoSemanticSearchReport {
        guard [.permitted, .limited].contains(library.authorization()), limit > 0 else {
            return .init(matches: [], isComplete: false, timedOut: false)
        }
        let terms = Self.semanticTerms(query)
        guard !terms.isEmpty else { return .init(matches: [], isComplete: true, timedOut: false) }
        let completion = PhotoSemanticDeadlineCompletion(limit: limit)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                completion.install(continuation)
                let work = Task(priority: .userInitiated) {
                    // Metadata is filtered by PhotoKit before this bounded
                    // candidate window. Result count must not be the scan cap.
                    let candidates = await library.search(criteria, limit: 200)
                    guard !Task.isCancelled else { return }
                    await evaluate(candidates: candidates, terms: terms, completion: completion)
                    guard !Task.isCancelled else { return }
                    let permitted = [.permitted, .limited].contains(library.authorization())
                    completion.finish(isComplete: candidates.count < 200 && permitted, discard: !permitted)
                }
                completion.setWork(work)
                // A low-priority deadline can be starved by concurrent Vision
                // work and turn a bounded request into the full loader delay.
                // Run the lightweight clock at the request's priority; it only
                // sleeps, cancels and resolves the one-shot completion.
                Task(priority: .userInitiated) {
                    do { try await Task.sleep(for: timeout) }
                    catch { completion.finish(isComplete: false, cancelWork: true, discard: true); return }
                    work.cancel()
                    // Give cooperative PhotoKit/Vision work one bounded turn to
                    // observe cancellation before the caller receives timeout.
                    // A non-cooperative loader can delay this by at most 20 ms.
                    try? await Task.sleep(for: .milliseconds(20))
                    completion.finish(isComplete: false, timedOut: true,
                                      discard: ![.permitted, .limited].contains(library.authorization()))
                }
            }
        } onCancel: {
            completion.finish(isComplete: false, cancelWork: true, discard: true)
        }
    }

    private func evaluate(
        candidates: [PhotoAssetReference],
        terms: Set<String>,
        completion: PhotoSemanticDeadlineCompletion
    ) async {
        let document = terms.contains("document")
        let namespace = document ? "document-ocr-v1" : "scene-v1"
        // Two concurrent requests bound memory/CPU on iPhone SE 2. Finish each
        // batch into the deadline snapshot so a slow asset cannot erase hits.
        for offset in stride(from: 0, to: candidates.count, by: 2) {
            guard !Task.isCancelled else { return }
            await withTaskGroup(of: Void.self) { group in
                for position in offset..<min(offset + 2, candidates.count) {
                    let asset = candidates[position]
                    group.addTask(priority: .userInitiated) {
                        guard !Task.isCancelled else { return }
                        let labels: [PhotoSemanticLabel]
                        if let cached = await self.index.labels(for: asset, namespace: namespace) {
                            labels = cached
                        } else {
                            let data = try? await (document
                                ? loader.documentThumbnailData(localIdentifier: asset.localIdentifier)
                                : loader.semanticThumbnailData(localIdentifier: asset.localIdentifier))
                            guard let data, !Task.isCancelled else { completion.markUnavailableAsset(); return }
                            let classified = try? await (document
                                ? labeler.documentLabels(imageData: data)
                                : labeler.labels(imageData: data))
                            guard let classified, !Task.isCancelled else { completion.markUnavailableAsset(); return }
                            labels = classified
                            await self.index.store(classified, for: asset, namespace: namespace)
                        }
                        let evidence = labels.filter { label in
                            !terms.isDisjoint(with: Self.semanticTerms(label.name))
                        }.sorted { $0.confidence > $1.confidence }
                        guard let confidence = evidence.first?.confidence,
                              confidence >= Self.minimumReliableConfidence else { return }
                        completion.record(.init(asset: asset, confidence: confidence, matchedLabels: evidence.map(\.name)), position: position)
                    }
                }
            }
        }
    }

    private static let minimumReliableConfidence: Float = 0.65

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Maps productive multilingual word roots to stable visual concepts emitted
    /// by Vision. This is a bounded taxonomy bridge, not a command/phrase table.
    private static let visualConceptRoots: [(String, [String])] = [
        ("dog", ["dog", "puppy", "canine", "собак", "пес", "щен", "собач"]),
        ("cat", ["cat", "kitten", "feline", "кіш", "кот", "кош"]),
        ("bird", ["bird", "avian", "птах", "птиц"]),
        ("animal", ["animal", "mammal", "pet", "тварин", "животн"]),
        ("vehicle", ["car", "automobile", "vehicle", "truck", "авто", "машин", "транспорт"]),
        ("water", ["sea", "ocean", "water", "beach", "coast", "lake", "river", "мор", "океан", "вод", "пляж", "озер", "річ", "рек"]),
        ("mountain", ["mountain", "hill", "peak", "гор", "вершин"]),
        ("plant", ["plant", "flower", "tree", "forest", "рослин", "квіт", "дерев", "ліс", "лес"]),
        ("person", ["person", "people", "human", "portrait", "людин", "особ", "портрет", "человек"]),
        ("food", ["food", "meal", "dish", "fruit", "vegetable", "їж", "страв", "фрукт", "овоч", "еда"]),
        ("building", ["building", "architecture", "house", "tower", "будів", "архітект", "дім", "веж", "дом"]),
        ("document", ["document", "receipt", "invoice", "paper", "text", "документ", "квитанц", "рахунк", "чек", "папер", "текст"]),
        ("sky", ["sky", "sunset", "sunrise", "cloud", "неб", "захід", "світан", "хмар", "облак"])
    ]

    private static func semanticTerms(_ query: String) -> Set<String> {
        let ignored: Set<String> = ["знайди", "покажи", "моїх", "моих", "фото", "фотографії", "фотографии", "pictures", "photos", "with", "на", "у", "в", "з", "с"]
        var output = Set<String>()
        for token in normalize(query).split(separator: " ").map(String.init) where !ignored.contains(token) {
            output.insert(token)
            for (concept, roots) in visualConceptRoots where roots.contains(where: { token.hasPrefix($0) || $0.hasPrefix(token) && token.count >= 3 }) {
                output.insert(concept)
            }
        }
        return output
    }
}

struct SystemPhotoLibraryPicker: UIViewControllerRepresentable {
    let onSelection: @MainActor (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelection: onSelection) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        LocalVoiceDiagnosticReport.shared.recordBoundaryPre(
            "PHOTOKIT", "operation=library_selection mechanism=PHPickerViewController"
        )
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onSelection: @MainActor (String?) -> Void
        init(onSelection: @escaping @MainActor (String?) -> Void) { self.onSelection = onSelection }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let identifier = results.first?.assetIdentifier
            picker.dismiss(animated: true)
            Task { @MainActor in onSelection(identifier) }
        }
    }
}

struct PhotoAssetPresentationView: View {
    enum AutomaticAction { case none, ocr, share }
    let localIdentifier: String
    let onOCR: @MainActor (UIImage?) -> Void
    let automaticAction: AutomaticAction
    @State private var image: UIImage?
    @State private var loadFailed = false
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
            } else if loadFailed {
                ContentUnavailableView("Фото недоступне", systemImage: "photo.badge.exclamationmark")
            } else {
                ProgressView()
            }
        }
        .padding()
        .sheet(isPresented: $showsShareSheet) {
            if let image { SystemShareSheet(items: [image]) }
        }
        .task {
            LocalVoiceDiagnosticReport.shared.recordBoundaryPre("PHOTOKIT", "operation=load_asset")
            guard image == nil,
                  let data = try? await PhotoKitAssetImageLoader().imageData(localIdentifier: localIdentifier),
                  let loadedImage = UIImage(data: data) else {
                LocalVoiceDiagnosticReport.shared.recordBoundaryPost("PHOTOKIT", "operation=load_asset status=error")
                loadFailed = true
                return
            }
            image = loadedImage
            LocalVoiceDiagnosticReport.shared.recordBoundaryPost("PHOTOKIT", "operation=load_asset status=success")
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
        LocalVoiceDiagnosticReport.shared.recordBoundaryPre("FILES", "mechanism=UIDocumentPicker")
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
            LocalVoiceDiagnosticReport.shared.recordBoundaryPost("FILES", "mechanism=UIDocumentPicker status=selected count=\(urls.count)")
            onSelection(urls)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            LocalVoiceDiagnosticReport.shared.recordBoundaryPost("FILES", "mechanism=UIDocumentPicker status=cancelled")
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
