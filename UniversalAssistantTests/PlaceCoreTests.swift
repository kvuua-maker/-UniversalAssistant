import Foundation
import Testing
@testable import UniversalAssistant

struct PlaceCoreTests {
    private let location = ValidatedLocation(sample: .init(latitude: 50.45, longitude: 30.52, horizontalAccuracy: 10, timestamp: .now, speed: -1, course: -1, source: .device), quality: .good, isSafeForLocationActions: true, manualLabel: nil)
    private func place(_ id: String, name: String = "Coffee", lat: Double = 50.45, lon: Double = 30.52, category: PlaceCategory = .cafe, source: String = "a", distance: Double? = nil, open: Bool? = nil) -> Place {
        .init(id: id, providerID: id, name: name, category: category, latitude: lat, longitude: lon, distanceMeters: distance, isOpenNow: open, source: source, timestamp: .now, verification: .providerReturned)
    }

    @Test func queryRejectsSuspiciousLocationAndUnboundedFanout() {
        var unsafe = location; unsafe = .init(sample: unsafe.sample, quality: .suspicious, isSafeForLocationActions: false, manualLabel: nil)
        #expect(throws: PlaceProviderError.unsafeLocation) { try PlaceQuery(text: "coffee", category: .cafe, location: unsafe).validated() }
        #expect(throws: PlaceProviderError.invalidBounds) { try PlaceQuery(text: "coffee", category: .cafe, location: location, limit: 100).validated() }
    }

    @Test func reliableDuplicatesMergeButDifferentSellerLikePlacesRemain() {
        let a = place("1")
        let duplicate = place("2", lat: 50.45005, lon: 30.52005, source: "b")
        let different = place("3", name: "Coffee House", lat: 50.45005, lon: 30.52005, source: "b")
        #expect(PlaceDeduplicator().deduplicate([a, duplicate, different]).count == 2)
    }

    @Test func rankingUsesRelevanceOpenStateAndDistanceStably() {
        let query = PlaceQuery(text: "Coffee", category: .cafe, location: location)
        let far = place("far", distance: 2_000, open: true)
        let near = place("near", distance: 100, open: true)
        let closed = place("closed", distance: 10, open: false)
        #expect(PlaceRanker().rank([far, near, closed], query: query).map(\.id) == ["near", "far", "closed"])
        #expect(PlaceRanker().rank([near, near], query: query).map(\.id) == ["near", "near"])
    }

    @Test func freshnessConfidenceAndVerifiedTravelTimeAreBehavioralRankingInputs() {
        let now = Date.now
        var quick = place("quick", distance: 2_000, open: true)
        quick.travelTimeSeconds = 120
        quick.confidence = 1
        var slow = place("slow", distance: 100, open: true)
        slow.travelTimeSeconds = 1_800
        slow.confidence = 0.2
        let query = PlaceQuery(text: "Coffee", category: .cafe, location: location)
        #expect(PlaceRanker().rank([slow, quick], query: query).first?.id == "quick")
        #expect(quick.freshness(now: now, recentFor: 900) == .recent)
        var stale = quick
        stale = .init(id: stale.id, providerID: stale.providerID, name: stale.name,
                      category: stale.category, latitude: stale.latitude, longitude: stale.longitude,
                      distanceMeters: stale.distanceMeters, travelTimeSeconds: stale.travelTimeSeconds,
                      isOpenNow: stale.isOpenNow, source: stale.source,
                      timestamp: now.addingTimeInterval(-901), verification: stale.verification,
                      confidence: stale.confidence)
        #expect(stale.freshness(now: now, recentFor: 900) == .stale)
    }

    @Test func explicitNearestIntentUsesPhysicalDistanceBeforeProviderScore() {
        let far = place("far", distance: 1_200, open: true)
        let unknown = place("unknown", distance: nil, open: true)
        let near = place("near", distance: 80, open: false)
        #expect(PlaceProximityOrdering().nearestFirst([far, unknown, near]).map(\.id) == ["near", "far", "unknown"])
    }
}
