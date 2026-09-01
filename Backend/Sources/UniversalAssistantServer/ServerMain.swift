import Foundation

public enum HealthStatus: String, Codable, Sendable { case healthy, degraded }

public struct HealthResponse: Codable, Equatable, Sendable {
    public let status: HealthStatus
    public let version: String
    public init(status: HealthStatus = .healthy, version: String = "v1") {
        self.status = status
        self.version = version
    }
}

@main
struct UniversalAssistantServer {
    static func main() {
        let response = HealthResponse()
        if let data = try? JSONEncoder().encode(response), let output = String(data: data, encoding: .utf8) {
            print(output)
        }
    }
}
