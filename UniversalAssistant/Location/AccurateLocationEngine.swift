import CoreLocation
import Foundation
import Observation

enum LocationQuality: String, Codable, Sendable { case precise, good, approximate, poor, suspicious, unavailable }
enum LocationSource: String, Codable, Sendable { case device, manual }
enum LocationPurpose: Sendable { case general, nearbySearch, navigation, emergency }

struct LocationSample: Equatable, Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timestamp: Date
    let speed: Double
    let course: Double
    let source: LocationSource
    var isReducedAccuracy: Bool = false
}

struct ValidatedLocation: Equatable, Codable, Sendable {
    let sample: LocationSample
    let quality: LocationQuality
    let isSafeForLocationActions: Bool
    let manualLabel: String?
}

protocol ReverseLocationGeocoding: Sendable {
    func address(for location: ValidatedLocation) async throws -> String
}

actor AppleReverseLocationGeocoder: ReverseLocationGeocoding {
    private let geocoder = CLGeocoder()
    func address(for location: ValidatedLocation) async throws -> String {
        let point = CLLocation(latitude: location.sample.latitude, longitude: location.sample.longitude)
        guard let value = try await geocoder.reverseGeocodeLocation(point).first else { throw CurrentLocationResolutionError.unavailable }
        let parts = [value.name, value.locality, value.administrativeArea, value.country].compactMap { component in component }.filter { component in !component.isEmpty }
        guard !parts.isEmpty else { throw CurrentLocationResolutionError.unavailable }
        return parts.reduce(into: [String]()) { accumulated, component in if !accumulated.contains(component) { accumulated.append(component) } }.joined(separator: ", ")
    }
}

protocol ManualLocationGeocoding: Sendable {
    func resolve(_ label: String) async throws -> LocationSample
}

actor AppleManualLocationGeocoder: ManualLocationGeocoding {
    private let geocoder = CLGeocoder()

    func resolve(_ label: String) async throws -> LocationSample {
        let query = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw ManualLocationError.emptyQuery }
        let placemarks = try await geocoder.geocodeAddressString(query)
        guard let coordinate = placemarks.first?.location?.coordinate else {
            throw ManualLocationError.notFound
        }
        return .init(latitude: coordinate.latitude, longitude: coordinate.longitude,
                     horizontalAccuracy: 0, timestamp: .now, speed: -1, course: -1,
                     source: .manual)
    }
}

enum ManualLocationError: Error, Equatable, Sendable { case emptyQuery, notFound, unsafeResult }

struct ManualLocationContextResolver: Sendable {
    let geocoder: any ManualLocationGeocoding
    private let validator = LocationValidator()

    init(geocoder: any ManualLocationGeocoding = AppleManualLocationGeocoder()) {
        self.geocoder = geocoder
    }

