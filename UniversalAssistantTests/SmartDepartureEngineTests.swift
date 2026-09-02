import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Smart departure")
struct SmartDepartureEngineTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func calculatesEveryCanonicalBufferFromVerifiedRoute() throws {
        let route = option(duration: 1_800)
        let buffers = DepartureBuffers(traffic: 300, parking: 240, walking: 180, safety: 600)
        let request = SmartDepartureRequest(origin: "Home", destination: "Clinic",
            arrivalDeadline: now.addingTimeInterval(7_200), route: route, buffers: buffers)
        let result = try SmartDepartureEngine().recommend(request, now: now)
        #expect(result.departureAt == request.arrivalDeadline.addingTimeInterval(-3_120))
        #expect(result.routeSource == "MapKit")
        #expect(result.origin == "Home" && result.destination == "Clinic")
    }

    @Test func staleMissingOrUnavailableRouteNeverProducesRecommendation() {
        let request = SmartDepartureRequest(origin: "Home", destination: "Clinic",
            arrivalDeadline: now.addingTimeInterval(7_200), route: option(duration: nil),
            buffers: .init(traffic: 0, parking: 0, walking: 0, safety: 300))
        #expect(throws: SmartDepartureError.unverifiedRoute) {
            try SmartDepartureEngine().recommend(request, now: now)
        }
    }

    @Test func recalculatesOnlyMeaningfulChange() throws {
        let engine = SmartDepartureEngine(meaningfulChange: 120)
        let base = request(duration: 1_800)
        let previous = try engine.recommend(base, now: now)
        #expect(try engine.meaningfulUpdate(previous: previous, request: request(duration: 1_860), now: now) == nil)
        #expect(try engine.meaningfulUpdate(previous: previous, request: request(duration: 2_100), now: now)?.travelTime == 2_100)
    }

    private func request(duration: TimeInterval) -> SmartDepartureRequest {
        .init(origin: "Home", destination: "Clinic", arrivalDeadline: now.addingTimeInterval(7_200),
              route: option(duration: duration), buffers: .init(traffic: 300, parking: 0, walking: 0, safety: 300))
    }

    private func option(duration: TimeInterval?) -> TransportOption {
        .init(id: "route", providerID: "mapkit", mode: .driving, departure: now,
              arrival: duration.map { now.addingTimeInterval($0) }, durationSeconds: duration,
              availability: .available, evidence: .init(source: "MapKit", kind: .realTime, observedAt: now))
    }
}
