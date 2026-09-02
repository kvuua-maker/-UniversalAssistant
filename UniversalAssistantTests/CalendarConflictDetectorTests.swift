import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Calendar conflict detection")
struct CalendarConflictDetectorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func detectsOverlapAndVerifiedImpossibleTravel() {
        let overlap = CalendarConflictDetector().conflicts(events: [
            event("a", 0, 1_000), event("b", 900, 2_000)
        ], travel: [], now: now)
        #expect(overlap.first?.reason == .overlap)

        let travel = CalendarTravelEvidence(fromEventID: "a", toEventID: "b", duration: 900,
                                            source: "MapKit", observedAt: now)
        let impossible = CalendarConflictDetector().conflicts(events: [
            event("a", 0, 600), event("b", 1_000, 2_000)
        ], travel: [travel], now: now)
        #expect(impossible.first?.reason == .insufficientTravelTime(required: 900, available: 400))
    }

    @Test func missingOrStaleTravelDoesNotInventConflict() {
        let stale = CalendarTravelEvidence(fromEventID: "a", toEventID: "b", duration: 900,
                                           source: "MapKit", observedAt: now.addingTimeInterval(-1_000))
        #expect(CalendarConflictDetector().conflicts(events: [
            event("a", 0, 600), event("b", 1_000, 2_000)
        ], travel: [stale], now: now).isEmpty)
    }

    private func event(_ id: String, _ start: TimeInterval, _ end: TimeInterval) -> CalendarEventSnapshot {
        .init(identifier: id, draft: .init(title: id, start: now.addingTimeInterval(start),
                                           end: now.addingTimeInterval(end)))
    }
}
