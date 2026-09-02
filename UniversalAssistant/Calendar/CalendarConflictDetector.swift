import Foundation

enum CalendarConflictReason: Equatable, Sendable {
    case overlap
    case insufficientTravelTime(required: TimeInterval, available: TimeInterval)
}

struct CalendarConflict: Equatable, Sendable {
    let earlierEventID: String
    let laterEventID: String
    let reason: CalendarConflictReason
}

struct CalendarTravelEvidence: Equatable, Sendable {
    let fromEventID: String
    let toEventID: String
    let duration: TimeInterval
    let source: String
    let observedAt: Date
}

struct CalendarConflictDetector: Sendable {
    var maximumTravelEvidenceAge: TimeInterval = 300

    func conflicts(
        events: [CalendarEventSnapshot],
        travel: [CalendarTravelEvidence],
        now: Date = .now
    ) -> [CalendarConflict] {
        let ordered = events.sorted { $0.draft.start < $1.draft.start }
        return zip(ordered, ordered.dropFirst()).compactMap { earlier, later in
            if earlier.draft.end > later.draft.start {
                return .init(earlierEventID: earlier.identifier, laterEventID: later.identifier, reason: .overlap)
            }
            guard let evidence = travel.first(where: {
                $0.fromEventID == earlier.identifier && $0.toEventID == later.identifier &&
                !$0.source.isEmpty && $0.duration >= 0 &&
                now.timeIntervalSince($0.observedAt) >= -60 &&
                now.timeIntervalSince($0.observedAt) <= maximumTravelEvidenceAge
            }) else { return nil }
            let available = later.draft.start.timeIntervalSince(earlier.draft.end)
            guard evidence.duration > available else { return nil }
            return .init(earlierEventID: earlier.identifier, laterEventID: later.identifier,
                         reason: .insufficientTravelTime(required: evidence.duration, available: available))
        }
    }
}
