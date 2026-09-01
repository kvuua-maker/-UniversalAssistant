import Foundation
import Testing
@testable import UniversalAssistant

struct LocationValidatorTests {
    private let now = Date(timeIntervalSince1970: 10_000)
    private func sample(lat: Double = 50.45, lon: Double = 30.52, accuracy: Double, age: TimeInterval = 0, reduced: Bool = false, source: LocationSource = .device) -> LocationSample {
        .init(latitude: lat, longitude: lon, horizontalAccuracy: accuracy, timestamp: now.addingTimeInterval(-age), speed: -1, course: -1, source: source, isReducedAccuracy: reduced)
    }

    @Test func qualityUsesRealAccuracyAndReducedAuthorization() {
        let validator = LocationValidator()
        #expect(validator.validate(sample(accuracy: 5), now: now).quality == .precise)
        #expect(validator.validate(sample(accuracy: 40), now: now).quality == .good)
        #expect(validator.validate(sample(accuracy: 5, reduced: true), now: now).quality == .approximate)
        #expect(validator.validate(sample(accuracy: 250), now: now).quality == .approximate)
    }

    @Test func staleAndInvalidSamplesAreDowngraded() {
        let validator = LocationValidator()
        #expect(validator.validate(sample(accuracy: 20, age: 31), now: now).quality == .poor)
        #expect(validator.validate(sample(accuracy: 20, age: 121), now: now).quality == .unavailable)
        #expect(!validator.validate(sample(lat: 100, accuracy: 5), now: now).isSafeForLocationActions)
    }

    @Test func impossibleJumpIsSuspiciousAndUnsafe() {
        let validator = LocationValidator()
        let prior = validator.validate(sample(accuracy: 5), now: now)
        let mexicoSecondsLater = LocationSample(latitude: 19.43, longitude: -99.13, horizontalAccuracy: 5, timestamp: now.addingTimeInterval(2), speed: -1, course: -1, source: .device)
        let result = validator.validate(mexicoSecondsLater, previous: prior, now: now.addingTimeInterval(2))
        #expect(result.quality == .suspicious)
        #expect(!result.isSafeForLocationActions)
    }

    @Test func manualOverrideIsExplicitAndUsableOffline() {
        let result = LocationValidator().validate(sample(accuracy: 0, source: .manual), now: now)
        #expect(result.sample.source == .manual)
        #expect(result.quality == .approximate)
        #expect(result.isSafeForLocationActions)
    }
}