    func resolve(_ label: String) async throws -> ValidatedLocation {
        let sample = try await geocoder.resolve(label)
        let validated = validator.validate(sample)
        guard validated.isSafeForLocationActions else { throw ManualLocationError.unsafeResult }
        return .init(sample: validated.sample, quality: validated.quality,
                     isSafeForLocationActions: true,
                     manualLabel: label.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct LocationValidator: Sendable {
    var poorAfter: TimeInterval = 30
    var unavailableAfter: TimeInterval = 120
    var maximumPlausibleSpeed: Double = 200

    func validate(_ sample: LocationSample, previous: ValidatedLocation? = nil, now: Date = .now) -> ValidatedLocation {
        guard (-90...90).contains(sample.latitude), (-180...180).contains(sample.longitude), sample.horizontalAccuracy >= 0 else {
            return result(sample, .unavailable, false)
        }
        if sample.source == .manual {
            return result(sample, .approximate, true)
        }
        let age = now.timeIntervalSince(sample.timestamp)
        guard age >= -5, age <= unavailableAfter else { return result(sample, .unavailable, false) }
        if let previous, previous.sample.source == .device {
            let elapsed = sample.timestamp.timeIntervalSince(previous.sample.timestamp)
            if elapsed > 0 {
                let speed = distance(from: previous.sample, to: sample) / elapsed
                if speed > maximumPlausibleSpeed { return result(sample, .suspicious, false) }
            }
        }
        if age > poorAfter || sample.horizontalAccuracy > 1_000 { return result(sample, .poor, true) }
        if sample.isReducedAccuracy || sample.horizontalAccuracy > 100 { return result(sample, .approximate, true) }
        if sample.horizontalAccuracy <= 10 { return result(sample, .precise, true) }
        return result(sample, .good, true)
    }

    private func result(_ sample: LocationSample, _ quality: LocationQuality, _ safe: Bool) -> ValidatedLocation {
        .init(sample: sample, quality: quality, isSafeForLocationActions: safe, manualLabel: nil)
    }

    private func distance(from a: LocationSample, to b: LocationSample) -> Double {
        let radius = 6_371_000.0
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let value = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return radius * 2 * atan2(sqrt(value), sqrt(1 - value))
    }
}

enum AccurateLocationState: Equatable, Sendable { case idle, requestingPermission, locating, available, denied, unavailable }

@MainActor
protocol CurrentLocationResolving: AnyObject {
    func resolveCurrent(for purpose: LocationPurpose) async throws -> ValidatedLocation
}

enum CurrentLocationResolutionError: Error, Equatable { case denied, unavailable }

@MainActor
final class AppleCurrentLocationResolver: CurrentLocationResolving {
    private let engine: AccurateLocationEngine

    init(engine: AccurateLocationEngine = .init()) { self.engine = engine }

    func resolveCurrent(for purpose: LocationPurpose) async throws -> ValidatedLocation {
        engine.request(for: purpose)
        for _ in 0..<100 {
            if engine.state == .denied { throw CurrentLocationResolutionError.denied }
            if engine.state == .unavailable { throw CurrentLocationResolutionError.unavailable }
            if engine.state == .available, let value = engine.current, value.isSafeForLocationActions { return value }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CurrentLocationResolutionError.unavailable
    }
}

@MainActor
@Observable
final class AccurateLocationEngine: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var state: AccurateLocationState = .idle
    private(set) var current: ValidatedLocation?
    private let manager: CLLocationManager
    private let validator: LocationValidator
    private var timeoutTask: Task<Void, Never>?
    private var recoveryAttempts = 0

    init(manager: CLLocationManager = CLLocationManager(), validator: LocationValidator = .init()) {
        self.manager = manager; self.validator = validator
        super.init(); manager.delegate = self
    }

    func request(for purpose: LocationPurpose = .general) {
        switch manager.authorizationStatus {
        case .notDetermined:
            state = .requestingPermission; manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            beginRequest(for: purpose)
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .unavailable
        }
    }

    func useManual(latitude: Double, longitude: Double, label: String) {
        let sample = LocationSample(latitude: latitude, longitude: longitude, horizontalAccuracy: 0, timestamp: .now, speed: -1, course: -1, source: .manual)
        var validated = validator.validate(sample)
        validated = .init(sample: validated.sample, quality: validated.quality, isSafeForLocationActions: validated.isSafeForLocationActions, manualLabel: label)
        current = validated; state = validated.isSafeForLocationActions ? .available : .unavailable
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { beginRequest(for: .general) }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { state = .denied }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.max(by: { $0.timestamp < $1.timestamp }) else { return }
        timeoutTask?.cancel()
        let sample = LocationSample(
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy, timestamp: location.timestamp,
            speed: location.speed, course: location.course, source: .device,
            isReducedAccuracy: manager.accuracyAuthorization == .reducedAccuracy
        )
        let validated = validator.validate(sample, previous: current)
        current = validated
        if (validated.quality == .poor || validated.quality == .suspicious), recoveryAttempts < 2 {
            recoveryAttempts += 1; manager.requestLocation(); scheduleTimeout(); return
        }
        recoveryAttempts = 0
        state = validated.isSafeForLocationActions ? .available : .unavailable
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        timeoutTask?.cancel(); state = .unavailable
    }

    private func beginRequest(for purpose: LocationPurpose) {
        manager.desiredAccuracy = switch purpose {
        case .navigation, .emergency: kCLLocationAccuracyBest
        case .nearbySearch: kCLLocationAccuracyNearestTenMeters
        case .general: kCLLocationAccuracyHundredMeters
        }
        state = .locating; manager.requestLocation(); scheduleTimeout()
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.state == .locating else { return }
            self.state = .unavailable
        }
    }
}
