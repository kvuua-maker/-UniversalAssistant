import Foundation

struct PlaceProviderFailure: Equatable, Sendable { let providerID: String; let reason: String }
struct PlaceSearchResponse: Equatable, Sendable { let places: [Place]; let failures: [PlaceProviderFailure] }

actor PlaceSearchEngine {
    private let providers: [any PlaceProvider]
    private let timeout: Duration
    private let deduplicator = PlaceDeduplicator()
    private let ranker = PlaceRanker()

    init(providers: [any PlaceProvider], maximumProviders: Int = 4, timeout: Duration = .seconds(4)) {
        self.providers = Array(providers.prefix(max(1, maximumProviders)))
        self.timeout = timeout
    }

    func search(_ input: PlaceQuery) async throws -> PlaceSearchResponse {
        let query = try input.validated()
        let batches = await withTaskGroup(of: ProviderBatch.self, returning: [ProviderBatch].self) { group in
            for provider in providers {
                group.addTask { [timeout] in await Self.fetch(provider, query: query, timeout: timeout) }
            }
            var output: [ProviderBatch] = []
            for await batch in group { output.append(batch) }
            return output
        }
        var places: [Place] = [], failures: [PlaceProviderFailure] = []
        for batch in batches {
            switch batch {
            case .success(_, let values): places.append(contentsOf: values)
            case .failure(let provider, let reason): failures.append(.init(providerID: provider, reason: reason))
            }
        }
        return .init(
            places: ranker.rank(deduplicator.deduplicate(places), query: query),
            failures: failures.sorted { $0.providerID < $1.providerID }
        )
    }

    private static func fetch(_ provider: any PlaceProvider, query: PlaceQuery, timeout: Duration) async -> ProviderBatch {
        do {
            return try await withThrowingTaskGroup(of: [Place].self) { group in
                group.addTask { try await provider.search(query) }
                group.addTask { try await Task.sleep(for: timeout); throw PlaceSearchFailure.timeout }
                guard let first = try await group.next() else { throw PlaceSearchFailure.empty }
                group.cancelAll()
                return .success(provider.providerID, first)
            }
        } catch is CancellationError { return .failure(provider.providerID, "cancelled") }
        catch PlaceSearchFailure.timeout { return .failure(provider.providerID, "timeout") }
        catch { return .failure(provider.providerID, "provider_error") }
    }
}

private enum PlaceSearchFailure: Error { case timeout, empty }
private enum ProviderBatch: Sendable {
    case success(String, [Place])
    case failure(String, String)
}
