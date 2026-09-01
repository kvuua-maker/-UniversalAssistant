import Foundation

actor WeatherContextEngine {
    private let provider: any WeatherProvider
    private let timeout: Duration

    init(provider: any WeatherProvider, timeout: Duration = .seconds(10)) {
        self.provider = provider
        self.timeout = timeout
    }

    func weather(for request: WeatherRequest) async throws -> WeatherSnapshot {
        let request = try request.validated()
        return try await withThrowingTaskGroup(of: WeatherSnapshot.self) { group in
            group.addTask { try await self.provider.weather(for: request) }
            group.addTask {
                try await Task.sleep(for: self.timeout)
                throw WeatherProviderError.timedOut
            }
            guard let result = try await group.next() else { throw WeatherProviderError.unavailable }
            group.cancelAll()
            return result
        }
    }
}

enum LocationRecoveryAction: String, Equatable, Sendable {
    case none, retry, useManualLocation, openSettings
}

struct LocationRecoveryPolicy: Sendable {
    func actions(state: AccurateLocationState, location: ValidatedLocation?) -> [LocationRecoveryAction] {
        if state == .denied { return [.openSettings, .useManualLocation] }
        guard let location else {
            return state == .idle ? [.none] : [.retry, .useManualLocation]
        }
        switch location.quality {
        case .poor, .suspicious, .unavailable:
            return [.retry, .useManualLocation]
        case .precise, .good, .approximate:
            return [.none]
        }
    }
}
