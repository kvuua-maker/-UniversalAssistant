import Foundation

struct ProviderOperation<Output: Sendable>: Sendable {
    let providerID: String
    let run: @Sendable () async throws -> [Output]
}

struct ProviderFailure: Equatable, Sendable {
    let providerID: String
    let reason: String
}

enum ProviderFanoutCoverage: String, Equatable, Sendable {
    case complete, partial, failed
}

struct ProviderFanoutResponse<Output: Sendable>: Sendable {
    let values: [Output]
    let failures: [ProviderFailure]
    let coverage: ProviderFanoutCoverage
}

enum ProviderFanoutError: Error, Equatable, Sendable {
    case invalidConfiguration
}

struct ProviderFanoutEngine<Output: Sendable>: Sendable {
    let timeout: Duration
    let maximumProviders: Int

    init(timeout: Duration = .seconds(5), maximumProviders: Int = 8) {
        self.timeout = timeout
        self.maximumProviders = maximumProviders
    }

    func execute(_ operations: [ProviderOperation<Output>]) async throws -> ProviderFanoutResponse<Output> {
        guard timeout > .zero, maximumProviders > 0,
              !operations.isEmpty, operations.count <= maximumProviders,
              Set(operations.map(\.providerID)).count == operations.count,
              operations.allSatisfy({ !$0.providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw ProviderFanoutError.invalidConfiguration }

        var indexed: [(Int, [Output])] = []
        var failures: [(Int, ProviderFailure)] = []
        var wasCancelled = false
        await withTaskGroup(of: ProviderOperationResult<Output>.self) { group in
            for (index, operation) in operations.enumerated() {
                group.addTask { await fetch(operation, index: index) }
            }
            for await result in group {
                switch result {
                case let .success(index, values): indexed.append((index, values))
                case let .failure(index, failure): failures.append((index, failure))
                case .cancelled:
                    wasCancelled = true
                    group.cancelAll()
                }
            }
        }
        if wasCancelled || Task.isCancelled { throw CancellationError() }
        let values = indexed.sorted { $0.0 < $1.0 }.flatMap(\.1)
        let orderedFailures = failures.sorted { $0.0 < $1.0 }.map(\.1)
        let coverage: ProviderFanoutCoverage = orderedFailures.isEmpty ? .complete : (values.isEmpty ? .failed : .partial)
        return .init(values: values, failures: orderedFailures, coverage: coverage)
    }

    private func fetch(_ operation: ProviderOperation<Output>, index: Int) async -> ProviderOperationResult<Output> {
        do {
            let values = try await withThrowingTaskGroup(of: [Output].self) { group in
                group.addTask { try await operation.run() }
                group.addTask { try await Task.sleep(for: timeout); throw ProviderTimeout.timeout }
                let first = try await group.next() ?? []
                group.cancelAll()
                return first
            }
            return .success(index, values)
        } catch ProviderTimeout.timeout {
            return .failure(index, .init(providerID: operation.providerID, reason: "timeout"))
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure(index, .init(providerID: operation.providerID, reason: "provider_error"))
        }
    }
}

private enum ProviderOperationResult<Output: Sendable>: Sendable {
    case success(Int, [Output])
    case failure(Int, ProviderFailure)
    case cancelled
}

private enum ProviderTimeout: Error { case timeout }
