import Foundation
import Vapor

public enum HealthStatus: String, Codable, Sendable { case healthy, degraded }

public struct HealthResponse: Content, Codable, Equatable, Sendable {
    public let status: HealthStatus
    public let version: String
    public init(status: HealthStatus = .healthy, version: String = "v1") {
        self.status = status
        self.version = version
    }
}

@main
struct UniversalAssistantServer {
    static func main() async throws {
        let environment = try Environment.detect()
        let app = try await Application.make(environment)
        defer { Task { try await app.asyncShutdown() } }
        app.http.server.configuration.hostname = Environment.get("UA_SERVER_HOST") ?? "127.0.0.1"
        app.http.server.configuration.port = Int(Environment.get("UA_SERVER_PORT") ?? "8787") ?? 8787
        let storage = Environment.get("UA_DIAGNOSTIC_STORAGE") ?? "/var/lib/universalassistant-diagnostics"
        try app.configurePhysicalDiagnostics(storageRoot: URL(fileURLWithPath: storage, isDirectory: true))
        // Jobs marketplace: previously compiled but never mounted. The route
        // surface is required by JOBS-097 (public vacancy search) and by the
        // canonical "OUR JOBS FIRST" source ordering.
        try app.configureJobsRoutes(storageRoot: URL(fileURLWithPath: storage, isDirectory: true))
        try app.configureTokenAIRoutes()
        try await app.execute()
    }
}
